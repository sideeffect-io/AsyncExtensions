//
//  AsyncSequence+ShareTests.swift
//
//
//  Created by Thibault Wittemberg on 03/03/2022.
//

import AsyncExtensions
import XCTest

final class AsyncSequence_ShareTests: XCTestCase {
    func test_share_multicasts_values_to_clientLoops() {
        let tasksHaveFinishedExpectation = expectation(description: "the tasks have finished")
        tasksHaveFinishedExpectation.expectedFulfillmentCount = 2

        let sut = AsyncLazySequence(["first", "second", "third"])
            .share()

        Task {
            var received = [String]()
            await sut
                .collect { received.append($0) }
            XCTAssertEqual(received, ["first", "second", "third"])
            tasksHaveFinishedExpectation.fulfill()
        }

        Task {
            var received = [String]()
            await sut
                .collect { received.append($0) }
            XCTAssertEqual(received, ["first", "second", "third"])
            tasksHaveFinishedExpectation.fulfill()
        }

        waitForExpectations(timeout: 5)
    }
}
