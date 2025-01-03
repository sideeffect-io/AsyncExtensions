//
//  AsyncHandleEventsSequenceTests.swift
//
//
//  Created by Thibault Wittemberg on 01/01/2022.
//

@testable import AsyncExtensions
import XCTest

final class AsyncHandleEventsSequenceTests: XCTestCase {
  func test_iteration_calls_blocks_when_not_cancelled_and_no_error() async throws {
    let received = ManagedCriticalState([String]())

    let sourceSequence = [1, 2, 3, 4, 5].async
    let sut = sourceSequence.handleEvents {
      received.withCriticalRegion { $0.append("start") }
    } onElement: { element in
      received.withCriticalRegion { $0.append("\(element)") }
    } onCancel: {
      received.withCriticalRegion { $0.append("cancelled") }
    } onFinish: { completion in
      received.withCriticalRegion { $0.append("finish \(completion)") }
    }

    for try await _ in sut {}

    XCTAssertEqual(received.criticalState, ["start", "1", "2", "3", "4", "5", "finish finished"])
  }

  func test_iteration_calls_onCancel_when_task_is_cancelled() async {
    let firstElementHasBeenReceivedExpectation = expectation(description: "First element has been emitted")
    let taskHasBeenCancelledExpectation = expectation(description: "The task has been cancelled")
    let onCancelHasBeenCalledExpectation = expectation(description: "OnCancel has been called")

    let received = ManagedCriticalState([String]())

    let sourceSequence = AsyncCurrentValueSubject<Int>(1)
    let sut = sourceSequence.handleEvents {
      received.withCriticalRegion { $0.append("start") }
    } onElement: { element in
      received.withCriticalRegion { $0.append("\(element)") }
    } onCancel: {
      received.withCriticalRegion { $0.append("cancelled") }
      onCancelHasBeenCalledExpectation.fulfill()
    } onFinish: { completion in
      received.withCriticalRegion { $0.append("finish \(completion)") }
    }

    let task = Task {
      for try await element in sut {
        if element == 1 {
          firstElementHasBeenReceivedExpectation.fulfill()
        }

        await fulfillment(of: [taskHasBeenCancelledExpectation], timeout: 1)
      }
    }

    await fulfillment(of: [firstElementHasBeenReceivedExpectation], timeout: 1)

    task.cancel()

    taskHasBeenCancelledExpectation.fulfill()

    await fulfillment(of: [onCancelHasBeenCalledExpectation], timeout: 1)

    XCTAssertEqual(received.criticalState, ["start", "1", "cancelled"])
  }

  func test_iteration_calls_onFinish_with_failure_when_sequence_fails() async throws {
    let onFinishHasBeenCalledExpectation = expectation(description: "OnFinish has been called")

    let received = ManagedCriticalState([String]())

    let expectedError = MockError(code: Int.random(in: 0...100))

    let sourceSequence = AsyncFailSequence<Int>(expectedError)
    let sut = sourceSequence.handleEvents {
      received.withCriticalRegion { $0.append("start") }
    } onElement: { element in
      received.withCriticalRegion { $0.append("\(element)") }
    } onCancel: {
      received.withCriticalRegion { $0.append("cancelled") }
    } onFinish: { completion in
      if case let .failure(error) = completion {
        XCTAssertEqual(error as? MockError, expectedError)
      }
      onFinishHasBeenCalledExpectation.fulfill()
    }

    do {
      for try await _ in sut {}
    } catch {
      XCTAssertEqual(error as? MockError, expectedError)
    }

    await fulfillment(of: [onFinishHasBeenCalledExpectation], timeout: 1)
  }

  func test_iteration_finishes_when_task_is_cancelled() async {
    let canCancelExpectation = expectation(description: "The first element has been emitted")
    let hasCancelExceptation = expectation(description: "The task has been cancelled")
    let taskHasFinishedExpectation = expectation(description: "The task has finished")

    let sut = (0...1_000_000)

    let handledSequence = sut.async.handleEvents()

    let task = Task {
      var firstElement: Int?
      for try await element in handledSequence {
        firstElement = element
        canCancelExpectation.fulfill()
        await fulfillment(of: [hasCancelExceptation], timeout: 5)
      }
      XCTAssertEqual(firstElement, 0)
      taskHasFinishedExpectation.fulfill()
    }

    await fulfillment(of: [canCancelExpectation], timeout: 5) // one element has been emitted, we can cancel the task

    task.cancel()

    hasCancelExceptation.fulfill() // we can release the lock in the for loop

    await fulfillment(of: [taskHasFinishedExpectation], timeout: 5) // task has been cancelled and has finished
  }
}
