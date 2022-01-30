//
//  AsyncSequences+ZipTests.swift
//  
//
//  Created by Thibault Wittemberg on 14/01/2022.
//

import AsyncExtensions
import XCTest

private struct TimedAsyncSequence<Element>: AsyncSequence, AsyncIteratorProtocol {
    typealias Element = Element
    typealias AsyncIterator = TimedAsyncSequence

    private let intervalInMills: UInt64
    private var iterator: Array<Element>.Iterator

    init(intervalInMills: UInt64, sequence: [Element]) {
        self.intervalInMills = intervalInMills
        self.iterator = sequence.makeIterator()
    }

    mutating func next() async throws -> Element? {
        try await Task.sleep(nanoseconds: self.intervalInMills * 1_000_000)
        return self.iterator.next()
    }

    func makeAsyncIterator() -> AsyncIterator {
        self
    }
}

private struct MockError: Error, Equatable {
    let count: Int
}

final class AsyncSequences_ZipTests: XCTestCase {
    func testZip2_respects_chronology_and_ends_when_first_sequence_ends() async throws {
        let asyncSeq1 = TimedAsyncSequence(intervalInMills: 50, sequence: [1, 2, 3, 4])
        let asyncSeq2 = TimedAsyncSequence(intervalInMills: 10, sequence: ["6", "7", "8", "9", "10"])

        let sut = AsyncSequences.Zip2(asyncSeq1, asyncSeq2)

        var receivedElements = [(Int, String)]()

        for try await element in sut {
            receivedElements.append(element)
        }

        XCTAssertEqual(receivedElements.map { $0.0 }, [1, 2, 3, 4])
        XCTAssertEqual(receivedElements.map { $0.1 }, ["6", "7", "8", "9"])
    }

    func testZip2_respects_chronology_and_ends_when_second_sequence_ends() async throws {
        let asyncSeq1 = TimedAsyncSequence(intervalInMills: 50, sequence: [1, 2, 3, 4, 5])
        let asyncSeq2 = TimedAsyncSequence(intervalInMills: 10, sequence: ["6", "7", "8"])

        let sut = AsyncSequences.Zip2(asyncSeq1, asyncSeq2)

        var receivedElements = [(Int, String)]()

        for try await element in sut {
            receivedElements.append(element)
        }

        XCTAssertEqual(receivedElements.map { $0.0 }, [1, 2, 3])
        XCTAssertEqual(receivedElements.map { $0.1 }, ["6", "7", "8"])
    }

    func testZip2_propagates_error() async throws {
        let mockError = MockError(count: Int.random(in: 0...100))

        let asyncSeq1 = TimedAsyncSequence(intervalInMills: 50, sequence: [1, 2, 3, 4])
        let asyncSeq2 = AsyncSequences.Fail<String>(error: mockError)

        let sut = AsyncSequences.Zip2(asyncSeq1, asyncSeq2)

        do {
            for try await _ in sut {}
        } catch {
            XCTAssertEqual(error as? MockError, mockError)
        }
    }

    func testZip2_finishes_when_task_is_cancelled() {
        let canCancelExpectation = expectation(description: "The first element has been emitted")
        let hasCancelExceptation = expectation(description: "The task has been cancelled")
        let taskHasFinishedExpectation = expectation(description: "The task has finished")

        let asyncSeq1 = TimedAsyncSequence(intervalInMills: 50, sequence: [1, 2, 3, 4, 5])
        let asyncSeq2 = TimedAsyncSequence(intervalInMills: 10, sequence: ["6", "7", "8"])

        let sut = AsyncSequences.Zip2(asyncSeq1, asyncSeq2)

        let task = Task {
            var firstElement: (Int, String)?
            for try await element in sut {
                firstElement = element
                canCancelExpectation.fulfill()
                wait(for: [hasCancelExceptation], timeout: 5)
            }
            XCTAssertEqual(firstElement!.0, 1)
            XCTAssertEqual(firstElement!.1, "6")
            taskHasFinishedExpectation.fulfill()
        }

        wait(for: [canCancelExpectation], timeout: 5) // one element has been emitted, we can cancel the task

        task.cancel()

        hasCancelExceptation.fulfill() // we can release the lock in the for loop

        wait(for: [taskHasFinishedExpectation], timeout: 5) // task has been cancelled and has finished
    }

    func testZip3_respects_chronology_and_ends_when_first_sequence_ends() async throws {
        let asyncSeq1 = TimedAsyncSequence(intervalInMills: 50, sequence: [1, 2, 3])
        let asyncSeq2 = TimedAsyncSequence(intervalInMills: 10, sequence: ["6", "7", "8", "9", "10"])
        let asyncSeq3 = TimedAsyncSequence(intervalInMills: 30, sequence: [true, false, true, false, true])

        let sut = AsyncSequences.Zip3(asyncSeq1, asyncSeq2, asyncSeq3)

        var receivedElements = [(Int, String, Bool)]()

        for try await element in sut {
            receivedElements.append(element)
        }

        XCTAssertEqual(receivedElements.map { $0.0 }, [1, 2, 3])
        XCTAssertEqual(receivedElements.map { $0.1 }, ["6", "7", "8"])
        XCTAssertEqual(receivedElements.map { $0.2 }, [true, false, true])
    }

    func testZip3_respects_chronology_and_ends_when_second_sequence_ends() async throws {
        let asyncSeq1 = TimedAsyncSequence(intervalInMills: 50, sequence: [1, 2, 3, 4, 5])
        let asyncSeq2 = TimedAsyncSequence(intervalInMills: 10, sequence: ["6", "7", "8"])
        let asyncSeq3 = TimedAsyncSequence(intervalInMills: 30, sequence: [true, false, true, false, true])

        let sut = AsyncSequences.Zip3(asyncSeq1, asyncSeq2, asyncSeq3)

        var receivedElements = [(Int, String, Bool)]()

        for try await element in sut {
            receivedElements.append(element)
        }

        XCTAssertEqual(receivedElements.map { $0.0 }, [1, 2, 3])
        XCTAssertEqual(receivedElements.map { $0.1 }, ["6", "7", "8"])
        XCTAssertEqual(receivedElements.map { $0.2 }, [true, false, true])
    }

    func testZip3_respects_chronology_and_ends_when_third_sequence_ends() async throws {
        let asyncSeq1 = TimedAsyncSequence(intervalInMills: 50, sequence: [1, 2, 3, 4, 5])
        let asyncSeq2 = TimedAsyncSequence(intervalInMills: 10, sequence: ["6", "7", "8", "9", "10"])
        let asyncSeq3 = TimedAsyncSequence(intervalInMills: 30, sequence: [true, false, true])

        let sut = AsyncSequences.Zip3(asyncSeq1, asyncSeq2, asyncSeq3)

        var receivedElements = [(Int, String, Bool)]()

        for try await element in sut {
            receivedElements.append(element)
        }

        XCTAssertEqual(receivedElements.map { $0.0 }, [1, 2, 3])
        XCTAssertEqual(receivedElements.map { $0.1 }, ["6", "7", "8"])
        XCTAssertEqual(receivedElements.map { $0.2 }, [true, false, true])
    }

    func testZip3_propagates_error() async throws {
        let mockError = MockError(count: Int.random(in: 0...100))

        let asyncSeq1 = TimedAsyncSequence(intervalInMills: 50, sequence: [1, 2, 3, 4])
        let asyncSeq2 = TimedAsyncSequence(intervalInMills: 5, sequence: ["1", "2", "3", "4"])
        let asyncSeq3 = AsyncSequences.Fail<String>(error: mockError)

        let sut = AsyncSequences.Zip3(asyncSeq1, asyncSeq2, asyncSeq3)

        do {
            for try await _ in sut {}
        } catch {
            XCTAssertEqual(error as? MockError, mockError)
        }
    }

    func testZip3_finishes_when_task_is_cancelled() {
        let canCancelExpectation = expectation(description: "The first element has been emitted")
        let hasCancelExceptation = expectation(description: "The task has been cancelled")
        let taskHasFinishedExpectation = expectation(description: "The task has finished")

        let asyncSeq1 = TimedAsyncSequence(intervalInMills: 50, sequence: [1, 2, 3, 4, 5])
        let asyncSeq2 = TimedAsyncSequence(intervalInMills: 10, sequence: ["6", "7", "8"])
        let asyncSeq3 = TimedAsyncSequence(intervalInMills: 15, sequence: [true, false, true, false])

        let sut = AsyncSequences.Zip3(asyncSeq1, asyncSeq2, asyncSeq3)

        let task = Task {
            var firstElement: (Int, String, Bool)?
            for try await element in sut {
                firstElement = element
                canCancelExpectation.fulfill()
                wait(for: [hasCancelExceptation], timeout: 5)
            }
            XCTAssertEqual(firstElement!.0, 1) // the AsyncSequence is cancelled having only emitted the first element
            XCTAssertEqual(firstElement!.1, "6")
            XCTAssertEqual(firstElement!.2, true)
            taskHasFinishedExpectation.fulfill()
        }

        wait(for: [canCancelExpectation], timeout: 5) // one element has been emitted, we can cancel the task

        task.cancel()

        hasCancelExceptation.fulfill() // we can release the lock in the for loop

        wait(for: [taskHasFinishedExpectation], timeout: 5) // task has been cancelled and has finished
    }

    func testZip_respects_chronology_and_ends_when_any_sequence_ends() async throws {
        let asyncSeq1 = TimedAsyncSequence(intervalInMills: 50, sequence: [1, 2, 3, 4, 5])
        let asyncSeq2 = TimedAsyncSequence(intervalInMills: 10, sequence: [1, 2, 3])
        let asyncSeq3 = TimedAsyncSequence(intervalInMills: 30, sequence: [1, 2, 3, 4, 5])
        let asyncSeq4 = TimedAsyncSequence(intervalInMills: 5, sequence: [1, 2, 3])
        let asyncSeq5 = TimedAsyncSequence(intervalInMills: 20, sequence: [1, 2, 3, 4, 5])

        let sut = AsyncSequences.Zip(asyncSeq1, asyncSeq2, asyncSeq3, asyncSeq4, asyncSeq5)

        var receivedElements = [[Int]]()

        for try await element in sut {
            receivedElements.append(element)
        }

        XCTAssertEqual(receivedElements.count, 3)
        XCTAssertEqual(receivedElements[0], [1, 1, 1, 1, 1])
        XCTAssertEqual(receivedElements[1], [2, 2, 2, 2, 2])
        XCTAssertEqual(receivedElements[2], [3, 3, 3, 3, 3])
    }

    func testZip_propagates_error() async throws {
        let mockError = MockError(count: Int.random(in: 0...100))

        let asyncSeq1 = TimedAsyncSequence(intervalInMills: 5, sequence: [1, 2, 3, 4]).eraseToAnyAsyncSequence()
        let asyncSeq2 = TimedAsyncSequence(intervalInMills: 10, sequence: [1, 2, 3, 4]).eraseToAnyAsyncSequence()
        let asyncSeq3 = AsyncSequences.Fail<Int>(error: mockError).eraseToAnyAsyncSequence()
        let asyncSeq4 = TimedAsyncSequence(intervalInMills: 20, sequence: [1, 2, 3, 4]).eraseToAnyAsyncSequence()
        let asyncSeq5 = TimedAsyncSequence(intervalInMills: 15, sequence: [1, 2, 3, 4]).eraseToAnyAsyncSequence()

        let sut = AsyncSequences.Zip(asyncSeq1, asyncSeq2, asyncSeq3, asyncSeq4, asyncSeq5)

        do {
            for try await _ in sut {}
        } catch {
            XCTAssertEqual(error as? MockError, mockError)
        }
    }

    func testZip_finishes_when_task_is_cancelled() {
        let canCancelExpectation = expectation(description: "The first element has been emitted")
        let hasCancelExceptation = expectation(description: "The task has been cancelled")
        let taskHasFinishedExpectation = expectation(description: "The task has finished")
        
        let asyncSeq1 = TimedAsyncSequence(intervalInMills: 50, sequence: [1, 2, 3, 4, 5])
        let asyncSeq2 = TimedAsyncSequence(intervalInMills: 10, sequence: [1, 2, 3])
        let asyncSeq3 = TimedAsyncSequence(intervalInMills: 30, sequence: [1, 2, 3, 4, 5])
        let asyncSeq4 = TimedAsyncSequence(intervalInMills: 5, sequence: [1, 2, 3])
        let asyncSeq5 = TimedAsyncSequence(intervalInMills: 20, sequence: [1, 2, 3, 4, 5])

        let sut = AsyncSequences.Zip(asyncSeq1, asyncSeq2, asyncSeq3, asyncSeq4, asyncSeq5)

        let task = Task {
            var firstElement: [Int]?
            for try await element in sut {
                firstElement = element
                canCancelExpectation.fulfill()
                wait(for: [hasCancelExceptation], timeout: 5)
            }
            XCTAssertEqual(firstElement!, [1, 1, 1, 1, 1])
            taskHasFinishedExpectation.fulfill()
        }

        wait(for: [canCancelExpectation], timeout: 5) // one element has been emitted, we can cancel the task

        task.cancel()

        hasCancelExceptation.fulfill() // we can release the lock in the for loop

        wait(for: [taskHasFinishedExpectation], timeout: 5) // task has been cancelled and has finished
    }
}
