import Dispatch
import AsyncAlgorithms
@testable import AsyncExtensions
import XCTest

final class AsyncSubjectCancellationTests: XCTestCase {
  func test_AsyncPassthroughSubject_does_not_deadlock_during_concurrent_cancellation() async {
    await assertCancellationRaces(
      makeSubject: { AsyncPassthroughSubject<Int>() },
      isSuspended: { subject in
        guard let channel = subject.state.criticalState.channels.values.first else { return false }
        if case .awaiting = channel.state.criticalState { return true }
        return false
      },
      sends: [
        { $0.send(1) },
        { $0.send(.finished) }
      ]
    )
  }

  func test_AsyncCurrentValueSubject_does_not_deadlock_during_concurrent_cancellation() async {
    await assertCancellationRaces(
      makeSubject: { AsyncCurrentValueSubject<Int>(0) },
      isSuspended: { subject in
        guard let channel = subject.state.criticalState.channels.values.first else { return false }
        if case .awaiting = channel.state.criticalState { return true }
        return false
      },
      sends: [
        { $0.send(1) },
        { $0.send(.finished) }
      ]
    )
  }

  func test_AsyncReplaySubject_does_not_deadlock_during_concurrent_cancellation() async {
    await assertCancellationRaces(
      makeSubject: { AsyncReplaySubject<Int>(bufferSize: 1) },
      isSuspended: { subject in
        guard let channel = subject.state.criticalState.channels.values.first else { return false }
        if case .awaiting = channel.state.criticalState { return true }
        return false
      },
      sends: [
        { $0.send(1) },
        { $0.send(.finished) }
      ]
    )
  }

  func test_AsyncThrowingPassthroughSubject_does_not_deadlock_during_concurrent_cancellation() async {
    await assertCancellationRaces(
      makeSubject: { AsyncThrowingPassthroughSubject<Int, Error>() },
      isSuspended: { subject in
        guard let channel = subject.state.criticalState.channels.values.first else { return false }
        if case .awaiting = channel.state.criticalState { return true }
        return false
      },
      sends: [
        { $0.send(1) },
        { $0.send(.finished) },
        { $0.send(.failure(MockError(code: 1))) }
      ]
    )
  }

  func test_AsyncThrowingCurrentValueSubject_does_not_deadlock_during_concurrent_cancellation() async {
    await assertCancellationRaces(
      makeSubject: { AsyncThrowingCurrentValueSubject<Int, Error>(0) },
      isSuspended: { subject in
        guard let channel = subject.state.criticalState.channels.values.first else { return false }
        if case .awaiting = channel.state.criticalState { return true }
        return false
      },
      sends: [
        { $0.send(1) },
        { $0.send(.finished) },
        { $0.send(.failure(MockError(code: 1))) }
      ]
    )
  }

  func test_AsyncThrowingReplaySubject_does_not_deadlock_during_concurrent_cancellation() async {
    await assertCancellationRaces(
      makeSubject: { AsyncThrowingReplaySubject<Int, Error>(bufferSize: 1) },
      isSuspended: { subject in
        guard let channel = subject.state.criticalState.channels.values.first else { return false }
        if case .awaiting = channel.state.criticalState { return true }
        return false
      },
      sends: [
        { $0.send(1) },
        { $0.send(.finished) },
        { $0.send(.failure(MockError(code: 1))) }
      ]
    )
  }

  func test_AsyncPassthroughSubject_cancellation_handler_can_send_during_concurrent_delivery() async {
    await assertCancellationRaces(
      makeSubject: { AsyncPassthroughSubject<Int>() },
      isSuspended: { subject in
        guard let channel = subject.state.criticalState.channels.values.first else { return false }
        if case .awaiting = channel.state.criticalState { return true }
        return false
      },
      onCancel: { $0.send(-1) },
      sends: [
        { $0.send(1) },
        { $0.send(.finished) }
      ]
    )
  }

  func test_AsyncCurrentValueSubject_cancellation_handler_can_send_during_concurrent_delivery() async {
    await assertCancellationRaces(
      makeSubject: { AsyncCurrentValueSubject<Int>(0) },
      isSuspended: { subject in
        guard let channel = subject.state.criticalState.channels.values.first else { return false }
        if case .awaiting = channel.state.criticalState { return true }
        return false
      },
      onCancel: { $0.send(-1) },
      sends: [
        { $0.send(1) },
        { $0.send(.finished) }
      ]
    )
  }

  func test_AsyncReplaySubject_cancellation_handler_can_send_during_concurrent_delivery() async {
    await assertCancellationRaces(
      makeSubject: { AsyncReplaySubject<Int>(bufferSize: 1) },
      isSuspended: { subject in
        guard let channel = subject.state.criticalState.channels.values.first else { return false }
        if case .awaiting = channel.state.criticalState { return true }
        return false
      },
      onCancel: { $0.send(-1) },
      sends: [
        { $0.send(1) },
        { $0.send(.finished) }
      ]
    )
  }

  func test_AsyncThrowingPassthroughSubject_cancellation_handler_can_send_during_concurrent_delivery() async {
    await assertCancellationRaces(
      makeSubject: { AsyncThrowingPassthroughSubject<Int, Error>() },
      isSuspended: { subject in
        guard let channel = subject.state.criticalState.channels.values.first else { return false }
        if case .awaiting = channel.state.criticalState { return true }
        return false
      },
      onCancel: { $0.send(-1) },
      sends: [
        { $0.send(1) },
        { $0.send(.finished) },
        { $0.send(.failure(MockError(code: 1))) }
      ]
    )
  }

  func test_AsyncThrowingCurrentValueSubject_cancellation_handler_can_send_during_concurrent_delivery() async {
    await assertCancellationRaces(
      makeSubject: { AsyncThrowingCurrentValueSubject<Int, Error>(0) },
      isSuspended: { subject in
        guard let channel = subject.state.criticalState.channels.values.first else { return false }
        if case .awaiting = channel.state.criticalState { return true }
        return false
      },
      onCancel: { $0.send(-1) },
      sends: [
        { $0.send(1) },
        { $0.send(.finished) },
        { $0.send(.failure(MockError(code: 1))) }
      ]
    )
  }

  func test_AsyncThrowingReplaySubject_cancellation_handler_can_send_during_concurrent_delivery() async {
    await assertCancellationRaces(
      makeSubject: { AsyncThrowingReplaySubject<Int, Error>(bufferSize: 1) },
      isSuspended: { subject in
        guard let channel = subject.state.criticalState.channels.values.first else { return false }
        if case .awaiting = channel.state.criticalState { return true }
        return false
      },
      onCancel: { $0.send(-1) },
      sends: [
        { $0.send(1) },
        { $0.send(.finished) },
        { $0.send(.failure(MockError(code: 1))) }
      ]
    )
  }

  private func assertCancellationRaces<Subject: AsyncSubject>(
    makeSubject: @escaping @Sendable () -> Subject,
    isSuspended: @escaping @Sendable (Subject) -> Bool,
    onCancel: @escaping @Sendable (Subject) -> Void = { _ in },
    sends: [@Sendable (Subject) -> Void],
    file: StaticString = #filePath,
    line: UInt = #line
  ) async {
    for send in sends {
      let completed = expectation(description: "Sending, cancellation and consumer exit all complete")
      DispatchQueue.global().async {
        for _ in 0..<1_000 {
          let subject = makeSubject()
          // Register before starting the race so passthrough values cannot be lost at setup.
          let iterator = subject.makeAsyncIterator()
          let consumerExited = DispatchSemaphore(value: 0)
          let consumer = Task.detached {
            defer { consumerExited.signal() }
            await withTaskCancellationHandler {
              var iterator = iterator
              do {
                while let _ = try await iterator.next() {}
              } catch {
                // A throwing subject may deliver its failure before cancellation wins.
              }
            } onCancel: {
              onCancel(subject)
            }
          }

          // Wait for an installed continuation, rather than racing an unstarted consumer.
          let deadline = DispatchTime.now() + .seconds(5)
          while !isSuspended(subject) {
            if DispatchTime.now() >= deadline {
              XCTFail("Consumer did not suspend", file: file, line: line)
              consumer.cancel()
              completed.fulfill()
              return
            }
            Thread.sleep(forTimeInterval: 0.0001)
          }

          DispatchQueue.concurrentPerform(iterations: 2) { index in
            if index == 0 {
              consumer.cancel()
            } else {
              send(subject)
            }
          }
          guard consumerExited.wait(timeout: .now() + .seconds(5)) == .success else {
            XCTFail("Consumer did not exit", file: file, line: line)
            completed.fulfill()
            return
          }
        }
        completed.fulfill()
      }
      // A deadlocked concurrentPerform stays on a Dispatch worker, not the test executor.
      await fulfillment(of: [completed], timeout: 30)
    }
  }
}
