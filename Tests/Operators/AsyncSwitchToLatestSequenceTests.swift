//
//  AsyncSwitchToLatestSequence.swift
//  
//
//  Created by Thibault Wittemberg on 04/01/2022.
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
    return try await withTaskCancellationHandler {
      try await Task.sleep(nanoseconds: self.interval.nanoseconds)
      self.currentIndex += 1
      if self.currentIndex == self.failAt {
        throw MockError(code: 0)
      }
      return self.elements.next()
    } onCancel: { [onCancel] in
      onCancel()
    }
  }

  func makeAsyncIterator() -> AsyncIterator {
    self
  }
}

private struct NonCooperativeAsyncSequence<Element: Sendable>: AsyncSequence, Sendable {
  let onSuspend: @Sendable () -> Void

  func makeAsyncIterator() -> Iterator {
    Iterator(onSuspend: self.onSuspend)
  }

  struct Iterator: AsyncIteratorProtocol, Sendable {
    let onSuspend: @Sendable () -> Void

    mutating func next() async -> Element? {
      await withUnsafeContinuation { (_: UnsafeContinuation<Element?, Never>) in
        self.onSuspend()
      }
    }
  }
}

private struct IteratorLifetimeSequence<Element: Sendable>: AsyncSequence, Sendable {
  let element: Element
  let onIteratorCreated: @Sendable () -> Void
  let onIteratorReleased: @Sendable () -> Void

  func makeAsyncIterator() -> Iterator {
    self.onIteratorCreated()
    return Iterator(element: self.element, onReleased: self.onIteratorReleased)
  }

  final class Iterator: AsyncIteratorProtocol, Sendable {
    let element: Element
    let onReleased: @Sendable () -> Void
    let hasEmitted = ManagedCriticalState(false)

    init(element: Element, onReleased: @escaping @Sendable () -> Void) {
      self.element = element
      self.onReleased = onReleased
    }

    deinit {
      self.onReleased()
    }

    func next() async -> Element? {
      self.hasEmitted.withCriticalRegion { hasEmitted in
        guard !hasEmitted else { return nil }
        hasEmitted = true
        return self.element
      }
    }
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
      AsyncLazySequence([1, 2, 3]).eraseToAnyAsyncSequence(),
      AsyncLazySequence([4, 5, 6]).eraseToAnyAsyncSequence(),
      AsyncLazySequence([7, 8, 9]).eraseToAnyAsyncSequence(), // should fail here
      AsyncLazySequence([10, 11, 12]).eraseToAnyAsyncSequence(),
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
        await fulfillment(of: [hasCancelExceptation], timeout: 5)
      }
      XCTAssertEqual(firstElement, 3)
      taskHasFinishedExpectation.fulfill()
    }

    wait(for: [canCancelExpectation], timeout: 5) // one element has been emitted, we can cancel the task

    task.cancel()

    hasCancelExceptation.fulfill() // we can release the lock in the for loop

    wait(for: [taskHasFinishedExpectation], timeout: 5) // task has been cancelled and has finished
  }

  func testSwitchToLatest_finishes_when_awaiting_an_unfinished_latest_sequence_and_task_is_cancelled() async {
    let receivedFirstValue = expectation(description: "The first sequence emitted")
    let receivedSecondValue = expectation(description: "The second sequence emitted")
    let receivedLatestValue = expectation(description: "The latest sequence emitted")
    let collectionFinished = expectation(description: "The collection task finished")

    var outerContinuation: AsyncStream<AsyncBufferedChannel<Int>>.Continuation!
    let outer = AsyncStream<AsyncBufferedChannel<Int>> { continuation in
      outerContinuation = continuation
    }

    let collectionTask = Task {
      for await element in outer.switchToLatest() {
        switch element {
          case 1: receivedFirstValue.fulfill()
          case 2: receivedSecondValue.fulfill()
          case 4: receivedLatestValue.fulfill()
          default: XCTFail("Received unexpected element: \(element)")
        }
      }
      collectionFinished.fulfill()
    }

    let first = AsyncBufferedChannel<Int>()
    first.send(1)
    outerContinuation.yield(first)
    await fulfillment(of: [receivedFirstValue], timeout: 1)

    let second = AsyncBufferedChannel<Int>()
    second.send(2)
    outerContinuation.yield(second)
    await fulfillment(of: [receivedSecondValue], timeout: 1)

    let latest = AsyncBufferedChannel<Int>()
    latest.send(4)
    outerContinuation.yield(latest)
    await fulfillment(of: [receivedLatestValue], timeout: 1)

    collectionTask.cancel()

    await fulfillment(of: [collectionFinished], timeout: 1)
  }

  func testSwitchToLatest_finishes_when_awaiting_a_non_cooperative_outer_sequence_and_task_is_cancelled() async {
    let outerSequenceIsSuspended = expectation(description: "The outer sequence is suspended")
    let collectionFinished = expectation(description: "The collection task finished")
    let outer = NonCooperativeAsyncSequence<AsyncBufferedChannel<Int>> {
      outerSequenceIsSuspended.fulfill()
    }

    let collectionTask = Task {
      for await _ in outer.switchToLatest() {}
      collectionFinished.fulfill()
    }

    await fulfillment(of: [outerSequenceIsSuspended], timeout: 1)
    await Task.yield()

    collectionTask.cancel()

    await fulfillment(of: [collectionFinished], timeout: 1)
  }

  func testSwitchToLatest_releases_previous_iterator_when_new_sequence_arrives_between_downstream_calls() async throws {
    let firstIteratorCreated = expectation(description: "The first iterator was created")
    let firstIteratorReleased = expectation(description: "The first iterator was released")
    let secondIteratorCreated = expectation(description: "The second iterator was created")
    let (outer, continuation) = AsyncStream<IteratorLifetimeSequence<Int>>.makeStream()
    var iterator = outer.switchToLatest().makeAsyncIterator()

    continuation.yield(
      IteratorLifetimeSequence(
        element: 1,
        onIteratorCreated: { firstIteratorCreated.fulfill() },
        onIteratorReleased: { firstIteratorReleased.fulfill() }
      )
    )

    let firstValue = await iterator.next()
    XCTAssertEqual(firstValue, 1)
    await fulfillment(of: [firstIteratorCreated], timeout: 1)

    continuation.yield(
      IteratorLifetimeSequence(
        element: 2,
        onIteratorCreated: { secondIteratorCreated.fulfill() },
        onIteratorReleased: {}
      )
    )

    await fulfillment(of: [secondIteratorCreated, firstIteratorReleased], timeout: 1)
    continuation.finish()
  }
}
