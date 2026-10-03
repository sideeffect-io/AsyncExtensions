import Dispatch
@testable import AsyncExtensions
import XCTest

final class AsyncSubjectConcurrentSendOrderingTests: XCTestCase {
  func test_passthrough_consumers_receive_concurrent_sends_in_the_same_order() async throws {
    try await assertOrdering(makeSubject: { AsyncPassthroughSubject<Int>() })
  }

  func test_throwing_passthrough_consumers_receive_concurrent_sends_in_the_same_order() async throws {
    try await assertOrdering(makeSubject: { AsyncThrowingPassthroughSubject<Int, Error>() })
  }

  func test_current_value_matches_consumers_after_concurrent_sends() async throws {
    try await assertOrdering(
      makeSubject: { AsyncCurrentValueSubject<Int>(-1) },
      initial: [-1], replayCount: 1, currentValue: { $0.value }
    )
  }

  func test_throwing_current_value_matches_consumers_after_concurrent_sends() async throws {
    try await assertOrdering(
      makeSubject: { AsyncThrowingCurrentValueSubject<Int, Error>(-1) },
      initial: [-1], replayCount: 1, currentValue: { $0.value }
    )
  }

  func test_replay_matches_consumers_after_concurrent_sends() async throws {
    try await assertOrdering(makeSubject: { AsyncReplaySubject<Int>(bufferSize: 4) }, replayCount: 4)
  }

  func test_throwing_replay_matches_consumers_after_concurrent_sends() async throws {
    try await assertOrdering(makeSubject: { AsyncThrowingReplaySubject<Int, Error>(bufferSize: 4) }, replayCount: 4)
  }

  private func assertOrdering<Subject: AsyncSubject>(
    makeSubject: () -> Subject,
    initial: [Int] = [],
    replayCount: Int = 0,
    currentValue: ((Subject) -> Int)? = nil,
    file: StaticString = #filePath,
    line: UInt = #line
  ) async throws where Subject.Element == Int {
    for _ in 0..<200 {
      let subject = makeSubject()
      // Registration is synchronous; consumers need not run before production begins.
      let first = subject.makeAsyncIterator()
      let second = subject.makeAsyncIterator()
      DispatchQueue.concurrentPerform(iterations: 2) { producer in
        for index in 0..<100 {
          subject.send(producer * 1_000 + index)
        }
      }

      var late = subject.makeAsyncIterator()
      var replayed: [Int] = []
      for _ in 0..<replayCount {
        if let value = try await late.next() { replayed.append(value) }
      }
      let storedValue = currentValue?(subject)
      subject.send(.finished)
      let receivedFirst = try await collect(first)
      let receivedSecond = try await collect(second)

      guard receivedFirst == receivedSecond else {
        return XCTFail("Consumers received concurrent sends in different orders", file: file, line: line)
      }
      XCTAssertEqual(Array(receivedFirst.prefix(initial.count)), initial, file: file, line: line)
      let sent = Array(receivedFirst.dropFirst(initial.count))
      XCTAssertEqual(sent.count, 200, file: file, line: line)
      for producer in 0..<2 {
        XCTAssertEqual(sent.filter { $0 / 1_000 == producer }, (0..<100).map { producer * 1_000 + $0 }, file: file, line: line)
      }
      if replayCount > 0 {
        XCTAssertEqual(Array(sent.suffix(replayCount)), replayed, file: file, line: line)
      }
      if let storedValue = storedValue {
        XCTAssertEqual(receivedFirst.last, storedValue, file: file, line: line)
      }
    }
  }

  private func collect<Iterator: AsyncIteratorProtocol>(_ iterator: Iterator) async throws -> [Iterator.Element] {
    var iterator = iterator
    var values: [Iterator.Element] = []
    while let value = try await iterator.next() { values.append(value) }
    return values
  }
}
