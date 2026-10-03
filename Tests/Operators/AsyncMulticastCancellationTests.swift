@testable import AsyncExtensions
import XCTest

private actor SharedConnection {
  let continuation: AsyncThrowingStream<Int, Error>.Continuation
  let shared: AsyncShareSequence<AsyncThrowingStream<Int, Error>>

  init() {
    let (continuation, stream) = AsyncThrowingStream<Int, Error>.pipe()
    self.continuation = continuation
    self.shared = stream.share()
  }

  func events() -> AsyncShareSequence<AsyncThrowingStream<Int, Error>> { shared }
  func send(_ value: Int) { continuation.yield(value) }
  func finish() { continuation.finish() }
}

final class AsyncMulticastCancellationTests: XCTestCase {
  func test_connection_returns_one_shared_sequence_for_concurrent_consumers() async throws {
    let connection = SharedConnection()
    let firstSequence = await connection.events()
    let secondSequence = await connection.events()
    XCTAssertTrue(firstSequence === secondSequence)
    var firstIterator = firstSequence.makeAsyncIterator()
    var secondIterator = secondSequence.makeAsyncIterator()
    let first = Task {
      var values = [Int]()
      while let value = try await firstIterator.next() { values.append(value) }
      return values
    }
    let second = Task {
      var values = [Int]()
      while let value = try await secondIterator.next() { values.append(value) }
      return values
    }
    await connection.send(42)
    await connection.finish()
    let firstValues = try await first.value
    let secondValues = try await second.value
    XCTAssertEqual(firstValues, [42])
    XCTAssertEqual(secondValues, [42])
  }

  func test_cancelling_subscriber_waiting_for_upstream_finishes_without_cancelling_shared_stream() async throws {
    let (continuation, upstream) = AsyncThrowingStream<Int, Error>.pipe()
    let shared = upstream.multicast(AsyncThrowingPassthroughSubject<Int, Error>()).autoconnect()
    var firstIterator = shared.makeAsyncIterator()
    var secondIterator = shared.makeAsyncIterator()
    let firstFinished = expectation(description: "Cancelled subscriber finishes before upstream emits")
    let first = Task {
      let value = try await firstIterator.next()
      firstFinished.fulfill()
      return value
    }
    let deadline = DispatchTime.now().uptimeNanoseconds + 2_000_000_000
    while shared.state.withCriticalRegion({ state in
      if case .busy = state { return false }
      return true
    }) {
      guard DispatchTime.now().uptimeNanoseconds < deadline else {
        continuation.finish()
        return XCTFail("Upstream iteration did not start")
      }
      await Task.yield()
    }
    let second = Task { try await secondIterator.next() }
    first.cancel()
    await fulfillment(of: [firstFinished], timeout: 2)

    // Also releases the original implementation after its timeout failure.
    continuation.yield(42)
    continuation.finish()
    let firstValue = try await first.value
    let secondValue = try await second.value
    XCTAssertNil(firstValue)
    XCTAssertEqual(secondValue, 42)
  }
}
