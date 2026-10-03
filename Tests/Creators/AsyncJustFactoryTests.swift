@testable import AsyncExtensions
import XCTest

struct JustFactoryGate: Sendable {
  struct State: Sendable {
    var continuation: UnsafeContinuation<Void, Never>?
    var opened = false
  }
  let state = ManagedCriticalState(State())
  let suspended: XCTestExpectation

  func wait() async {
    await withUnsafeContinuation { continuation in
      let opened = state.withCriticalRegion { state -> Bool in
        guard !state.opened else { return true }
        state.continuation = continuation
        return false
      }
      if opened { continuation.resume() }
      suspended.fulfill()
    }
  }

  func open() {
    let continuation = state.withCriticalRegion { state -> UnsafeContinuation<Void, Never>? in
      state.opened = true
      defer { state.continuation = nil }
      return state.continuation
    }
    continuation?.resume()
  }
}

final class AsyncJustFactoryTests: XCTestCase {
  func test_factory_is_lazy_and_runs_once_per_independent_iterator() async {
    let calls = ManagedCriticalState(0)
    let sequence = AsyncJustSequence<Int> {
      calls.withCriticalRegion { $0 += 1 }
      return 42
    }
    XCTAssertEqual(calls.criticalState, 0)
    var first = sequence.makeAsyncIterator()
    var independent = sequence.makeAsyncIterator()
    let firstValue = await first.next()
    let pastEnd = await first.next()
    let independentValue = await independent.next()
    XCTAssertEqual(firstValue, 42)
    XCTAssertNil(pastEnd)
    XCTAssertEqual(independentValue, 42)
    XCTAssertEqual(calls.criticalState, 2)
  }

  func test_nil_factory_result_finishes_without_emitting() async {
    var iterator = AsyncJustSequence<Int> { nil }.makeAsyncIterator()
    let value = await iterator.next()
    XCTAssertNil(value)
  }

  func test_already_cancelled_iterator_does_not_invoke_factory() async {
    let gate = JustFactoryGate(suspended: expectation(description: "Paused before iteration"))
    let calls = ManagedCriticalState(0)
    let task = Task {
      await gate.wait()
      var iterator = AsyncJustSequence<Int> {
        calls.withCriticalRegion { $0 += 1 }
        return 42
      }.makeAsyncIterator()
      return await iterator.next()
    }
    await fulfillment(of: [gate.suspended], timeout: 2)
    task.cancel()
    gate.open()
    let value = await task.value
    XCTAssertNil(value)
    XCTAssertEqual(calls.criticalState, 0)
  }

  func test_cancellation_discards_late_noncooperative_factory_value() async {
    let gate = JustFactoryGate(suspended: expectation(description: "Factory suspended"))
    let task = Task {
      var iterator = AsyncJustSequence<Int> {
        await gate.wait()
        return 42
      }.makeAsyncIterator()
      return await iterator.next()
    }
    await fulfillment(of: [gate.suspended], timeout: 2)
    task.cancel()
    gate.open()
    let value = await task.value
    XCTAssertNil(value)
  }
}
