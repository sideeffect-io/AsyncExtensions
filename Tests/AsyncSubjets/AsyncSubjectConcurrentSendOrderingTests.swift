import Dispatch
@testable import AsyncExtensions
import Foundation
import XCTest

final class AsyncSubjectConcurrentSendOrderingTests: XCTestCase {
  private let rounds = 200
  private let sendsPerProducer = 100

  func test_AsyncPassthroughSubject_subscribers_receive_concurrent_sends_in_the_same_order() async {
    var roundsWithDifferentOrder = 0
    for _ in 0..<rounds {
      let subject = AsyncPassthroughSubject<Int>()
      let received = await collect(subscribers: 2, from: subject) {
        sendConcurrently(producers: 2, sendsPerProducer: sendsPerProducer) { subject.send($0) }
        subject.send(.finished)
      }
      if received[0] != received[1] { roundsWithDifferentOrder += 1 }
    }
    XCTAssertEqual(roundsWithDifferentOrder, 0)
  }

  func test_AsyncCurrentValueSubject_subscriber_ends_on_the_subject_value_after_concurrent_sends() async {
    var roundsWithStaleSubscriber = 0
    for _ in 0..<rounds {
      let subject = AsyncCurrentValueSubject<Int>(-1)
      var value = 0
      let received = await collect(subscribers: 1, from: subject) {
        sendConcurrently(producers: 2, sendsPerProducer: sendsPerProducer) { subject.send($0) }
        value = subject.value
        subject.send(.finished)
      }
      if received[0].last != value { roundsWithStaleSubscriber += 1 }
    }
    XCTAssertEqual(roundsWithStaleSubscriber, 0)
  }

  func test_AsyncReplaySubject_subscriber_ends_on_the_replayed_value_after_concurrent_sends() async {
    var roundsWithStaleSubscriber = 0
    for _ in 0..<rounds {
      let subject = AsyncReplaySubject<Int>(bufferSize: 1)
      var replayedValue: Int?
      let received = await collect(subscribers: 1, from: subject) {
        sendConcurrently(producers: 2, sendsPerProducer: sendsPerProducer) { subject.send($0) }
        replayedValue = subject.state.criticalState.buffer.last
        subject.send(.finished)
      }
      if received[0].last != replayedValue { roundsWithStaleSubscriber += 1 }
    }
    XCTAssertEqual(roundsWithStaleSubscriber, 0)
  }

  func test_AsyncThrowingPassthroughSubject_subscribers_receive_concurrent_sends_in_the_same_order() async {
    var roundsWithDifferentOrder = 0
    for _ in 0..<rounds {
      let subject = AsyncThrowingPassthroughSubject<Int, Error>()
      let received = await collect(subscribers: 2, from: subject) {
        sendConcurrently(producers: 2, sendsPerProducer: sendsPerProducer) { subject.send($0) }
        subject.send(.finished)
      }
      if received[0] != received[1] { roundsWithDifferentOrder += 1 }
    }
    XCTAssertEqual(roundsWithDifferentOrder, 0)
  }

  func test_AsyncThrowingCurrentValueSubject_subscriber_ends_on_the_subject_value_after_concurrent_sends() async {
    var roundsWithStaleSubscriber = 0
    for _ in 0..<rounds {
      let subject = AsyncThrowingCurrentValueSubject<Int, Error>(-1)
      var value = 0
      let received = await collect(subscribers: 1, from: subject) {
        sendConcurrently(producers: 2, sendsPerProducer: sendsPerProducer) { subject.send($0) }
        value = subject.value
        subject.send(.finished)
      }
      if received[0].last != value { roundsWithStaleSubscriber += 1 }
    }
    XCTAssertEqual(roundsWithStaleSubscriber, 0)
  }

  func test_AsyncThrowingReplaySubject_subscribers_receive_concurrent_sends_in_the_same_order() async {
    var roundsWithDifferentOrder = 0
    for _ in 0..<rounds {
      let subject = AsyncThrowingReplaySubject<Int, Error>(bufferSize: UInt(sendsPerProducer * 2))
      let received = await collect(subscribers: 2, from: subject) {
        sendConcurrently(producers: 2, sendsPerProducer: sendsPerProducer) { subject.send($0) }
        subject.send(.finished)
      }
      if received[0] != received[1] { roundsWithDifferentOrder += 1 }
    }
    XCTAssertEqual(roundsWithDifferentOrder, 0)
  }

  func test_cancellation_handler_can_send_to_its_subject_during_a_concurrent_send() async {
    for _ in 0..<1_000 {
      let subject = AsyncPassthroughSubject<Int>()
      let iterator = subject.makeAsyncIterator()
      let exited = DispatchSemaphore(value: 0)
      let consumer = Task.detached {
        defer { exited.signal() }
        await withTaskCancellationHandler {
          var iterator = iterator
          while let _ = await iterator.next() {}
        } onCancel: {
          subject.send(-1)
        }
      }

      let suspensionDeadline = DispatchTime.now() + .seconds(1)
      while !isSuspended(subject) && DispatchTime.now() < suspensionDeadline {
        try? await Task.sleep(nanoseconds: 100_000)
      }
      guard isSuspended(subject) else {
        XCTFail("consumer did not suspend in next()")
        consumer.cancel()
        return
      }

      DispatchQueue.concurrentPerform(iterations: 2) { index in
        if index == 0 {
          consumer.cancel()
        } else {
          subject.send(1)
        }
      }

      let exitWaiter = Task.detached {
        waitForSignal(exited, timeout: .seconds(1))
      }
      guard await exitWaiter.value else {
        XCTFail("consumer did not exit after cancellation")
        consumer.cancel()
        return
      }
    }
  }

  private func collect<Subject: AsyncSubject>(
    subscribers: Int,
    from subject: Subject,
    produce: () -> Void
  ) async -> [[Subject.Element]] where Subject.Element: Sendable {
    let iterators = (0..<subscribers).map { _ in subject.makeAsyncIterator() }
    let consumers = iterators.map { iterator in
      Task.detached { () -> [Subject.Element] in
        var iterator = iterator
        var values: [Subject.Element] = []
        while let value = try? await iterator.next() {
          values.append(value)
        }
        return values
      }
    }
    produce()
    var received: [[Subject.Element]] = []
    for consumer in consumers {
      received.append(await consumer.value)
    }
    return received
  }
}

private func isSuspended(_ subject: AsyncPassthroughSubject<Int>) -> Bool {
  guard let channel = subject.state.criticalState.channels.values.first else { return false }
  if case .awaiting = channel.state.criticalState { return true }
  return false
}

private func waitForSignal(_ semaphore: DispatchSemaphore, timeout: DispatchTimeInterval) -> Bool {
  semaphore.wait(timeout: .now() + timeout) == .success
}

private func sendConcurrently(producers: Int, sendsPerProducer: Int, send: (Int) -> Void) {
  DispatchQueue.concurrentPerform(iterations: producers) { producer in
    for index in 0..<sendsPerProducer {
      send(producer * 1_000_000 + index)
    }
  }
}
