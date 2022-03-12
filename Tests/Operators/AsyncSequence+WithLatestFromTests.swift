//
//  AsyncSequence+WithLatestFromTests.swift
//  
//
//  Created by Thibault Wittemberg on 07/03/2022.
//

import AsyncExtensions
import XCTest

final class AsyncSequence_WithLatestFromTests: XCTestCase {
    func test_withLatestFrom_combines_values_and_finishes_if_other_finishes() {
        // time: |---------------------------------------------------------
        // seq1: |    1         2      3              4                 5
        // seq2: |        "1"                "2"            finish
        // expected: (1, "1") -> (2, "1") -> (3, "1") -> (4, "2") -> finished
        let otherHasEmitted1Expectation = expectation(description: "the other sequence has produced '1'")
        let otherHasEmitted2Expectation = expectation(description: "the other sequence has produced '2'")
        let otherIsFinishedExpectation = expectation(description: "the other sequence is finished")
        let sutIsFinishedExpectation = expectation(description: "the combined sequence is finished")

        let upstream = AsyncStreams.CurrentValue<Int>(1)
        let other = AsyncStreams.Passthrough<String>()

        // monitoring the other sequence to drive the timeline
        Task(priority: .high) {
            try await other.collect { element in
                if element == "1" {
                    otherHasEmitted1Expectation.fulfill()
                }
                if element == "2" {
                    otherHasEmitted2Expectation.fulfill()
                }
            }
            otherIsFinishedExpectation.fulfill()
        }

        Task(priority: .low) {
            let sut = upstream.withLatestFrom(other, otherPriority: .high)
            var iterator = sut.makeAsyncIterator()

            other.send("1")
            wait(for: [otherHasEmitted1Expectation], timeout: 2)

            let element1 = try await iterator.next()
            XCTAssertEqual(element1?.0, 1)
            XCTAssertEqual(element1?.1, "1")

            upstream.send(2)

            let element2 = try await iterator.next()
            XCTAssertEqual(element2?.0, 2)
            XCTAssertEqual(element2?.1, "1")

            upstream.send(3)
            let element3 = try await iterator.next()
            XCTAssertEqual(element3?.0, 3)
            XCTAssertEqual(element3?.1, "1")

            other.send("2")
            wait(for: [otherHasEmitted2Expectation], timeout: 2)

            upstream.send(4)
            let element4 = try await iterator.next()
            XCTAssertEqual(element4?.0, 4)
            XCTAssertEqual(element4?.1, "2")

            other.send(termination: .finished)
            wait(for: [otherIsFinishedExpectation], timeout: 2)

            upstream.send(5)
            let element5 = try await iterator.next()
            XCTAssertNil(element5)

            sutIsFinishedExpectation.fulfill()
        }

        wait(for: [sutIsFinishedExpectation], timeout: 2)
    }

    func test_withLatestFrom_finishes_if_upstream_finishes() async throws {
        let upstream = AsyncStreams.CurrentValue<Int>(1)
        let other = AsyncStreams.CurrentValue<String>("1")

        let sut = upstream.withLatestFrom(other)
        var iterator = sut.makeAsyncIterator()

        let element1 = try await iterator.next()
        XCTAssertEqual(element1?.0, 1)
        XCTAssertEqual(element1?.1, "1")

        upstream.send(termination: .finished)

        let element2 = try await iterator.next()
        XCTAssertNil(element2)
    }

    func test_withLatestFrom_finishes_when_task_is_cancelled() {
        let canCancelExpectation = expectation(description: "The first element has been emitted")
        let hasCancelExceptation = expectation(description: "The task has been cancelled")
        let taskHasFinishedExpectation = expectation(description: "The task has finished")

        let upstream = AsyncStreams.CurrentValue<Int>(1)
        let other = AsyncStreams.CurrentValue<String>("1")

        let sut = upstream.withLatestFrom(other)

        let task = Task {
            var firstElement: (Int, String)?
            for try await element in sut {
                firstElement = element
                canCancelExpectation.fulfill()
                wait(for: [hasCancelExceptation], timeout: 5)
            }
            XCTAssertEqual(firstElement?.0, 1)
            XCTAssertEqual(firstElement?.1, "1")
            taskHasFinishedExpectation.fulfill()
        }

        wait(for: [canCancelExpectation], timeout: 5) // one element has been emitted, we can cancel the task

        task.cancel()

        hasCancelExceptation.fulfill() // we can release the lock in the for loop

        wait(for: [taskHasFinishedExpectation], timeout: 5) // task has been cancelled and has finished
    }
}
