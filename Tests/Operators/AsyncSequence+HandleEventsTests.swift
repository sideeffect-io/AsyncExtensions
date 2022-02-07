//
//  AsyncSequence+HandleEventsTests.swift
//
//
//  Created by Thibault Wittemberg on 01/01/2022.
//

import AsyncExtensions
import XCTest

private struct MockError: Error, Equatable {
    let code: Int
}

final class AsyncSequence_HandleEventsTests: XCTestCase {
    func testHandleEvents_calls_blocks_when_not_cancelled_and_no_error() async throws {
        var received = [String]()

        let sourceSequence = [1, 2, 3, 4, 5].asyncElements
        let sut = sourceSequence.handleEvents {
            received.append("start")
        } onElement: { element in
            received.append("\(element)")
        } onCancel: {
            received.append("cancelled")
        } onFinish: { completion in
            received.append("finish \(completion)")
        }

        for try await _ in sut {}

        XCTAssertEqual(received, ["start", "1", "2", "3", "4", "5", "finish finished"])
    }

    func testHandleEvents_calls_onCancel_when_task_is_cancelled() {
        var received = [String]()

        let firstElementHasBeenReceivedExpectation = expectation(description: "First element has been emitted")
        let taskHasBeenCancelledExpectation = expectation(description: "The task has been cancelled")
        let onCancelHasBeenCalledExpectation = expectation(description: "OnCancel has been called")

        let sourceSequence = AsyncStreams.CurrentValue<Int>(1)
        let sut = sourceSequence.handleEvents {
            received.append("start")
        } onElement: { element in
            received.append("\(element)")
        } onCancel: {
            received.append("cancelled")
            onCancelHasBeenCalledExpectation.fulfill()
        } onFinish: { completion in
            received.append("finish \(completion)")
        }

        let task = Task {
            for try await element in sut {
                if element == 1 {
                    firstElementHasBeenReceivedExpectation.fulfill()
                }

                wait(for: [taskHasBeenCancelledExpectation], timeout: 1)
            }
        }

        wait(for: [firstElementHasBeenReceivedExpectation], timeout: 1)

        task.cancel()

        taskHasBeenCancelledExpectation.fulfill()

        wait(for: [onCancelHasBeenCalledExpectation], timeout: 1)

        XCTAssertEqual(received, ["start", "1", "cancelled"])
    }

    func testHandleEvents_calls_onFinish_with_failure_when_sequence_fails() async throws {
        let onFinishHasBeenCalledExpectation = expectation(description: "OnFinish has been called")

        var received = [String]()

        let expectedError = MockError(code: Int.random(in: 0...100))

        let sourceSequence = AsyncSequences.Fail<Int>(error: expectedError)
        let sut = sourceSequence.handleEvents {
            received.append("start")
        } onElement: { element in
            received.append("\(element)")
        } onCancel: {
            received.append("cancelled")
        } onFinish: { completion in
            if case let .failure(error) = completion {
                XCTAssertEqual(error as? MockError, expectedError)
            }
            onFinishHasBeenCalledExpectation.fulfill()
        }

        do {
            for try await _ in sut {}
        } catch {
            XCTAssertEqual(error as? MockError, expectedError)
        }

        await waitForExpectations(timeout: 1)
    }

    func testHandleEvents_finishes_when_task_is_cancelled() {
        let canCancelExpectation = expectation(description: "The first element has been emitted")
        let hasCancelExceptation = expectation(description: "The task has been cancelled")
        let taskHasFinishedExpectation = expectation(description: "The task has finished")

        let sut = (0...1_000_000)

        let handledSequence = sut.asyncElements.handleEvents()

        let task = Task {
            var firstElement: Int?
            for try await element in handledSequence {
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
