@testable import AsyncExtensions
import XCTest

private final class LifetimeFeature: Sendable {
  let values: AnyAsyncSequence<Int>
  let onDeinit: @Sendable () -> Void

  init(subject: AsyncCurrentValueSubject<Int>, onDeinit: @Sendable @escaping () -> Void) {
    self.values = subject.eraseToAnyAsyncSequence()
    self.onDeinit = onDeinit
  }

  deinit { onDeinit() }
}

private final class LifetimeDevice: @unchecked Sendable {
  // The test removes the feature only after the consumer has built its inner iterator.
  var features: [AnyAsyncSequence<LifetimeFeature>]

  init(feature: LifetimeFeature) {
    features = [AsyncJustSequence(feature).eraseToAnyAsyncSequence()]
  }
}

final class AsyncFlatMapLatestLifetimeTests: XCTestCase {
  func test_removing_feature_releases_it_while_its_inner_subject_remains_subscribed() async throws {
    let subject = AsyncCurrentValueSubject<Int>(50)
    let released = expectation(description: "Consumed feature released")
    let device = LifetimeDevice(feature: LifetimeFeature(subject: subject) { released.fulfill() })
    let result: AnyAsyncSequence<Int> = AsyncJustSequence(device)
      .eraseToAnyAsyncSequence()
      .flatMapLatest { device -> AnyAsyncSequence<Int> in
        device.features.first!.flatMap { $0.values }.eraseToAnyAsyncSequence()
      }
      .eraseToAnyAsyncSequence()
    let receivedInitial = expectation(description: "Initial value received")
    let receivedLater = expectation(description: "Inner subscription still active")
    let task = Task {
      var received = [Int]()
      for try await value in result {
        received.append(value)
        if value == 50 { receivedInitial.fulfill() }
        if value == 75 { receivedLater.fulfill() }
      }
      return received
    }

    await fulfillment(of: [receivedInitial], timeout: 2)
    device.features.removeFirst()
    await fulfillment(of: [released], timeout: 2)
    subject.send(75)
    await fulfillment(of: [receivedLater], timeout: 2)
    task.cancel()
    let received = try await task.value
    XCTAssertEqual(received, [50, 75])
  }
}
