//
//  AsyncThrowingJustSequenceTests.swift
//
//
//  Created by Thibault Wittemberg on 04/01/2022.
//

@testable import AsyncExtensions
import XCTest

final class AsyncThrowingJustSequenceTests: XCTestCase {
  func test_AsyncThrowingJustSequence_outputs_expected_element_and_finishes() async throws {
    var receivedResult = [Int]()

    let element = Int.random(in: 0...100)
    let sut = AsyncThrowingJustSequence(element)

    for try await result in sut {
      receivedResult.append(result)
    }

    XCTAssertEqual(receivedResult, [element])
  }

  func test_AsyncThrowingJustSequence_outputs_expected_element_from_closure_and_finishes() async throws {
    var receivedResult = [Int]()

    let element = Int.random(in: 0...100)
    let sut = AsyncThrowingJustSequence(factory: {
      return element
    })

    for try await result in sut {
      receivedResult.append(result)
    }

    XCTAssertEqual(receivedResult, [element])
  }

  func test_AsyncThrowingJustSequence_fails_and_finishes() async {
    let sut = AsyncThrowingJustSequence<Int> { throw MockError(code: 1701) }

    do {
      for try await _ in sut {}
    } catch {
      XCTAssertEqual(error as? MockError, MockError(code: 1701))
    }
  }

  func test_AsyncThrowingJustSequence_returns_an_asyncSequence_that_finishes_without_elements_when_task_is_cancelled() async {
    let hasCancelledExpectation = expectation(description: "The task has been cancelled")
    let hasFinishedExpectation = expectation(description: "The AsyncSequence has finished")

    let justSequence = AsyncThrowingJustSequence<Int>(1)

    let task = Task {
      await fulfillment(of: [hasCancelledExpectation], timeout: 1)
      for try await _ in justSequence {
        XCTFail("The AsyncSequence should not output elements")
      }
      hasFinishedExpectation.fulfill()
    }

    task.cancel()

    hasCancelledExpectation.fulfill()

    await fulfillment(of: [hasFinishedExpectation], timeout: 1)
  }
}
