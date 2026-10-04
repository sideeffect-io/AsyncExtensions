//
//  AsyncMulticastSequenceTests.swift
//
//
//  Created by Thibault Wittemberg on 21/02/2022.
//

@testable import AsyncExtensions
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

/// An upstream the test feeds by hand; `demanded` fires each time a consumer enters `next()`.
private struct GatedUpstream: AsyncSequence, Sendable {
  typealias Element = Int

  let stream: AsyncThrowingStream<Int, Error>
  let demanded: @Sendable () -> Void

  func makeAsyncIterator() -> Iterator {
    Iterator(base: self.stream.makeAsyncIterator(), demanded: self.demanded)
  }

  struct Iterator: AsyncIteratorProtocol, @unchecked Sendable {
    var base: AsyncThrowingStream<Int, Error>.Iterator
    let demanded: @Sendable () -> Void

    mutating func next() async throws -> Int? {
      self.demanded()
      return try await self.base.next()
    }
  }
}

private enum SubscriberExit {
  case cancelTask
  case releaseIterator
}

final class AsyncMulticastSequenceTests: XCTestCase {
  func test_cancelling_one_subscriber_task_keeps_upstream_for_the_other_when_connected() async {
    await self.assertSurvivingSubscriberCompletes(autoconnect: false, exit: .cancelTask)
  }

  func test_cancelling_one_subscriber_task_keeps_upstream_for_the_other_when_autoconnected() async {
    await self.assertSurvivingSubscriberCompletes(autoconnect: true, exit: .cancelTask)
  }

  func test_releasing_one_subscriber_iterator_keeps_upstream_for_the_other_when_connected() async {
    await self.assertSurvivingSubscriberCompletes(autoconnect: false, exit: .releaseIterator)
  }

  func test_releasing_one_subscriber_iterator_keeps_upstream_for_the_other_when_autoconnected() async {
    await self.assertSurvivingSubscriberCompletes(autoconnect: true, exit: .releaseIterator)
  }

  /// Subscriber A is the one pulling on the shared upstream when it leaves; subscriber B, already
  /// registered and waiting on the subject, must still receive every element and finish normally.
  private func assertSurvivingSubscriberCompletes(autoconnect: Bool, exit: SubscriberExit) async {
    let (stream, continuation) = AsyncThrowingStream<Int, Error>.makeStream()
    let demanded = expectation(description: "A consumer is awaiting the upstream")
    demanded.assertForOverFulfill = false
    let upstream = GatedUpstream(stream: stream) { demanded.fulfill() }

    let subject = AsyncThrowingPassthroughSubject<Int, Error>()
    let multicasted = upstream.multicast(subject)
    let sut = autoconnect ? multicasted.autoconnect() : multicasted
    let subscriberCount = { subject.state.withCriticalRegion { $0.channels.count } }

    // B registers with the subject before any element flows.
    let iteratorB = sut.makeAsyncIterator()

    let aHasLeft = expectation(description: "Subscriber A has left")
    let bHasFinished = expectation(description: "Subscriber B has finished")

    // A's iterator exists only inside this task, so no copy of it outlives A.
    let taskA = Task { () throws -> [Int] in
      defer { aHasLeft.fulfill() }
      var iterator = sut.makeAsyncIterator()
      var received = [Int]()
      switch exit {
        case .cancelTask:
          while let element = try await iterator.next() {
            received.append(element)
          }
        case .releaseIterator:
          if let element = try await iterator.next() {
            received.append(element)
          }
      }
      return received
    }

    if !autoconnect {
      sut.connect()
    }

    // A is now inside the upstream's next(); only then does B ask for elements, so A is the puller.
    await fulfillment(of: [demanded], timeout: 1)
    XCTAssertEqual(subscriberCount(), 2)

    let taskB = Task { () throws -> [Int] in
      defer { bHasFinished.fulfill() }
      var iterator = iteratorB
      var received = [Int]()
      while let element = try await iterator.next() {
        received.append(element)
      }
      return received
    }

    let expectedForA: [Int]
    switch exit {
      case .cancelTask:
        // A must finish while upstream is silent; any element sent now could wake it.
        taskA.cancel()
        expectedForA = []
      case .releaseIterator:
        continuation.yield(1)
        expectedForA = [1]
    }
    await fulfillment(of: [aHasLeft], timeout: 1)
    XCTAssertEqual(subscriberCount(), 1, "Subscriber A is still registered with the subject")

    if exit == .cancelTask {
      continuation.yield(1)
    }
    continuation.yield(2)
    continuation.yield(3)
    continuation.finish()

    await fulfillment(of: [bHasFinished], timeout: 1)
    taskB.cancel()
    // A's result was settled when it left, before any of these elements were sent.
    do {
      let received = try await taskA.value
      XCTAssertEqual(received, expectedForA)
    } catch {
      XCTFail("Subscriber A should leave without an error, got \(error)")
    }
    do {
      let received = try await taskB.value
      XCTAssertEqual(received, [1, 2, 3])
    } catch {
      XCTFail("Subscriber B should finish normally, got \(error)")
    }
  }

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
