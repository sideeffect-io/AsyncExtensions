//
//  AsyncSequence+PrependTests.swift
//  
//
//  Created by Thibault Wittemberg on 01/01/2022.
//

import AsyncExtensions
import XCTest

private struct MockError: Error, Equatable {
    let code: Int
}

final class AsyncSequence_PrependTests: XCTestCase {
    func testPrepend_prepends_an_element_to_the_source_asyncSequence() async throws {
        let expectedResult = [0, 1, 2, 3, 4, 5]
        var receivedResult = [Int]()

        let sut = [1, 2, 3, 4, 5].asyncElements

        let prependedSequence = sut.prepend(0)
        for try await element in prependedSequence {
            receivedResult.append(element)
        }

        XCTAssertEqual(receivedResult, expectedResult)
    }

    func testPrepend_prepends_an_element_built_with_factory_to_the_source_asyncSequence() async throws {
        let expectedResult = [0, 1, 2, 3, 4, 5]
        var receivedResult = [Int]()

        let sut = [1, 2, 3, 4, 5].asyncElements

        let prependedSequence = sut.prepend { 0 }
        for try await element in prependedSequence {
            receivedResult.append(element)
        }

        XCTAssertEqual(receivedResult, expectedResult)
    }

    func testPrepend_throws_when_factory_function_throws() async throws {
        let expectedError = MockError(code: Int.random(in: 0...100))

        let sut = [1, 2, 3, 4, 5].asyncElements

        let prependedSequence = sut.prepend { throw expectedError }
        do {
            for try await _ in prependedSequence {}
            XCTFail("The AsyncSequence should fail")
        } catch {
            XCTAssertEqual(error as? MockError, expectedError)
        }
    }

    func testPrepend_finishes_when_task_is_cancelled() {
        let canCancelExpectation = expectation(description: "The first element has been emitted")
        let hasCancelExceptation = expectation(description: "The task has been cancelled")
        let taskHasFinishedExpectation = expectation(description: "The task has finished")

        let sut = [1, 2, 3, 4, 5].asyncElements

        let prependedSequence = sut.prepend(0)

        let task = Task {
            var firstElement: Int?
            for try await element in prependedSequence {
                firstElement = element
                canCancelExpectation.fulfill()
                wait(for: [hasCancelExceptation], timeout: 5)
            }
            XCTAssertEqual(firstElement, 0)
            taskHasFinishedExpectation.fulfill()
        }

        wait(for: [canCancelExpectation], timeout: 5) // one element has been emitted, we can cancel the task

        task.cancel()

        hasCancelExceptation.fulfill() // we can release the lock in the for loop

        wait(for: [taskHasFinishedExpectation], timeout: 5) // task has been cancelled and has finished
    }
}
