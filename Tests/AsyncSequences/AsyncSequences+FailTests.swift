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
        let exp = expectation(description: "AsyncSequence finishes when task is cancelled")

        let failSequence = AsyncSequences.Fail<Int>(error: MockError(code: 1))

        Task {
            do {
                for try await _ in failSequence {
                    XCTFail("The AsyncSequence should not output elements")
                }
                exp.fulfill()
            } catch {
                XCTFail("The AsyncSequence should not throw an error")
            }

        }.cancel()

        waitForExpectations(timeout: 1)
    }
}
