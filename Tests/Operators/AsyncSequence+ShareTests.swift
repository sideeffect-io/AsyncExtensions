//
//  AsyncSequence+ShareTests.swift
//
//
//  Created by Thibault Wittemberg on 03/03/2022.
//

import AsyncExtensions
import XCTest

private extension DispatchTimeInterval {
  var nanoseconds: UInt64 {
    switch self {
      case .nanoseconds(let value) where value >= 0: return UInt64(value)
      case .microseconds(let value) where value >= 0: return UInt64(value) * 1000
      case .milliseconds(let value) where value >= 0: return UInt64(value) * 1_000_000
      case .seconds(let value) where value >= 0: return UInt64(value) * 1_000_000_000
      case .never: return .zero
      default: return .zero
    }
  }
}

private struct LongAsyncSequence<Element>: AsyncSequence, AsyncIteratorProtocol {
  typealias Element = Element
  typealias AsyncIterator = LongAsyncSequence
  
  var elements: IndexingIterator<[Element]>
  let interval: DispatchTimeInterval
  var currentIndex = -1
  let failAt: Int?
  var hasEmitted = false
  let onCancel: () -> Void
  
  init(elements: [Element], interval: DispatchTimeInterval = .seconds(0), failAt: Int? = nil, onCancel: @escaping () -> Void = {}) {
    self.onCancel = onCancel
    self.elements = elements.makeIterator()
    self.failAt = failAt
    self.interval = interval
  }
  
  mutating func next() async throws -> Element? {
    return try await withTaskCancellationHandler {
      try await Task.sleep(nanoseconds: self.interval.nanoseconds)
      self.currentIndex += 1
      if self.currentIndex == self.failAt {
        throw MockError(code: 0)
      }
      return self.elements.next()
    } onCancel: { [onCancel] in
      onCancel()
    }
  }
  
  func makeAsyncIterator() -> AsyncIterator {
    self
  }
}

final class AsyncSequence_ShareTests: XCTestCase {
  func test_share_multicasts_values_to_clientLoops() async {
    let tasksHaveFinishedExpectation = expectation(description: "the tasks have finished")
    tasksHaveFinishedExpectation.expectedFulfillmentCount = 2
    
    let sut = LongAsyncSequence(
      elements: ["1", "2", "3"],
      interval: .milliseconds(200)
    ).share()
    
    Task(priority: .high) {
      var received = [String]()
      try await sut.collect { received.append($0) }
      XCTAssertEqual(received, ["1", "2", "3"])
      tasksHaveFinishedExpectation.fulfill()
    }
    
    Task(priority: .high) {
      var received = [String]()
      try await sut.collect { received.append($0) }
      XCTAssertEqual(received, ["1", "2", "3"])
      tasksHaveFinishedExpectation.fulfill()
    }
    
    await fulfillment(of: [tasksHaveFinishedExpectation], timeout: 5)
  }
}
