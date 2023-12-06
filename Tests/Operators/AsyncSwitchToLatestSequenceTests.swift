//
//  AsyncSwitchToLatestSequence.swift
//  
//
//  Created by Thibault Wittemberg on 04/01/2022.
//

import AsyncAlgorithms
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

private struct LongAsyncSequence<Element>: AsyncSequence, AsyncIteratorProtocol {
  typealias Element = Element
  typealias AsyncIterator = LongAsyncSequence

  var elements: IndexingIterator<[Element]>
  let interval: DispatchTimeInterval
  var currentIndex = -1
  let failAt: Int?
  var hasEmitted = false
  let onCancel: () -> Void

  init(elements: [Element], interval: DispatchTimeInterval = .seconds(0), failAt: Int? = nil, onCancel: @escaping () -> Void = {}) {
    self.onCancel = onCancel
    self.elements = elements.makeIterator()
    self.failAt = failAt
    self.interval = interval
  }

  mutating func next() async throws -> Element? {
    return try await withTaskCancellationHandler { [onCancel] in
      onCancel()
    } operation: {
      try await Task.sleep(nanoseconds: self.interval.nanoseconds)
      self.currentIndex += 1
      if self.currentIndex == self.failAt {
        throw MockError(code: 0)
      }
      return self.elements.next()
    }
  }

  func makeAsyncIterator() -> AsyncIterator {
    self
  }
}

final class AsyncSwitchToLatestSequenceTests: XCTestCase {
  func testSwitchToLatest_switches_to_latest_asyncSequence_and_cancels_previous_ones() async throws {
    var asyncSequence1IsCancelled = false
    var asyncSequence2IsCancelled = false
    var asyncSequence3IsCancelled = false

    let childAsyncSequence1 = LongAsyncSequence(
      elements: [1, 2, 3],
      interval: .milliseconds(200),
      onCancel: { asyncSequence1IsCancelled = true }
    )
      .prepend(0)
    let childAsyncSequence2 = LongAsyncSequence(
      elements: [5, 6, 7],
      interval: .milliseconds(200),
      onCancel: { asyncSequence2IsCancelled = true }
    )
      .prepend(4)
    let childAsyncSequence3 = LongAsyncSequence(
      elements: [9, 10, 11],
      interval: .milliseconds(200),
      onCancel: { asyncSequence3IsCancelled = true }
    )
      .prepend(8)

    let mainAsyncSequence = LongAsyncSequence(elements: [childAsyncSequence1, childAsyncSequence2, childAsyncSequence3],
                                              interval: .milliseconds(30),
                                              onCancel: {})

    let sut = mainAsyncSequence.switchToLatest()

    var receivedElements = [Int]()
    let expectedElements = [0, 4, 8, 9, 10, 11]
    for try await element in sut {
      receivedElements.append(element)
    }

    XCTAssertEqual(receivedElements, expectedElements)
    XCTAssertTrue(asyncSequence1IsCancelled)
    XCTAssertTrue(asyncSequence2IsCancelled)
    XCTAssertFalse(asyncSequence3IsCancelled)
  }

  func testSwitchToLatest_propagates_errors_when_base_sequence_fails() async {
    let sequences = [
      [1, 2, 3].async.eraseToAnyAsyncSequence(),
      [4, 5, 6].async.eraseToAnyAsyncSequence(),
      [7, 8, 9].async.eraseToAnyAsyncSequence(), // should fail here
      [10, 11, 12].async.eraseToAnyAsyncSequence(),
    ]

    let sourceSequence = LongAsyncSequence(elements: sequences, interval: .milliseconds(100), failAt: 2)

    let sut = sourceSequence.switchToLatest()

    var received = [Int]()

    do {
      for try await element in sut {
        received.append(element)
      }
      XCTFail("The sequence should fail")
    } catch {
      XCTAssertEqual(received, [1, 2, 3, 4, 5, 6])
      XCTAssert(error is MockError)
    }
  }

  func testSwitchToLatest_propagates_errors_when_child_sequence_fails() async {
    let expectedError = MockError(code: Int.random(in: 0...100))

    let sequences = [
      AsyncJustSequence(1).eraseToAnyAsyncSequence(),
      AsyncFailSequence<Int>(expectedError).eraseToAnyAsyncSequence(), // should fail
      AsyncJustSequence(2).eraseToAnyAsyncSequence()
    ]

    let sourceSequence = LongAsyncSequence(elements: sequences, interval: .milliseconds(100))

    let sut = sourceSequence.switchToLatest()

    var received = [Int]()

    do {
      for try await element in sut {
        received.append(element)
      }
      XCTFail("The sequence should fail")
    } catch {
      XCTAssertEqual(received, [1])
      XCTAssertEqual(error as? MockError, expectedError)
    }
  }

  func testSwitchToLatest_finishes_when_task_is_cancelled_after_switched() {
    let canCancelExpectation = expectation(description: "The first element has been emitted")
    let hasCancelExceptation = expectation(description: "The task has been cancelled")
    let taskHasFinishedExpectation = expectation(description: "The task has finished")

    let sourceSequence = [1, 2, 3].async
    let mappedSequence = sourceSequence.map { element in LongAsyncSequence(
      elements: [element],
      interval: .milliseconds(50),
      onCancel: {}
    )}
    let sut = mappedSequence.switchToLatest()

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
}
