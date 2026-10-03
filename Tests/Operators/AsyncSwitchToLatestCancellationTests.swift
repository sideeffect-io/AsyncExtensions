@testable import AsyncExtensions
import XCTest

// The gate deliberately ignores cancellation, but can always be released by test cleanup.
private struct SwitchCancellationGate: Sendable {
  struct State {
    var continuation: UnsafeContinuation<Void, Never>?
    var isReleased = false
  }

  let state = ManagedCriticalState(State())
  let suspended: XCTestExpectation

  func wait() async {
    await withUnsafeContinuation { continuation in
      let resume = state.withCriticalRegion { state -> Bool in
        guard !state.isReleased else { return true }
        state.continuation = continuation
        return false
      }
      if resume { continuation.resume() }
      suspended.fulfill()
    }
  }

  func release() {
    let continuation = state.withCriticalRegion { state -> UnsafeContinuation<Void, Never>? in
      state.isReleased = true
      defer { state.continuation = nil }
      return state.continuation
    }
    continuation?.resume()
  }
}

private struct GatedSwitchSequence<Element: Sendable>: AsyncSequence, Sendable {
  let gate: SwitchCancellationGate
  let result: Result<Element?, Error>

  func makeAsyncIterator() -> Iterator { Iterator(gate: gate, result: result) }

  struct Iterator: AsyncIteratorProtocol, Sendable {
    let gate: SwitchCancellationGate
    let result: Result<Element?, Error>
    var hasReturned = false

    mutating func next() async throws -> Element? {
      guard !hasReturned else { return nil }
      hasReturned = true
      await gate.wait()
      return try result.get()
    }
  }
}

private struct ObservedSwitchChild: AsyncSequence, Sendable {
  let channel: AsyncBufferedChannel<Int>
  let suspended: XCTestExpectation

  func makeAsyncIterator() -> Iterator { Iterator(channel: channel, suspended: suspended) }

  struct Iterator: AsyncIteratorProtocol, Sendable {
    let channel: AsyncBufferedChannel<Int>
    let suspended: XCTestExpectation
    let didSuspend = ManagedCriticalState(false)

    func next() async -> Int? {
      await channel.next(onSuspend: {
        let firstSuspension = didSuspend.withCriticalRegion { didSuspend -> Bool in
          defer { didSuspend = true }
          return !didSuspend
        }
        if firstSuspension { suspended.fulfill() }
      })
    }
  }
}

final class AsyncSwitchToLatestCancellationTests: XCTestCase {
  func test_cancellation_while_latest_child_is_suspended_finishes_collection() async {
    let (continuation, outer) = AsyncStream<ObservedSwitchChild>.pipe()
    let received = (1...3).map { expectation(description: "Received \($0)") }
    let suspended = (1...3).map { expectation(description: "Child \($0) suspended") }
    let channels = (1...3).map { _ in AsyncBufferedChannel<Int>() }
    let finished = expectation(description: "Collection finished")
    let task = Task {
      var values = [Int]()
      for await value in outer.switchToLatest() {
        values.append(value)
        if (1...3).contains(value) { received[value - 1].fulfill() }
      }
      XCTAssertEqual(values, [1, 2, 3])
      finished.fulfill()
    }

    for index in channels.indices {
      channels[index].send(index + 1)
      continuation.yield(ObservedSwitchChild(channel: channels[index], suspended: suspended[index]))
      await fulfillment(of: [received[index], suspended[index]], timeout: 2)
    }
    task.cancel()
    await fulfillment(of: [finished], timeout: 2)

    // Cleanup also lets the unfixed implementation finish after its timeout failure.
    channels.forEach { $0.finish() }
    continuation.finish()
    await task.value
  }

  func test_cancellation_while_waiting_for_non_cooperative_outer_ignores_late_child() async {
    await assertCancellationWhileWaitingForOuter(result: .success(AsyncBufferedChannel<Int>()))
  }

  func test_cancellation_while_waiting_for_non_cooperative_outer_ignores_late_error() async {
    await assertCancellationWhileWaitingForOuter(result: .failure(MockError(code: 53)))
  }

  private func assertCancellationWhileWaitingForOuter(result: Result<AsyncBufferedChannel<Int>?, Error>) async {
    let gate = SwitchCancellationGate(suspended: expectation(description: "Outer suspended"))
    var iterator = GatedSwitchSequence(gate: gate, result: result).switchToLatest().makeAsyncIterator()
    let state = iterator.state
    let finished = expectation(description: "Consumer finished before outer released")
    let task = Task {
      do {
        let value = try await iterator.next()
        XCTAssertNil(value)
        finished.fulfill()
        // Reuse from an uncancelled task must not resurrect the cancelled iterator.
        return iterator
      } catch {
        XCTFail("Cancelled iteration delivered a late error: \(error)")
        finished.fulfill()
        return iterator
      }
    }

    await fulfillment(of: [gate.suspended], timeout: 2)
    await waitUntil {
      state.withCriticalRegion {
        if case .waitingForChildIterator = $0.base { return true }
        return false
      }
    }
    task.cancel()
    await fulfillment(of: [finished], timeout: 2)
    gate.release()
    if case .success(let channel) = result { channel?.finish() }
    var cancelledIterator = await task.value
    // Await the producer so the assertion also covers its late success/failure transition.
    await cancelledIterator.baseTask?.value
    do {
      let value = try await cancelledIterator.next()
      XCTAssertNil(value)
    } catch {
      XCTFail("Late outer result resurrected cancelled iteration: \(error)")
    }
  }

  func test_finite_outer_allows_latest_child_to_drain() async {
    let channel = AsyncBufferedChannel<Int>()
    let suspended = expectation(description: "Latest child suspended after outer finished")
    let child = ObservedSwitchChild(channel: channel, suspended: suspended)
    var iterator = [child].async.switchToLatest().makeAsyncIterator()
    let state = iterator.state
    let task = Task { () -> [Int] in
      var values = [Int]()
      while let value = await iterator.next() { values.append(value) }
      return values
    }
    await fulfillment(of: [suspended], timeout: 2)
    await waitUntil { state.withCriticalRegion { $0.base.isFinished } }
    channel.send(10)
    channel.send(20)
    channel.finish()
    let values = await task.value
    XCTAssertEqual(values, [10, 20])
  }

  func test_cancellation_discards_late_inner_value() async {
    await assertCancellationDiscardsInnerResult(.success(53))
  }

  func test_cancellation_discards_late_inner_error() async {
    await assertCancellationDiscardsInnerResult(.failure(MockError(code: 53)))
  }

  private func assertCancellationDiscardsInnerResult(_ result: Result<Int?, Error>) async {
    let gate = SwitchCancellationGate(suspended: expectation(description: "Inner suspended"))
    let child = GatedSwitchSequence(gate: gate, result: result)
    var iterator = [child].async.switchToLatest().makeAsyncIterator()
    let task = Task {
      do {
        let value = try await iterator.next()
        XCTAssertNil(value)
      } catch {
        XCTFail("Cancelled iteration delivered a late inner error: \(error)")
      }
      return iterator
    }
    await fulfillment(of: [gate.suspended], timeout: 2)
    task.cancel()
    // A non-cooperative inner task must return before its task.value await can complete.
    gate.release()
    iterator = await task.value
    XCTAssertTrue(iterator.state.criticalState.base.isCancelled)
    XCTAssertNil(iterator.state.criticalState.childTask)
    await iterator.baseTask?.value
  }

  func test_cancellation_racing_outer_delivery_finishes_without_resurrecting_iteration() async {
    for _ in 0..<100 {
      let gate = SwitchCancellationGate(suspended: expectation(description: "Outer suspended"))
      let child = AsyncBufferedChannel<Int>()
      child.send(53)
      child.finish()
      var iterator = GatedSwitchSequence(gate: gate, result: .success(child)).switchToLatest().makeAsyncIterator()
      let finished = expectation(description: "Racing consumer finished")
      let task = Task {
        do {
          while let value = try await iterator.next() { XCTAssertEqual(value, 53) }
        } catch {
          XCTFail("Unexpected failure: \(error)")
        }
        finished.fulfill()
        return iterator
      }
      await fulfillment(of: [gate.suspended], timeout: 2)
      race({ task.cancel() }, { gate.release() })
      await fulfillment(of: [finished], timeout: 2)
      iterator = await task.value
      await iterator.baseTask?.value
      do {
        let value = try await iterator.next()
        XCTAssertNil(value)
      } catch {
        XCTFail("Finished iterator delivered a late error: \(error)")
      }
    }
  }

  func test_already_cancelled_task_does_not_start_outer_iteration() async {
    let (continuation, outer) = AsyncStream<AsyncBufferedChannel<Int>>.pipe()
    let gate = SwitchCancellationGate(suspended: expectation(description: "Consumer paused before next"))
    let task = Task {
      await gate.wait()
      var iterator = outer.switchToLatest().makeAsyncIterator()
      let value = await iterator.next()
      XCTAssertNil(value)
      XCTAssertNil(iterator.baseTask)
      return iterator
    }
    await fulfillment(of: [gate.suspended], timeout: 2)
    task.cancel()
    gate.release()
    var iterator = await task.value
    let child = AsyncBufferedChannel<Int>()
    child.send(53)
    child.finish()
    continuation.yield(child)
    continuation.finish()
    let value = await iterator.next()
    XCTAssertNil(value)
    XCTAssertNil(iterator.baseTask)
    XCTAssertNil(iterator.state.criticalState.childTask)
  }

  func test_cancellation_between_next_calls_cancels_existing_outer_task() async {
    let (continuation, outer) = AsyncStream<AsyncBufferedChannel<Int>>.pipe()
    let channel = AsyncBufferedChannel<Int>()
    channel.send(1)
    continuation.yield(channel)
    var iterator = outer.switchToLatest().makeAsyncIterator()
    let first = await iterator.next()
    XCTAssertEqual(first, 1)

    let terminated = expectation(description: "Outer cancelled")
    continuation.onTermination = { _ in terminated.fulfill() }
    let gate = SwitchCancellationGate(suspended: expectation(description: "Consumer between next calls"))
    let task = Task {
      await gate.wait()
      let value = await iterator.next()
      XCTAssertNil(value)
      return iterator
    }
    await fulfillment(of: [gate.suspended], timeout: 2)
    task.cancel()
    gate.release()
    iterator = await task.value
    await fulfillment(of: [terminated], timeout: 2)
    channel.finish()
    continuation.finish()
    let value = await iterator.next()
    XCTAssertNil(value)
    XCTAssertNil(iterator.state.criticalState.childTask)
  }

  // Observe the actual state rather than assume a fixed number of scheduler yields is enough.
  private func waitUntil(_ condition: () -> Bool) async {
    let deadline = DispatchTime.now().uptimeNanoseconds + 2_000_000_000
    while !condition() {
      guard DispatchTime.now().uptimeNanoseconds < deadline else {
        return XCTFail("Iterator did not reach the expected state")
      }
      await Task.yield()
    }
  }
}
