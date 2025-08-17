//
//  AsyncBufferedChannelTests.swift
//  
//
//  Created by Thibault WITTEMBERG on 06/08/2022.
//

@testable import AsyncExtensions
import XCTest

final class AsyncBufferedChannelTests: XCTestCase {
  func test_send_queues_elements_and_delivers_to_one_consumer() async {
    let expected = [1, 2, 3, 4, 5]

    // Given
    let sut = AsyncBufferedChannel<Int>()

    // When
    sut.send(1)
    sut.send(2)
    sut.send(3)
    sut.send(4)
    sut.send(5)
    sut.finish()

    var received = [Int]()
    for await element in sut {
      received.append(element)
    }

    // Then
    XCTAssertEqual(received, expected)
  }

  func test_send_resumes_awaiting() async {
    let iterationIsAwaiting = expectation(description: "Iteration is awaiting")
    let expected = 1

    // Given
    let sut = AsyncBufferedChannel<Int>()

    let task = Task<Int?, Never> {
      let received = await sut.next {
        iterationIsAwaiting.fulfill()
      }
      return received
    }

    await fulfillment(of: [iterationIsAwaiting], timeout: 1.0)

    // When
    sut.send(1)

    let received = await task.value

    // Then
    XCTAssertEqual(received, expected)
  }

  func test_send_from_several_producers_queues_elements_and_delivers_to_several_consumers() async {
    let expected1 = Set((1...24))
    let expected2 = Set((25...50))
    let expected = expected1.union(expected2)

    // Given
    let sut = AsyncBufferedChannel<Int>()

    // When
    let sendTask1 = Task {
      for i in expected1 {
        sut.send(i)
      }
    }

    let sendTask2 = Task {
      for i in expected2 {
        sut.send(i)
      }
    }

    await sendTask1.value
    await sendTask2.value

    sut.finish()

    let task1 = Task<[Int], Never> {
      var received = [Int]()
      for await element in sut {
        received.append(element)
      }
      return received
    }

    let task2 = Task<[Int], Never> {
      var received = [Int]()
      for await element in sut {
        received.append(element)
      }
      return received
    }

    let received1 = await task1.value
    let received2 = await task2.value

    let received: Set<Int> = Set(received1).union(received2)

    // Then
    XCTAssertEqual(received, expected)
  }

  func test_asyncBufferedChannel_ends_iteration_when_task_is_cancelled() async {
    let taskCanBeCancelled = expectation(description: "The can be cancelled")
    let taskWasCancelled = expectation(description: "The task was cancelled")
    let iterationHasFinished = expectation(description: "The iteration we finished")

    let sut = AsyncBufferedChannel<Int>()
    sut.send(1)
    sut.send(2)
    sut.send(3)
    sut.send(4)
    sut.send(5)

    let task = Task<Int?, Never> {
      var received: Int?
      for await element in sut {
        received = element
        taskCanBeCancelled.fulfill()
        await fulfillment(of: [taskWasCancelled], timeout: 1.0)
      }
      iterationHasFinished.fulfill()
      return received
    }

    await fulfillment(of: [taskCanBeCancelled], timeout: 1.0)

    // When
    task.cancel()
    taskWasCancelled.fulfill()

    await fulfillment(of: [iterationHasFinished], timeout: 1.0)

    // Then
    let received = await task.value
    XCTAssertEqual(received, 1)
  }

  func test_finished_ends_awaiting_consumers_and_immediately_resumes_pastEnd() async throws {
    let iteration1IsAwaiting = expectation(description: "")
    let iteration1IsFinished = expectation(description: "")

    let iteration2IsAwaiting = expectation(description: "")
    let iteration2IsFinished = expectation(description: "")

    // Given
    let sut = AsyncBufferedChannel<Int>()

    let task1 = Task<Int?, Never> {
      let received = await sut.next {
        iteration1IsAwaiting.fulfill()
      }
      iteration1IsFinished.fulfill()
      return received
    }

    let task2 = Task<Int?, Never> {
      let received = await sut.next {
        iteration2IsAwaiting.fulfill()
      }
      iteration2IsFinished.fulfill()
      return received
    }

    await fulfillment(of: [iteration1IsAwaiting, iteration2IsAwaiting], timeout: 1.0)

    // When
    sut.finish()

    await fulfillment(of: [iteration1IsFinished, iteration2IsFinished], timeout: 1.0)

    let received1 = await task1.value
    let received2 = await task2.value

    XCTAssertNil(received1)
    XCTAssertNil(received2)

    let iterator = sut.makeAsyncIterator()
    let received = await iterator.next()
    XCTAssertNil(received)
  }

  func test_send_does_not_queue_when_already_finished() async {
    // Given
    let sut = AsyncBufferedChannel<Int>()

    // When
    sut.finish()
    sut.send(1)

    // Then
    let iterator = sut.makeAsyncIterator()
    let received = await iterator.next()

    XCTAssertNil(received)
  }

  func test_cancellation_immediately_resumes_when_already_finished() async {
    let iterationIsFinished = expectation(description: "The task was cancelled")

    // Given
    let sut = AsyncBufferedChannel<Int>()
    sut.finish()

    // When
    Task {
      for await _ in sut {}
      iterationIsFinished.fulfill()
    }.cancel()

    // Then
    await fulfillment(of: [iterationIsFinished], timeout: 1.0)
  }

  func test_awaiting_uses_id_for_equatable() {
    // Given
    let awaiting1 = AsyncBufferedChannel<Int>.Awaiting.placeHolder(id: 1)
    let awaiting2 = AsyncBufferedChannel<Int>.Awaiting.placeHolder(id: 2)
    let awaiting3 = AsyncBufferedChannel<Int>.Awaiting.placeHolder(id: 1)

    // When
    // Then
    XCTAssertEqual(awaiting1, awaiting3)
    XCTAssertNotEqual(awaiting1, awaiting2)
  }
}
