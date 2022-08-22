//
//  AsyncSequence+FlatMapLatestTests.swift
//
//
//  Created by Thibault Wittemberg on 10/01/2022.
//

@testable import AsyncExtensions
import XCTest

private extension DispatchTimeInterval {
  var nanoseconds: UInt64 {
    switch self {
      case .nanoseconds(let value) where value >= 0: return UInt64(value)
      case .microseconds(let value) where value >= 0: return UInt64(value) * 1000
      case .milliseconds(let value) where value >= 0: return UInt64(value) * 1_000_000
      case .seconds(let value) where value >= 0: return UInt64(value) * 1_000_000_000
      case .never: return .zero
      default: return .zero
    }
  }
}

private actor Spy {
  var elements = [Int]()

  func register(_ element: Int) {
    self.elements.append(element)
  }

  func assertElementsEqual(_ elements: [Int]) {
    XCTAssertEqual(self.elements, elements)
  }
}

private struct LongAsyncSequence: AsyncSequence, AsyncIteratorProtocol {
  typealias Element = Int
  typealias AsyncIterator = LongAsyncSequence

  var elements: IndexingIterator<[Element]>
  let interval: DispatchTimeInterval
  let onCancel: () -> Void

  init(elements: [Element], interval: DispatchTimeInterval = .seconds(0), onCancel: @escaping () -> Void) {
    self.onCancel = onCancel
    self.elements = elements.makeIterator()
    self.interval = interval
  }

  mutating func next() async throws -> Element? {
    guard !Task.isCancelled else {
      self.onCancel()
      return nil
    }

    let onCancel = self.onCancel

    return try await withTaskCancellationHandler {
      try await Task.sleep(nanoseconds: self.interval.nanoseconds)
      return self.elements.next()
    } onCancel: {
      onCancel()
    }
  }

  func makeAsyncIterator() -> AsyncIterator {
    self
  }
}

private struct TimedAsyncSequence<Element>: AsyncSequence, AsyncIteratorProtocol {
  typealias Element = Element
  typealias AsyncIterator = TimedAsyncSequence

  private let intervalInMills: [UInt64]
  private var iterator: Array<Element>.Iterator
  private var index = 0
  private let indexOfError: Int?

  init(intervalInMills: [UInt64], sequence: [Element], indexOfError: Int? = nil) {
    self.intervalInMills = intervalInMills
    self.iterator = sequence.makeIterator()
    self.indexOfError = indexOfError
  }

  mutating func next() async throws -> Element? {

    if let indexOfError = self.indexOfError, self.index == indexOfError {
      throw MockError(code: 1)
    }

    if self.index < self.intervalInMills.count {
      try await Task.sleep(nanoseconds: self.intervalInMills[index] * 1_000_000)
      self.index += 1
    }
    return self.iterator.next()
  }

  func makeAsyncIterator() -> AsyncIterator {
    self
  }
}

final class AsyncSequence_FlatMapLatestTests: XCTestCase {
  func testFlatMapLatest_emits_elements_from_newest_sequence_and_cancels_previous_sequences() async throws {
    // ---- 50 ------- 500 ---------- 1000 -------------------------------
    // -------- 70 ------------ 750 --------------------------------------
    // -------------------- 520 ---------------------------------- 1520 --
    // ------------------------------------ 1100 -- 1200 -- 1300 ---------
    // ---- 1 -- a ---- 2 -- c ------- 3 --- e ----- f ------ g ----------
    //
    // output should be: a c e f g
    // childAsyncSequence1 and childAsyncSequence2 will be cancelled
    let expectedElements = ["a", "c", "e", "f", "g"]
    let childAsyncSequence1Cancelled = ManagedCriticalState(false)
    let childAsyncSequence2Cancelled = ManagedCriticalState(false)
    let childAsyncSequence3Cancelled = ManagedCriticalState(false)

    let rootAsyncSequence = TimedAsyncSequence(intervalInMills: [50, 450, 500], sequence: [1, 2, 3])

    let childAsyncSequence1 = TimedAsyncSequence(intervalInMills: [20, 680], sequence: ["a", "b"])
      .handleEvents(onCancel: { childAsyncSequence1Cancelled.apply(criticalState: true) })

    let childAsyncSequence2 = TimedAsyncSequence(intervalInMills: [20, 1500], sequence: ["c", "d"])
      .handleEvents(onCancel: { childAsyncSequence2Cancelled.apply(criticalState: true) })

    let childAsyncSequence3 = TimedAsyncSequence(intervalInMills: [100, 100, 100], sequence: ["e", "f", "g"])
      .handleEvents(onCancel: { childAsyncSequence3Cancelled.apply(criticalState: true) })

    let sut = rootAsyncSequence.flatMapLatest { element -> AsyncHandleEventsSequence<TimedAsyncSequence<String>> in
      switch element {
        case 1: return childAsyncSequence1
        case 2: return childAsyncSequence2
        default: return childAsyncSequence3
      }
    }

    var receivedElements = [String]()

    for try await element in sut {
      receivedElements.append(element)
    }

    XCTAssertEqual(receivedElements, expectedElements)
    XCTAssertTrue(childAsyncSequence1Cancelled.criticalState)
    XCTAssertTrue(childAsyncSequence2Cancelled.criticalState)
    XCTAssertFalse(childAsyncSequence3Cancelled.criticalState)
  }

  func testFlatMapLatest_propagates_errors_when_transform_function_fails() async {
    let expectedError = MockError(code: Int.random(in: 0...100))

    let sut = [1, 2]
      .async
      .flatMapLatest { element throws -> AnyAsyncSequence<Int> in
        throw expectedError
      }

    do {
      for try await _ in sut {}
    } catch {
      XCTAssertEqual(error as? MockError, expectedError)
    }
  }

  func testFlatMapLatest_propagates_errors() async {
    let expectedError = MockError(code: Int.random(in: 0...100))

    let sut = AsyncLazySequence([1, 2])
      .flatMapLatest { element -> AnyAsyncSequence<Int> in
        if element == 1 {
          return AsyncLazySequence([1]).eraseToAnyAsyncSequence()
        }

        return AsyncFailSequence<Int>(expectedError).eraseToAnyAsyncSequence()
      }
      .eraseToAnyAsyncSequence()

    do {
      for try await _ in sut {}
    } catch {
      XCTAssertEqual(error as? MockError, expectedError)
    }
  }

  func testFlatMapLatest_finishes_when_task_is_cancelled_after_switched() {
    let canCancelExpectation = expectation(description: "The first element has been emitted")
    let hasCancelExceptation = expectation(description: "The task has been cancelled")
    let taskHasFinishedExpectation = expectation(description: "The task has finished")

    let sut = [1, 2, 3]
      .async
      .flatMapLatest { element in
        LongAsyncSequence(elements: [element], interval: .milliseconds(50), onCancel: {} )
      }

    let task = Task {
      var firstElement: Int?
      for try await element in sut {
        firstElement = element
        canCancelExpectation.fulfill()
        wait(for: [hasCancelExceptation], timeout: 5)
      }
      XCTAssertEqual(firstElement, 3)
      taskHasFinishedExpectation.fulfill()
    }

    wait(for: [canCancelExpectation], timeout: 5) // one element has been emitted, we can cancel the task

    task.cancel()

    hasCancelExceptation.fulfill() // we can release the lock in the for loop

    wait(for: [taskHasFinishedExpectation], timeout: 5) // task has been cancelled and has finished
  }

  func testFlatMapLatest_switches_to_latest_element() async throws {
    var receivedElement = [String]()

    let sut = [1, 2, 3]
      .async
      .flatMapLatest { element -> String in
        try await Task.sleep(nanoseconds: 50_000_000)
        return "a\(element)"
      }

    for try await element in sut {
      receivedElement.append(element)
    }

    XCTAssertEqual(receivedElement, ["a3"])
  }
}
