//
//  AsyncReplaySubjectTests.swift
//
//
//  Created by Thibault Wittemberg on 02/01/2022.
//

@testable import AsyncExtensions
import XCTest

final class AsyncReplaySubjectTests: XCTestCase {
  func test_send_replays_buffered_elements() {
    let exp = expectation(description: "Send has stacked elements in the replay the buffer")
    exp.expectedFulfillmentCount = 2

    let expectedResult = [2, 3, 4, 5, 6]

    let sut = AsyncReplaySubject<Int>(bufferSize: 5)
    sut.send(1)
    sut.send(2)
    sut.send(3)
    sut.send(4)
    sut.send(5)
    sut.send(6)

    Task {
      var receivedElements = [Int]()

      for await element in sut {
        receivedElements.append(element)
        if element == 6 {
          XCTAssertEqual(receivedElements, expectedResult)
          exp.fulfill()
        }
      }
    }

    Task {
      var receivedElements = [Int]()

      for await element in sut {
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

    let sut = AsyncReplaySubject<Int>(bufferSize: 5)

    sut.send(1)

    Task {
      var receivedElements = [Int]()

      for await element in sut {
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

      for await element in sut {
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

  func test_sendFinished_ends_the_subject_and_immediately_resumes_futur_consumer() async {
    let hasReceivedOneElementExpectation = expectation(description: "One element has been iterated in the async sequence")
    hasReceivedOneElementExpectation.expectedFulfillmentCount = 2

    let hasFinishedExpectation = expectation(description: "Send(.finished) finishes all created AsyncSequences")
    hasFinishedExpectation.expectedFulfillmentCount = 2

    let sut = AsyncReplaySubject<Int>(bufferSize: 1)

    sut.send(1)

    Task {
      for await element in sut {
        if element == 1 {
          hasReceivedOneElementExpectation.fulfill()
        }
      }
      hasFinishedExpectation.fulfill()
    }

    Task {
      for await element in sut {
        if element == 1 {
          hasReceivedOneElementExpectation.fulfill()
        }
      }
      hasFinishedExpectation.fulfill()
    }

    await fulfillment(of: [hasReceivedOneElementExpectation], timeout: 1)

    sut.send(.finished)

    await fulfillment(of: [hasFinishedExpectation], timeout: 1)

    var iterator = sut.makeAsyncIterator()
    let received = await iterator.next()
    XCTAssertNil(received)
  }

  func test_subject_finishes_when_task_is_cancelled() {
    let canCancelExpectation = expectation(description: "The first element has been emitted")
    let hasCancelExceptation = expectation(description: "The task has been cancelled")
    let taskHasFinishedExpectation = expectation(description: "The task has finished")

    let sut = AsyncReplaySubject<Int>(bufferSize: 1)

    sut.send(1)

    let task = Task {
      var firstElement: Int?
      for await element in sut {
        firstElement = element
        canCancelExpectation.fulfill()
        await fulfillment(of: [hasCancelExceptation], timeout: 5)
      }
      XCTAssertEqual(firstElement, 1)
      taskHasFinishedExpectation.fulfill()
    }

    wait(for: [canCancelExpectation], timeout: 5) // one element has been emitted, we can cancel the task

    task.cancel()

    hasCancelExceptation.fulfill() // we can release the lock in the for loop

    wait(for: [taskHasFinishedExpectation], timeout: 5) // task has been cancelled and has finished
  }

  func test_subject_handles_concurrency() async {
    let canSendExpectation = expectation(description: "Replay is ready to be sent values")
    canSendExpectation.expectedFulfillmentCount = 2

    let expectedElements = (0...2000).map { $0 }

    let sut = AsyncReplaySubject<Int>(bufferSize: 0)

    // concurrently iterate the sut 1
    let taskA = Task { () -> [Int] in
      var received = [Int]()
      var iterator = sut.makeAsyncIterator()
      canSendExpectation.fulfill()
      while let element = await iterator.next() {
        received.append(element)
      }
      return received.sorted()
    }

    // concurrently iterate the sut 2
    let taskB = Task { () -> [Int] in
      var received = [Int]()
      var iterator = sut.makeAsyncIterator()
      canSendExpectation.fulfill()
      while let element = await iterator.next() {
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

    let receivedElementsA = await taskA.value
    let receivedElementsB = await taskB.value

    XCTAssertEqual(receivedElementsA, expectedElements)
    XCTAssertEqual(receivedElementsB, expectedElements)
  }
}
