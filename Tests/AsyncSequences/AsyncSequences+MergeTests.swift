//
//  AsyncSequences+Merge.swift
//
//
//  Created by Thibault Wittemberg on 01/01/2022.
//

import Combine
import AsyncExtensions
import XCTest

private struct MockError: Error, Equatable {
    let code: Int
}

private struct TimedAsyncSequence<Element>: AsyncSequence, AsyncIteratorProtocol {
    typealias Element = Element
    typealias AsyncIterator = TimedAsyncSequence

    private let intervalInMills: [UInt64]
    private var iterator: Array<Element>.Iterator
    private var index = 0
    private let indexOfError: Int?

    init(intervalInMills: [UInt64], sequence: [Element], indexOfError: Int? = nil) {
        self.intervalInMills = intervalInMills
        self.iterator = sequence.makeIterator()
        self.indexOfError = indexOfError
    }

    mutating func next() async throws -> Element? {

        if let indexOfError = self.indexOfError, self.index == indexOfError {
            throw MockError(code: 1)
        }

        if self.index < self.intervalInMills.count {
            try await Task.sleep(nanoseconds: self.intervalInMills[index] * 1_000_000)
            self.index += 1
        }
        return self.iterator.next()
    }

    func makeAsyncIterator() -> AsyncIterator {
        self
    }
}

final class AsyncSequences_MergeTests: XCTestCase {
    func testMerge_merges_sequences_according_to_the_timeline_using_asyncSequences() async throws {
        // -- 0 ------------------------------- 1200 ---------------------------
        // ------- 300 ------------- 900 ------------------------------ 1800 ---
        // --------------- 600 --------------------------- 1500 ----------------
        // -- a --- c ----- f ------- d --------- b -------- g ---------- e ----
        //
        // output should be: a c f d b g e
        let expectedElements = ["a", "c", "f", "d", "b", "g", "e"]

        let asyncSequence1 = TimedAsyncSequence(intervalInMills: [0, 1200], sequence: ["a", "b"])
        let asyncSequence2 = TimedAsyncSequence(intervalInMills: [300, 600, 900], sequence: ["c", "d", "e"])
        let asyncSequence3 = TimedAsyncSequence(intervalInMills: [600, 1100], sequence: ["f", "g"])

        let sut = AsyncSequences.Merge(asyncSequence1, asyncSequence2, asyncSequence3)

        var receivedElements = [String]()
        for try await element in sut {
            try await Task.sleep(nanoseconds: 110_000_000)
            receivedElements.append(element)
        }

        XCTAssertEqual(receivedElements, expectedElements)
    }

    func testMerge_merges_sequences_according_to_the_timeline_using_streams() {
        let readyToBeIteratedExpectation = expectation(description: "The merged sequence is ready to be iterated")
        let canSend2Expectation = expectation(description: "2 can be sent")
        let canSend3Expectation = expectation(description: "3 can be sent")
        let canSend4Expectation = expectation(description: "4 can be sent")
        let canSend5Expectation = expectation(description: "5 can be sent")
        let canSend6Expectation = expectation(description: "6 can be sent")

        let mergedSequenceIsFinisedExpectation = expectation(description: "The merged sequence is finished")

        let asyncSequence1 = AsyncStreams.Passthrough<Int>()
        let asyncSequence2 = AsyncStreams.Passthrough<Int>()
        let asyncSequence3 = AsyncStreams.Passthrough<Int>()

        let sut = AsyncSequences.Merge(asyncSequence1, asyncSequence2, asyncSequence3)

        Task {
            var receivedElements = [Int]()

            var iterator = sut.makeAsyncIterator()
            readyToBeIteratedExpectation.fulfill()
            while let element = try await iterator.next() {
                receivedElements.append(element)
                if element == 1 {
                    canSend2Expectation.fulfill()
                }
                if element == 2 {
                    canSend3Expectation.fulfill()
                }
                if element == 3 {
                    canSend4Expectation.fulfill()
                }
                if element == 4 {
                    canSend5Expectation.fulfill()
                }
                if element == 5 {
                    canSend6Expectation.fulfill()
                }
            }
            XCTAssertEqual(receivedElements, [1, 2, 3, 4, 5, 6])
            mergedSequenceIsFinisedExpectation.fulfill()
        }

        wait(for: [readyToBeIteratedExpectation], timeout: 1)

        asyncSequence1.nonBlockingSend(1)
        wait(for: [canSend2Expectation], timeout: 1)

        asyncSequence2.nonBlockingSend(2)
        wait(for: [canSend3Expectation], timeout: 1)

        asyncSequence3.nonBlockingSend(3)
        wait(for: [canSend4Expectation], timeout: 1)

        asyncSequence3.nonBlockingSend(4)
        wait(for: [canSend5Expectation], timeout: 1)

        asyncSequence2.nonBlockingSend(5)
        wait(for: [canSend6Expectation], timeout: 1)

        asyncSequence1.nonBlockingSend(6)
        asyncSequence1.nonBlockingSend(termination: .finished)
        asyncSequence2.nonBlockingSend(termination: .finished)
        asyncSequence3.nonBlockingSend(termination: .finished)

        wait(for: [mergedSequenceIsFinisedExpectation], timeout: 1)
    }

    func testMerge_returns_empty_sequence_when_all_sequences_are_empty() async throws {
        var receivedResult = [Int]()

        let asyncSequence1 = AsyncSequences.Empty<Int>()
        let asyncSequence2 = AsyncSequences.Empty<Int>()
        let asyncSequence3 = AsyncSequences.Empty<Int>()

        let sut = AsyncSequences.Merge([asyncSequence1, asyncSequence2, asyncSequence3])

        for try await element in sut {
            receivedResult.append(element)
        }

        XCTAssertTrue(receivedResult.isEmpty)
    }

    func testMerge_returns_original_sequence_when_one_sequence_is_empty() async throws {
        let expectedResult = [1, 2, 3]
        var receivedResult = [Int]()

        let asyncSequence1 = expectedResult.asyncElements
        let asyncSequence2 = AsyncSequences.Empty<Int>()

        let sut = AsyncSequences.Merge(asyncSequence1.eraseToAnyAsyncSequence(), asyncSequence2.eraseToAnyAsyncSequence())

        for try await element in sut {
            receivedResult.append(element)
        }

        XCTAssertEqual(receivedResult, expectedResult)
    }

    func testMerge_propagates_error() {
        let readyToBeIteratedExpectation = expectation(description: "The merged sequence is ready to be iterated")
        let canSend2Expectation = expectation(description: "2 can be sent")
        let canSend3Expectation = expectation(description: "3 can be sent")
        let mergedSequenceIsFinisedExpectation = expectation(description: "The merged sequence is finished")

        let asyncSequence1 = AsyncStreams.Passthrough<Int>()
        let asyncSequence2 = AsyncStreams.Passthrough<Int>()

        let sut = AsyncSequences.Merge(asyncSequence1, asyncSequence2)

        Task {
            var receivedElements = [Int]()

            var iterator = sut.makeAsyncIterator()
            readyToBeIteratedExpectation.fulfill()
            do {
                while let element = try await iterator.next() {
                    receivedElements.append(element)
                    if element == 1 {
                        canSend2Expectation.fulfill()
                    }
                    if element == 2 {
                        canSend3Expectation.fulfill()
                    }
                }
            } catch {
                XCTAssertEqual(receivedElements, [1, 2])
                mergedSequenceIsFinisedExpectation.fulfill()
            }
        }

        wait(for: [readyToBeIteratedExpectation], timeout: 1)

        asyncSequence1.nonBlockingSend(1)
        wait(for: [canSend2Expectation], timeout: 1)

        asyncSequence2.nonBlockingSend(2)
        wait(for: [canSend3Expectation], timeout: 1)

        asyncSequence1.nonBlockingSend(termination: .failure(MockError(code: 1)))

        wait(for: [mergedSequenceIsFinisedExpectation], timeout: 1)
    }

    func testMerge_finishes_when_task_is_cancelled() {
        let canCancelExpectation = expectation(description: "The first element has been emitted")
        let hasCancelExceptation = expectation(description: "The task has been cancelled")
        let taskHasFinishedExpectation = expectation(description: "The task has finished")

        let asyncSequence1 = TimedAsyncSequence(intervalInMills: [100, 100, 100], sequence: [1, 2, 3])
        let asyncSequence2 = TimedAsyncSequence(intervalInMills: [50, 100, 100, 100], sequence: [6, 7, 8, 9])
        let asyncSequence3 = TimedAsyncSequence(intervalInMills: [1, 399], sequence: [10, 11])

        let sut = AsyncSequences.Merge(asyncSequence1, asyncSequence2, asyncSequence3)

        let task = Task {
            var firstElement: Int?
            for try await element in sut {
                firstElement = element
                canCancelExpectation.fulfill()
                wait(for: [hasCancelExceptation], timeout: 5)
            }
            XCTAssertEqual(firstElement, 10)
            taskHasFinishedExpectation.fulfill()
        }

        wait(for: [canCancelExpectation], timeout: 5) // one element has been emitted, we can cancel the task

        task.cancel()

        hasCancelExceptation.fulfill() // we can release the lock in the for loop

        wait(for: [taskHasFinishedExpectation], timeout: 5) // task has been cancelled and has finished
    }

    func testMerge_finishes_when_task_is_cancelled_while_waiting_for_an_element() {
        let firstElementHasBeenReceivedExpectation = expectation(description: "The first elemenet has been received")
        let canIterateExpectation = expectation(description: "We can iterate")
        let hasCancelExceptation = expectation(description: "The iteration is cancelled")

        let asyncSequence1 = AsyncStreams.CurrentValue<Int>(1)
        let asyncSequence2 = AsyncStreams.Passthrough<Int>()

        let sut = AsyncSequences.Merge(asyncSequence1.eraseToAnyAsyncSequence(), asyncSequence2.eraseToAnyAsyncSequence())

        let task = Task {
            var iterator = sut.makeAsyncIterator()
            canIterateExpectation.fulfill()
            while let _ = try await iterator.next() {
                firstElementHasBeenReceivedExpectation.fulfill()
            }
            hasCancelExceptation.fulfill()
        }

        wait(for: [canIterateExpectation], timeout: 1)

        wait(for: [firstElementHasBeenReceivedExpectation], timeout: 1)

        task.cancel()

        wait(for: [hasCancelExceptation], timeout: 1)
    }
}
