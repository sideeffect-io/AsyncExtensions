//
//  AsyncMulticastSequenceTests.swift
//
//
//  Created by Thibault Wittemberg on 21/02/2022.
//

import AsyncExtensions
import XCTest

private class SpyAsyncSequenceForNumberOfIterators<Element>: AsyncSequence {
  typealias Element = Element
  typealias AsyncIterator = Iterator
  
  let element: Element
  let numberOfTimes: Int
  
  var numberOfIterators = 0
  
  init(element: Element, numberOfTimes: Int) {
    self.element = element
    self.numberOfTimes = numberOfTimes
  }
  
  func makeAsyncIterator() -> AsyncIterator {
    self.numberOfIterators += 1
    return Iterator(element: self.element, numberOfTimes: self.numberOfTimes)
  }
  
  struct Iterator: AsyncIteratorProtocol {
    let element: Element
    var numberOfTimes: Int
    
    mutating func next() async throws -> Element? {
      guard self.numberOfTimes > 0 else { return nil }
      self.numberOfTimes -= 1
      return element
    }
  }
}

private struct CancellationAwareSequence: AsyncSequence {
  typealias Element = Int
  typealias AsyncIterator = Iterator

  let onStart: @Sendable () -> Void
  let onCancel: @Sendable () -> Void

  func makeAsyncIterator() -> AsyncIterator {
    Iterator(onStart: self.onStart, onCancel: self.onCancel)
  }

  struct Iterator: AsyncIteratorProtocol {
    let onStart: @Sendable () -> Void
    let onCancel: @Sendable () -> Void
    var hasStarted = false

    mutating func next() async throws -> Int? {
      if !hasStarted {
        hasStarted = true
        onStart()
      }

      do {
        try await Task.sleep(nanoseconds: 5_000_000_000)
        return nil
      } catch {
        onCancel()
        return nil
      }
    }
  }
}

final class AsyncMulticastSequenceTests: XCTestCase {
  func test_multiple_loops_receive_elements_from_single_baseIterator() {
    let taskHaveIterators = expectation(description: "All tasks have their iterator")
    taskHaveIterators.expectedFulfillmentCount = 2
    
    let tasksHaveFinishedExpectation = expectation(description: "Tasks have finished")
    tasksHaveFinishedExpectation.expectedFulfillmentCount = 2
    
    let spyUpstreamSequence = SpyAsyncSequenceForNumberOfIterators(element: 1, numberOfTimes: 3)
    let stream = AsyncThrowingPassthroughSubject<Int, Error>()
    let sut = spyUpstreamSequence.multicast(stream)
    
    Task {
      var receivedElement = [Int]()
      var iterator = sut.makeAsyncIterator()
      taskHaveIterators.fulfill()
      while let element = try await iterator.next() {
        receivedElement.append(element)
      }
      XCTAssertEqual(receivedElement, [1, 1, 1])
      tasksHaveFinishedExpectation.fulfill()
    }
    
    Task {
      var receivedElement = [Int]()
      var iterator = sut.makeAsyncIterator()
      taskHaveIterators.fulfill()
      while let element = try await iterator.next() {
        receivedElement.append(element)
      }
      XCTAssertEqual(receivedElement, [1, 1, 1])
      tasksHaveFinishedExpectation.fulfill()
    }
    
    wait(for: [taskHaveIterators], timeout: 1)
    
    sut.connect()
    
    wait(for: [tasksHaveFinishedExpectation], timeout: 1)
    
    XCTAssertEqual(spyUpstreamSequence.numberOfIterators, 1)
  }
  
  func test_multiple_loops_uses_provided_stream() {
    let taskHaveIterators = expectation(description: "All tasks have their iterator")
    taskHaveIterators.expectedFulfillmentCount = 3
    
    let tasksHaveFinishedExpectation = expectation(description: "Tasks have finished")
    tasksHaveFinishedExpectation.expectedFulfillmentCount = 3
    
    let stream = AsyncThrowingPassthroughSubject<Int, Error>()
    let spyUpstreamSequence = SpyAsyncSequenceForNumberOfIterators(element: 1, numberOfTimes: 3)
    let sut = spyUpstreamSequence.multicast(stream)
    
    Task {
      var receivedElement = [Int]()
      var iterator = sut.makeAsyncIterator()
      taskHaveIterators.fulfill()
      while let element = try await iterator.next() {
        receivedElement.append(element)
      }
      XCTAssertEqual(receivedElement, [1, 1, 1])
      tasksHaveFinishedExpectation.fulfill()
    }
    
    Task {
      var receivedElement = [Int]()
      var iterator = sut.makeAsyncIterator()
      taskHaveIterators.fulfill()
      while let element = try await iterator.next() {
        receivedElement.append(element)
      }
      XCTAssertEqual(receivedElement, [1, 1, 1])
      tasksHaveFinishedExpectation.fulfill()
    }
    
    Task {
      var receivedElement = [Int]()
      var iterator = sut.makeAsyncIterator()
      taskHaveIterators.fulfill()
      while let element = try await iterator.next() {
        receivedElement.append(element)
      }
      XCTAssertEqual(receivedElement, [1, 1, 1])
      tasksHaveFinishedExpectation.fulfill()
    }
    
    wait(for: [taskHaveIterators], timeout: 1)
    
    sut.connect()
    
    wait(for: [tasksHaveFinishedExpectation], timeout: 1)
    
    XCTAssertEqual(spyUpstreamSequence.numberOfIterators, 1)
  }
  
  func test_multicast_propagates_error_when_autoconnect() async {
    let expectedError = MockError(code: Int.random(in: 0...100))
    
    let stream = AsyncThrowingPassthroughSubject<Int, Error>()
    
    let sut = AsyncFailSequence<Int>(expectedError)
      .prepend(1)
      .multicast(stream)
      .autoconnect()
    
    var receivedElement = [Int]()
    do {
      for try await element in sut {
        receivedElement.append(element)
      }
      XCTFail("The iteration should fail")
    } catch {
      XCTAssertEqual(receivedElement, [1])
      XCTAssertEqual(error as? MockError, expectedError)
    }
  }

  func test_multicast_cancels_upstream_when_consumer_cancels() async {
    let upstreamStartedExpectation = expectation(description: "Upstream started")
    let upstreamCancelledExpectation = expectation(description: "Upstream cancelled")

    let base = CancellationAwareSequence(
      onStart: { upstreamStartedExpectation.fulfill() },
      onCancel: { upstreamCancelledExpectation.fulfill() }
    )
    let stream = AsyncThrowingPassthroughSubject<Int, Error>()
    let sut = base.multicast(stream).autoconnect()

    let task = Task {
      var iterator = sut.makeAsyncIterator()
      _ = try? await iterator.next()
    }

    await fulfillment(of: [upstreamStartedExpectation], timeout: 1)
    task.cancel()

    await fulfillment(of: [upstreamCancelledExpectation], timeout: 1)
  }
}
