//
//  AsyncSequences+TimerTests.swift
//  
//
//  Created by Thibault Wittemberg on 06/03/2022.
//

import AsyncExtensions
import XCTest

final class AsyncSequences_TimerTests: XCTestCase {
    func testTimer_finishes_when_task_is_cancelled() {
        let canCancelExpectation = expectation(description: "the timer can be cancelled")
        let asyncSequenceHasFinishedExpectation = expectation(description: "The async sequence has finished")

        let sut = AsyncSequences.Timer(priority: .userInitiated, every: .milliSeconds(100))

        let task = Task {
            var index = 1
            for try await _ in sut {
                if index == 10 {
                    canCancelExpectation.fulfill()
                }
                index += 1
            }
            asyncSequenceHasFinishedExpectation.fulfill()
        }

        wait(for: [canCancelExpectation], timeout: 5)

        task.cancel()

        wait(for: [asyncSequenceHasFinishedExpectation], timeout: 5)
    }

    func testTimer_finishes_when_cancel_is_called() async throws {
        let sut = AsyncSequences.Timer(priority: .userInitiated, every: .milliSeconds(100))

        var index = 1
        for try await _ in sut {
            if index == 10 {
                sut.cancel()
            }
            index += 1
        }

        XCTAssertEqual(index, 11)
    }
}
