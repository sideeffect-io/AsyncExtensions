//
//  AsyncSequences+FromTests.swift
//  
//
//  Created by Thibault Wittemberg on 02/01/2022.
//

import AsyncExtensions
import XCTest

final class AsyncSequences_FromTests: XCTestCase {
    func testAsyncElements_returns_original_sequence() async throws {
        var receivedResult = [Int]()

        let sequence = [1, 2, 3, 4, 5]

        let sut = AsyncSequences.From(sequence)

        for try await element in sut {
            receivedResult.append(element)
        }

        XCTAssertEqual(receivedResult, sequence)
    }

    func testFrom_returns_an_asyncSequence_that_finishes_when_task_is_cancelled() throws {
        let canCancelExpectation = expectation(description: "The first element has been emitted")
        let hasCancelExceptation = expectation(description: "The task has been cancelled")

        let sequence = (0...1_000_000)

        let sut = AsyncSequences.From(sequence)

        let task = Task {
            var firstElement: Int?
            for try await element in sut {
                firstElement = element
                canCancelExpectation.fulfill()
                wait(for: [hasCancelExceptation], timeout: 5)
            }
            XCTAssertEqual(firstElement!, 0) // the AsyncSequence is cancelled having only emitted the first element
        }

        wait(for: [canCancelExpectation], timeout: 5) // one element has been emitted, we can cancel the task

        task.cancel()

        hasCancelExceptation.fulfill() // we can release the lock in the for loop
    }
}
