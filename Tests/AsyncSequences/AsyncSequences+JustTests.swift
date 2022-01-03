//
//  AsyncSequences+JustTests.swift
//  
//
//  Created by Thibault Wittemberg on 04/01/2022.
//

@testable import AsyncExtensions
import XCTest

final class AsyncSequences_JustTests: XCTestCase {
    func testInit_sets_element() async throws {
        let element = Int.random(in: 0...100)
        let sut = AsyncSequences.Just(element)
        let value = try await sut.element()
        XCTAssertEqual(value, element)
    }

    func testJust_outputs_expected_element_and_finishes() async throws {
        var receivedResult = [Int]()

        let element = Int.random(in: 0...100)
        let sut = AsyncSequences.Just(element)

        for try await result in sut {
            receivedResult.append(result)
        }

        XCTAssertEqual(receivedResult, [element])
    }

    func testJust_returns_an_asyncSequence_that_finishes_without_elements_when_task_is_cancelled() {
        let hasCancelledExpectation = expectation(description: "The task has been cancelled")
        let hasFinishedExpectation = expectation(description: "The AsyncSequence has finished")

        let justSequence = AsyncSequences.Just<Int>(1)

        let task = Task {
            wait(for: [hasCancelledExpectation], timeout: 1)
            for try await _ in justSequence {
                XCTFail("The AsyncSequence should not output elements")
            }
            hasFinishedExpectation.fulfill()
        }

        task.cancel()

        hasCancelledExpectation.fulfill()

        wait(for: [hasFinishedExpectation], timeout: 1)
    }
}
