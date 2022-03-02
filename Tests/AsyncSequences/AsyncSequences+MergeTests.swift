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
        // -- 0 ------------------------------- 1000 ----------------------------- 2000 -
        // --------------- 500 --------------------------------- 1500 -------------------
        // -- a ----------- d ------------------ b --------------- e --------------- c --
        //
        // output should be: a, d, b, e, c
        let expectedElements = ["a", "d", "b", "e", "c"]

        let asyncSequence1 = TimedAsyncSequence(intervalInMills: [0, 1000, 1000], sequence: ["a", "b", "c"])
        let asyncSequence2 = TimedAsyncSequence(intervalInMills: [500, 1000], sequence: ["d", "e"])

        let sut = AsyncSequences.Merge(asyncSequence1, asyncSequence2)

        var receivedElements = [String]()
        for try await element in sut {
            try await Task.sleep(nanoseconds: 110_000_000)
            receivedElements.append(element)
        }

        XCTAssertEqual(receivedElements, expectedElements)
    }

    func testMerge_merges_sequences_according_to_the_timeline_using_streams() {
        let canSend2Expectation = expectation(description: "2 can be sent")
        let canSend3Expectation = expectation(description: "3 can be sent")
        let canSend4Expectation = expectation(description: "4 can be sent")
        let canSend5Expectation = expectation(description: "5 can be sent")
        let canSend6Expectation = expectation(description: "6 can be sent")
        let canSendFinishExpectation = expectation(description: "finish can be sent")

        let mergedSequenceIsFinisedExpectation = expectation(description: "The merged sequence is finished")

        let stream1 = AsyncStreams.CurrentValue<Int>(1)
        let stream2 = AsyncStreams.Passthrough<Int>()
        let stream3 = AsyncStreams.Passthrough<Int>()

        let sut = AsyncSequences.Merge(stream1.eraseToAnyAsyncSequence(), stream2.eraseToAnyAsyncSequence(), stream3.eraseToAnyAsyncSequence())

        Task {
            var receivedElements = [Int]()

            for try await element in sut {
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

                if element == 6 {
                    canSendFinishExpectation.fulfill()
                }
            }
            XCTAssertEqual(receivedElements, [1, 2, 3, 4, 5, 6])
            mergedSequenceIsFinisedExpectation.fulfill()
        }

        wait(for: [canSend2Expectation], timeout: 1)

        stream2.send(2)
        wait(for: [canSend3Expectation], timeout: 1)

        stream3.send(3)
        wait(for: [canSend4Expectation], timeout: 1)

        stream3.send(4)
        wait(for: [canSend5Expectation], timeout: 1)

        stream2.send(5)
        wait(for: [canSend6Expectation], timeout: 1)

        stream1.send(6)

        wait(for: [canSendFinishExpectation], timeout: 1)

        stream1.send(termination: .finished)
        stream2.send(termination: .finished)
        stream3.send(termination: .finished)

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
        let canSend2Expectation = expectation(description: "2 can be sent")
        let canSend3Expectation = expectation(description: "3 can be sent")
        let mergedSequenceIsFinishedExpectation = expectation(description: "The merged sequence is finished")

        let stream1 = AsyncStreams.CurrentValue<Int>(1)
        let stream2 = AsyncStreams.Passthrough<Int>()

        let sut = AsyncSequences.Merge(stream1.eraseToAnyAsyncSequence(), stream2.eraseToAnyAsyncSequence())

        Task {
            var receivedElements = [Int]()
            do {
                for try await element in sut {
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
                mergedSequenceIsFinishedExpectation.fulfill()
            }
        }

        wait(for: [canSend2Expectation], timeout: 1)

        stream2.send(2)
        wait(for: [canSend3Expectation], timeout: 1)

        stream1.send(termination: .failure(MockError(code: 1)))

        wait(for: [mergedSequenceIsFinishedExpectation], timeout: 1)
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
