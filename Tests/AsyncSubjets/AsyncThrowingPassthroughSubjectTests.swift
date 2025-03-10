//
//  AsyncThrowingPassthroughSubjectTests.swift
//
//
//  Created by Thibault Wittemberg on 10/01/2022.
//

@testable import AsyncExtensions
import XCTest

final class AsyncThrowingPassthroughSubjectTests: XCTestCase {
  func test_send_pushes_elements_in_the_subject() async {
    let isReadyToBeIteratedExpectation = expectation(description: "Passthrough subject iterators are ready for iteration")
    isReadyToBeIteratedExpectation.expectedFulfillmentCount = 2

    let hasReceivedSentElementsExpectation = expectation(description: "Send pushes elements in created AsyncSequences")
    hasReceivedSentElementsExpectation.expectedFulfillmentCount = 2

    let expectedResult = [1, 2, 3]

    let sut = AsyncThrowingPassthroughSubject<Int, Error>()

    Task {
      var receivedElements = [Int]()

      var it = sut.makeAsyncIterator()
      isReadyToBeIteratedExpectation.fulfill()
      while let element = try await it.next() {
        receivedElements.append(element)
        if element == 3 {
          XCTAssertEqual(receivedElements, expectedResult)
          hasReceivedSentElementsExpectation.fulfill()
        }
      }
    }

    Task {
      var receivedElements = [Int]()

      var it = sut.makeAsyncIterator()
      isReadyToBeIteratedExpectation.fulfill()
      while let element = try await it.next() {
        receivedElements.append(element)
        if element == 3 {
          XCTAssertEqual(receivedElements, expectedResult)
          hasReceivedSentElementsExpectation.fulfill()
        }
      }
    }

    await fulfillment(of: [isReadyToBeIteratedExpectation], timeout: 1)

    sut.send(1)
    sut.send(2)
    sut.send(3)

    await fulfillment(of: [hasReceivedSentElementsExpectation], timeout: 1)
  }

  func test_sendFinished_ends_the_subject_and_immediately_resumes_futur_consumer() async throws {
    let isReadyToBeIteratedExpectation = expectation(description: "Passthrough subject iterators are ready for iteration")
    isReadyToBeIteratedExpectation.expectedFulfillmentCount = 2

    let hasReceivedOneElementExpectation = expectation(description: "One element has been iterated in the async sequence")
    hasReceivedOneElementExpectation.expectedFulfillmentCount = 2

    let hasFinishedExpectation = expectation(description: "Send(.finished) finishes all created AsyncSequences")
    hasFinishedExpectation.expectedFulfillmentCount = 2

    let sut = AsyncThrowingPassthroughSubject<Int, Error>()

    Task {
      var it = sut.makeAsyncIterator()
      isReadyToBeIteratedExpectation.fulfill()
      while let element = try await it.next() {
        if element == 1 {
          hasReceivedOneElementExpectation.fulfill()
        }
      }
      hasFinishedExpectation.fulfill()
    }

    Task {
      var it = sut.makeAsyncIterator()
      isReadyToBeIteratedExpectation.fulfill()
      while let element = try await it.next() {
        if element == 1 {
          hasReceivedOneElementExpectation.fulfill()
        }
      }
      hasFinishedExpectation.fulfill()
    }

    await fulfillment(of: [isReadyToBeIteratedExpectation], timeout: 1)

    sut.send(1)

    await fulfillment(of: [hasReceivedOneElementExpectation], timeout: 1)

    sut.send( .finished)

    await fulfillment(of: [hasFinishedExpectation], timeout: 1)

    var iterator = sut.makeAsyncIterator()
    let received = try await iterator.next()
    XCTAssertNil(received)
  }

  func test_sendFailure_ends_the_subject_with_an_error_and_immediately_resumes_futur_consumer_with_error() async {
    let isReadyToBeIteratedExpectation = expectation(description: "Passthrough subject iterators are ready for iteration")
    isReadyToBeIteratedExpectation.expectedFulfillmentCount = 2

    let hasReceivedOneElementExpectation = expectation(description: "One element has been iterated in the async sequence")
    hasReceivedOneElementExpectation.expectedFulfillmentCount = 2

    let hasFinishedWithFailureExpectation = expectation(description: "Send(.failure) finishes all created AsyncSequences with error")
    hasFinishedWithFailureExpectation.expectedFulfillmentCount = 2

    let expectedError = MockError(code: Int.random(in: 0...100))

    let sut = AsyncThrowingPassthroughSubject<Int, Error>()

    Task {
      do {
        var it = sut.makeAsyncIterator()
        isReadyToBeIteratedExpectation.fulfill()
        while let element = try await it.next() {
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
        var it = sut.makeAsyncIterator()
        isReadyToBeIteratedExpectation.fulfill()
        while let element = try await it.next() {
          if element == 1 {
            hasReceivedOneElementExpectation.fulfill()
          }
        }
      } catch {
        XCTAssertEqual(error as? MockError, expectedError)
        hasFinishedWithFailureExpectation.fulfill()
      }
    }

    await fulfillment(of: [isReadyToBeIteratedExpectation], timeout: 1)

    sut.send(1)

    await fulfillment(of: [hasReceivedOneElementExpectation], timeout: 1)

    sut.send(.failure(expectedError))

    await fulfillment(of: [hasFinishedWithFailureExpectation], timeout: 1)

    var iterator = sut.makeAsyncIterator()
    do {
      _ = try await iterator.next()
      XCTFail("The iteration should immediately fail")
    } catch {
      XCTAssertEqual(error as? MockError, expectedError)
    }
  }

  func test_subject_finishes_when_task_is_cancelled() async {
    let isReadyToBeIteratedExpectation = expectation(description: "Passthrough subject iterators are ready for iteration")
    let canCancelExpectation = expectation(description: "The first element has been emitted")
    let hasCancelExpectation = expectation(description: "The task has been cancelled")
    let taskHasFinishedExpectation = expectation(description: "The task has finished")

    let sut = AsyncThrowingPassthroughSubject<Int, Error>()

    let task = Task {
      var receivedElements = [Int]()

      var it = sut.makeAsyncIterator()
      isReadyToBeIteratedExpectation.fulfill()
      while let element = try await it.next() {
        receivedElements.append(element)
        canCancelExpectation.fulfill()
        await fulfillment(of: [hasCancelExpectation], timeout: 5)
      }
      XCTAssertEqual(receivedElements, [1])
      taskHasFinishedExpectation.fulfill()
    }

    await fulfillment(of: [isReadyToBeIteratedExpectation], timeout: 1)

    sut.send(1)

    await fulfillment(of: [canCancelExpectation], timeout: 5) // one element has been emitted, we can cancel the task

    task.cancel()

    hasCancelExpectation.fulfill() // we can release the lock in the for loop

    await fulfillment(of: [taskHasFinishedExpectation], timeout: 5) // task has been cancelled and has finished
  }

  func test_subject_handles_concurrency() async throws {
    let canSendExpectation = expectation(description: "Passthrough is ready to be sent values")
    canSendExpectation.expectedFulfillmentCount = 2

    let expectedElements = (0...2000).map { $0 }

    let sut = AsyncThrowingPassthroughSubject<Int, Error>()

    // concurrently iterate the sut 1
    let taskA = Task<[Int], Error> {
      var received = [Int]()
      var iterator = sut.makeAsyncIterator()
      canSendExpectation.fulfill()
      while let element = try await iterator.next() {
        received.append(element)
      }
      return received.sorted()
    }

    // concurrently iterate the sut 2
    let taskB = Task<[Int], Error> {
      var received = [Int]()
      var iterator = sut.makeAsyncIterator()
      canSendExpectation.fulfill()
      while let element = try await iterator.next() {
        received.append(element)
      }
      return received.sorted()
    }

    await fulfillment(of: [canSendExpectation], timeout: 1)

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
