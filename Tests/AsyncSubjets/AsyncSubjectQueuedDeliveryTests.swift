import Dispatch
import AsyncAlgorithms
@testable import AsyncExtensions
import XCTest

final class AsyncSubjectQueuedDeliveryTests: XCTestCase {
  func test_passthrough_queues_values_and_termination_while_another_sender_drains() async throws {
    let subject = AsyncPassthroughSubject<Int>()
    try await assertQueuedDelivery(
      subject: subject, initial: [], replayed: [],
      termination: .finished,
      enqueue: { work in subject.state.withCriticalRegion { $0.deliveries.enqueue(work) } },
      drain: { subject.drainDeliveries() }
    )
  }

  func test_current_value_queues_values_and_termination_while_another_sender_drains() async throws {
    let subject = AsyncCurrentValueSubject<Int>(0)
    try await assertQueuedDelivery(
      subject: subject, initial: [0], replayed: [2],
      termination: .finished,
      enqueue: { work in subject.state.withCriticalRegion { $0.deliveries.enqueue(work) } },
      drain: { subject.drainDeliveries() }
    )
  }

  func test_replay_queues_values_and_termination_while_another_sender_drains() async throws {
    let subject = AsyncReplaySubject<Int>(bufferSize: 2)
    try await assertQueuedDelivery(
      subject: subject, initial: [], replayed: [1, 2],
      termination: .finished,
      enqueue: { work in subject.state.withCriticalRegion { $0.deliveries.enqueue(work) } },
      drain: { subject.drainDeliveries() }
    )
  }

  func test_throwing_passthrough_queues_values_and_termination_while_another_sender_drains() async throws {
    for termination: Termination<Error> in [.finished, .failure(MockError(code: 61))] {
      let subject = AsyncThrowingPassthroughSubject<Int, Error>()
      try await assertQueuedDelivery(
        subject: subject, initial: [], replayed: [],
        termination: termination,
        enqueue: { work in subject.state.withCriticalRegion { $0.deliveries.enqueue(work) } },
        drain: { subject.drainDeliveries() }
      )
    }
  }

  func test_throwing_current_value_queues_values_and_termination_while_another_sender_drains() async throws {
    for termination: Termination<Error> in [.finished, .failure(MockError(code: 61))] {
      let subject = AsyncThrowingCurrentValueSubject<Int, Error>(0)
      try await assertQueuedDelivery(
        subject: subject, initial: [0], replayed: [2],
        termination: termination,
        enqueue: { work in subject.state.withCriticalRegion { $0.deliveries.enqueue(work) } },
        drain: { subject.drainDeliveries() }
      )
    }
  }

  func test_throwing_replay_queues_values_and_termination_while_another_sender_drains() async throws {
    for termination: Termination<Error> in [.finished, .failure(MockError(code: 61))] {
      let subject = AsyncThrowingReplaySubject<Int, Error>(bufferSize: 2)
      try await assertQueuedDelivery(
        subject: subject, initial: [], replayed: [1, 2],
        termination: termination,
        enqueue: { work in subject.state.withCriticalRegion { $0.deliveries.enqueue(work) } },
        drain: { subject.drainDeliveries() }
      )
    }
  }

  private func assertQueuedDelivery<Subject: AsyncSubject>(
    subject: Subject,
    initial: [Int],
    replayed: [Int],
    termination: Termination<Subject.Failure>,
    enqueue: (@escaping @Sendable () -> Void) -> Bool,
    drain: @escaping @Sendable () -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
  ) async throws where Subject.Element == Int {
    var first = subject.makeAsyncIterator()
    var second = subject.makeAsyncIterator()
    for value in initial {
      let a = try await first.next()
      let b = try await second.next()
      XCTAssertEqual(a, value, file: file, line: line)
      XCTAssertEqual(b, value, file: file, line: line)
    }

    let entered = expectation(description: "Drainer paused outside the state lock")
    let finished = expectation(description: "Drainer emptied the queue")
    let release = DispatchSemaphore(value: 0)
    XCTAssertTrue(enqueue {
      entered.fulfill()
      if release.wait(timeout: .now() + .seconds(5)) != .success {
        XCTFail("Drainer was not released", file: file, line: line)
      }
    }, file: file, line: line)
    defer { release.signal() }
    DispatchQueue.global().async {
      drain()
      finished.fulfill()
    }
    await fulfillment(of: [entered], timeout: 5)

    // These sends must return while the active drainer is still paused.
    subject.send(1)
    subject.send(2)
    let late = subject.makeAsyncIterator()
    subject.send(termination)
    let afterTermination = subject.makeAsyncIterator()
    XCTAssertFalse(first.hasBufferedElements, file: file, line: line)
    XCTAssertFalse(second.hasBufferedElements, file: file, line: line)
    // A new consumer observes terminal state even while existing delivery is pending.
    await assertReceived(afterTermination, values: [], termination: termination, file: file, line: line)

    release.signal()
    await fulfillment(of: [finished], timeout: 5)
    await assertReceived(first, values: [1, 2], termination: termination, file: file, line: line)
    await assertReceived(second, values: [1, 2], termination: termination, file: file, line: line)
    await assertReceived(late, values: replayed, termination: termination, file: file, line: line)

    // Exercise the empty-to-active transition again after drainer ownership is released.
    let restarted = expectation(description: "A new drainer can start")
    XCTAssertTrue(enqueue { restarted.fulfill() }, file: file, line: line)
    drain()
    await fulfillment(of: [restarted], timeout: 5)
  }

  private func assertReceived<Iterator: AsyncIteratorProtocol, Failure: Error>(
    _ iterator: Iterator,
    values: [Int],
    termination: Termination<Failure>,
    file: StaticString,
    line: UInt
  ) async where Iterator.Element == Int {
    var iterator = iterator
    var received: [Int] = []
    var receivedError: Error?
    do {
      while let value = try await iterator.next() { received.append(value) }
    } catch {
      receivedError = error
    }
    XCTAssertEqual(received, values, file: file, line: line)
    switch termination {
      case .finished:
        XCTAssertNil(receivedError, file: file, line: line)
      case .failure(let expected):
        XCTAssertEqual(receivedError as? MockError, expected as? MockError, file: file, line: line)
    }
  }
}
