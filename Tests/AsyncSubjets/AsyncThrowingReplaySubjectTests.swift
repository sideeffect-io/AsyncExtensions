//
//  AsyncThrowingReplaySubjectTests.swift
//
//
//  Created by Thibault Wittemberg on 02/01/2022.
//

@testable import AsyncExtensions
import XCTest

final class AsyncThrowingReplaySubjectTests: XCTestCase {
  func test_send_replays_buffered_elements() {
    let exp = expectation(description: "Send has stacked elements in the replay the buffer")
    exp.expectedFulfillmentCount = 2

    let expectedResult = [2, 3, 4, 5, 6]

    let sut = AsyncThrowingReplaySubject<Int, Error>(bufferSize: 5)
    sut.send(1)
    sut.send(2)
    sut.send(3)
    sut.send(4)
    sut.send(5)
    sut.send(6)

    Task {
      var receivedElements = [Int]()

      for try await element in sut {
        receivedElements.append(element)
        if element == 6 {
          XCTAssertEqual(receivedElements, expectedResult)
          exp.fulfill()
        }
      }
    }

    Task {
      var receivedElements = [Int]()

      for try await element in sut {
        receivedElements.append(element)
        if element == 6 {
          XCTAssertEqual(receivedElements, expectedResult)
          exp.fulfill()
        }
      }
    }

    waitForExpectations(timeout: 0.5)
  }

  func test_send_pushes_elements_in_the_subject() {
    let hasReceivedOneElementExpectation = expectation(description: "One element has been iterated in the async sequence")
    hasReceivedOneElementExpectation.expectedFulfillmentCount = 2

    let hasReceivedSentElementsExpectation = expectation(description: "Send pushes elements in created AsyncSequences")
    hasReceivedSentElementsExpectation.expectedFulfillmentCount = 2

    let expectedResult = [1, 2, 3]

    let sut = AsyncThrowingReplaySubject<Int, Error>(bufferSize: 5)

    sut.send(1)

    Task {
      var receivedElements = [Int]()

      for try await element in sut {
        if element == 1 {
          hasReceivedOneElementExpectation.fulfill()
        }
        receivedElements.append(element)
        if element == 3 {
          XCTAssertEqual(receivedElements, expectedResult)
          hasReceivedSentElementsExpectation.fulfill()
        }
      }
    }

    Task {
      var receivedElements = [Int]()

      for try await element in sut {
        if element == 1 {
          hasReceivedOneElementExpectation.fulfill()
        }
        receivedElements.append(element)
        if element == 3 {
          XCTAssertEqual(receivedElements, expectedResult)
          hasReceivedSentElementsExpectation.fulfill()
        }
      }
    }

    wait(for: [hasReceivedOneElementExpectation], timeout: 1)

    sut.send(2)
    sut.send(3)

    wait(for: [hasReceivedSentElementsExpectation], timeout: 1)
  }

  func test_sendFinished_ends_the_subject_and_immediately_resumes_futur_consumer() async throws {
    let hasReceivedOneElementExpectation = expectation(description: "One element has been iterated in the async sequence")
    hasReceivedOneElementExpectation.expectedFulfillmentCount = 2

    let hasFinishedExpectation = expectation(description: "Send(.finished) finishes all created AsyncSequences")
    hasFinishedExpectation.expectedFulfillmentCount = 2

    let sut = AsyncThrowingReplaySubject<Int, Error>(bufferSize: 1)

    sut.send(1)

    Task {
      for try await element in sut {
        if element == 1 {
          hasReceivedOneElementExpectation.fulfill()
        }
      }
      hasFinishedExpectation.fulfill()
    }

    Task {
      for try await element in sut {
        if element == 1 {
          hasReceivedOneElementExpectation.fulfill()
        }
      }
      hasFinishedExpectation.fulfill()
    }

    wait(for: [hasReceivedOneElementExpectation], timeout: 1)

    sut.send(.finished)

    wait(for: [hasFinishedExpectation], timeout: 1)

    var iterator = sut.makeAsyncIterator()
    let received = try await iterator.next()
    XCTAssertNil(received)
  }

  func test_sendFailure_ends_the_subject_with_an_error_and_immediately_resumes_futur_consumer_with_error() async {
    let hasReceivedOneElementExpectation = expectation(description: "One element has been iterated in the async sequence")
    hasReceivedOneElementExpectation.expectedFulfillmentCount = 2

    let hasFinishedWithFailureExpectation = expectation(description: "Send(.failure) finishes all created AsyncSequences with error")
    hasFinishedWithFailureExpectation.expectedFulfillmentCount = 2

    let expectedError = MockError(code: Int.random(in: 0...100))

    let sut = AsyncThrowingReplaySubject<Int, Error>(bufferSize: 1)

    sut.send(1)

    Task {
      do {
        for try await element in sut {
          if element == 1 {
            hasReceivedOneElementExpectation.fulfill()
          }
        }
      } catch {
        XCTAssertEqual(error as? MockError, expectedError)
        hasFinishedWithFailureExpectation.fulfill()
      }
    }

    Task {
      do {
        for try await element in sut {
          if element == 1 {
            hasReceivedOneElementExpectation.fulfill()
          }
        }
      } catch {
        XCTAssertEqual(error as? MockError, expectedError)
        hasFinishedWithFailureExpectation.fulfill()
      }
    }

    wait(for: [hasReceivedOneElementExpectation], timeout: 1)

    sut.send(.failure(expectedError))

    wait(for: [hasFinishedWithFailureExpectation], timeout: 1)

    var iterator = sut.makeAsyncIterator()
    do {
      _ = try await iterator.next()
      XCTFail("The iteration should immediately fail")
    } catch {
      XCTAssertEqual(error as? MockError, expectedError)
    }
  }

  func test_subject_finishes_when_task_is_cancelled() {
    let canCancelExpectation = expectation(description: "The first element has been emitted")
    let hasCancelExceptation = expectation(description: "The task has been cancelled")
    let taskHasFinishedExpectation = expectation(description: "The task has finished")

    let sut = AsyncThrowingReplaySubject<Int, Error>(bufferSize: 1)

    sut.send(1)

    let task = Task {
      var firstElement: Int?
      for try await element in sut {
        firstElement = element
        canCancelExpectation.fulfill()
        wait(for: [hasCancelExceptation], timeout: 5)
      }
      XCTAssertEqual(firstElement, 1)
      taskHasFinishedExpectation.fulfill()
    }

    wait(for: [canCancelExpectation], timeout: 5) // one element has been emitted, we can cancel the task

    task.cancel()

    hasCancelExceptation.fulfill() // we can release the lock in the for loop

    wait(for: [taskHasFinishedExpectation], timeout: 5) // task has been cancelled and has finished
  }

  func test_subject_handles_concurrency() async throws {
    let canSendExpectation = expectation(description: "Replay is ready to be sent values")
    canSendExpectation.expectedFulfillmentCount = 2

    let expectedElements = (0...2000).map { $0 }

    let sut = AsyncThrowingReplaySubject<Int, Error>(bufferSize: 0)

    // concurrently iterate the sut 1
    let taskA = Task { () -> [Int] in
      var received = [Int]()
      var iterator = sut.makeAsyncIterator()
      canSendExpectation.fulfill()
      while let element = try await iterator.next() {
        received.append(element)
      }
      return received.sorted()
    }

    // concurrently iterate the sut 2
    let taskB = Task { () -> [Int] in
      var received = [Int]()
      var iterator = sut.makeAsyncIterator()
      canSendExpectation.fulfill()
      while let element = try await iterator.next() {
        received.append(element)
      }
      return received.sorted()
    }

    await waitForExpectations(timeout: 1)

    // concurrently push values in the sut 1
    let task1 = Task {
      for index in (0...1000) {
        sut.send(index)
      }
    }

    // concurrently push values in the sut 2
    let task2 = Task {
      for index in (1001...2000) {
        sut.send(index)
      }
    }

    await task1.value
    await task2.value

    sut.send(.finished)

    let receivedElementsA = try await taskA.value
    let receivedElementsB = try await taskB.value

    XCTAssertEqual(receivedElementsA, expectedElements)
    XCTAssertEqual(receivedElementsB, expectedElements)
  }
}
