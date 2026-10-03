@testable import AsyncExtensions
import XCTest

private final class LifetimePayload: Sendable {
  let onDeinit: @Sendable () -> Void
  init(onDeinit: @Sendable @escaping () -> Void) { self.onDeinit = onDeinit }
  deinit { onDeinit() }
}

final class AsyncSubjectLifetimeTests: XCTestCase {
  func test_abandoned_passthrough_iterators_release_their_buffered_values() {
    assertBufferedValueReleased(AsyncPassthroughSubject<LifetimePayload>())
    assertBufferedValueReleased(AsyncThrowingPassthroughSubject<LifetimePayload, Error>())
  }

  private func assertBufferedValueReleased<S: AsyncSubject>(_ subject: S) where S.Element == LifetimePayload {
    let released = ManagedCriticalState(false)
    var iterator: S.AsyncIterator? = subject.makeAsyncIterator()
    var payload: LifetimePayload? = LifetimePayload { released.apply(criticalState: true) }
    subject.send(payload!)
    payload = nil
    withExtendedLifetime(iterator) { XCTAssertFalse(released.criticalState) }
    iterator = nil
    XCTAssertTrue(released.criticalState)
  }

  func test_last_iterator_copy_unregisters_each_subject_subscription() {
    let passthrough = AsyncPassthroughSubject<Int>()
    assertUnregister(passthrough) { passthrough.state.withCriticalRegion { $0.channels.count } }
    let current = AsyncCurrentValueSubject<Int>(0)
    assertUnregister(current) { current.state.withCriticalRegion { $0.channels.count } }
    let replay = AsyncReplaySubject<Int>(bufferSize: 1)
    assertUnregister(replay) { replay.state.withCriticalRegion { $0.channels.count } }
    let throwingPassthrough = AsyncThrowingPassthroughSubject<Int, Error>()
    assertUnregister(throwingPassthrough) { throwingPassthrough.state.withCriticalRegion { $0.channels.count } }
    let throwingCurrent = AsyncThrowingCurrentValueSubject<Int, Error>(0)
    assertUnregister(throwingCurrent) { throwingCurrent.state.withCriticalRegion { $0.channels.count } }
    let throwingReplay = AsyncThrowingReplaySubject<Int, Error>(bufferSize: 1)
    assertUnregister(throwingReplay) { throwingReplay.state.withCriticalRegion { $0.channels.count } }
  }

  private func assertUnregister<S: AsyncSubject>(_ subject: S, subscriberCount: () -> Int) {
    var iterator: S.AsyncIterator? = subject.makeAsyncIterator()
    var copy = iterator
    XCTAssertEqual(subscriberCount(), 1)
    iterator = nil
    withExtendedLifetime(copy) { XCTAssertEqual(subscriberCount(), 1) }
    copy = nil
    XCTAssertEqual(subscriberCount(), 0)
  }
}
