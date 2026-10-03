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

final class AsyncMulticastSequenceTests: XCTestCase {
  func test_concurrent_consumers_receive_all_elements_in_order_before_finish() async {
    await assertConcurrentDelivery()
  }

  func test_concurrent_consumers_receive_all_elements_in_order_before_failure() async {
    await assertConcurrentDelivery(failure: MockError(code: 1701))
  }

  private func assertConcurrentDelivery(failure: MockError? = nil) async {
    let elements = Array(0..<100)

    for _ in 0..<20 {
      let upstream = AsyncThrowingStream<Int, Error> { continuation in
        elements.forEach { continuation.yield($0) }
        continuation.finish(throwing: failure)
      }
      let sut = upstream.multicast(AsyncThrowingPassthroughSubject<Int, Error>())
      // Register every subscriber before allowing any of them to advance upstream.
      let iterators = (0..<8).map { _ in sut.makeAsyncIterator() }
      let finished = expectation(description: "All concurrent subscribers finish")
      finished.expectedFulfillmentCount = iterators.count
      sut.connect()

      let consumers = iterators.map { iterator in
        Task {
          defer { finished.fulfill() }
          var iterator = iterator
          var received = [Int]()
          do {
            while let element = try await iterator.next() {
              received.append(element)
            }
            XCTAssertNil(failure)
          } catch {
            XCTAssertNotNil(failure)
            XCTAssertEqual(error as? MockError, failure)
          }
          XCTAssertEqual(received, elements)
        }
      }

      await fulfillment(of: [finished], timeout: 5)
      consumers.forEach { $0.cancel() }
    }
  }

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

}
