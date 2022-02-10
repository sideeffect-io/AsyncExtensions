//
//  AsyncSequences+FailTests.swift
//  
//
//  Created by Thibault Wittemberg on 04/01/2022.
//

@testable import AsyncExtensions
import XCTest

private struct MockError: Error, Equatable {
    let code: Int
}

final class AsyncSequences_FailTests: XCTestCase {
    func testInit_sets_error() {
        let mockError = MockError(code: Int.random(in: 0...100))
        let sut = AsyncSequences.Fail<Int>(error: mockError)
        XCTAssertEqual(sut.error as? MockError, mockError)
    }

    func testFail_throws_expected_error() async {
        let mockError = MockError(code: Int.random(in: 0...100))
        var receivedResult = [Int]()

        let sut = AsyncSequences.Fail<Int>(error: mockError)

        do {
            for try await result in sut {
                receivedResult.append(result)
            }
        } catch {
            XCTAssertEqual(error as? MockError, mockError)
        }

        XCTAssertTrue(receivedResult.isEmpty)
    }

    func testFail_returns_an_asyncSequence_that_finishes_without_error_when_task_is_cancelled() {
        let taskHasBeenCancelledExpectation = expectation(description: "The task has been cancelled")
        let sequenceHasFinishedExpectation = expectation(description: "The async sequence has finished")

        let failSequence = AsyncSequences.Fail<Int>(error: MockError(code: 1))

        let task = Task {
            do {
                var iterator = failSequence.makeAsyncIterator()
                wait(for: [taskHasBeenCancelledExpectation], timeout: 1)
                while let _ = try await iterator.next() {
                    XCTFail("The AsyncSequence should not output elements")
                }
                sequenceHasFinishedExpectation.fulfill()
            } catch {
                XCTFail("The AsyncSequence should not throw an error")
            }

        }

        task.cancel()

        taskHasBeenCancelledExpectation.fulfill()

        wait(for: [sequenceHasFinishedExpectation], timeout: 1)
    }
}
