//
//  AsyncSequence+FlatMapLatestTests.swift
//
//
//  Created by Thibault Wittemberg on 10/01/2022.
//

@testable import AsyncExtensions
import XCTest

private actor Spy {
    var elements = [Int]()

    func register(_ element: Int) {
        self.elements.append(element)
    }

    func assertElementsEqual(_ elements: [Int]) {
        XCTAssertEqual(self.elements, elements)
    }
}

private struct MockError: Error, Equatable {
    let code: Int
}

private struct LongAsyncSequence: AsyncSequence, AsyncIteratorProtocol {
    typealias Element = Int
    typealias AsyncIterator = LongAsyncSequence

    var elements: IndexingIterator<[Element]>
    let interval: AsyncSequences.Interval
    let onCancel: () -> Void

    init(elements: [Element], interval: AsyncSequences.Interval = .immediate, onCancel: @escaping () -> Void) {
        self.onCancel = onCancel
        self.elements = elements.makeIterator()
        self.interval = interval
    }

    mutating func next() async throws -> Element? {
        guard !Task.isCancelled else {
            self.onCancel()
            return nil
        }

        let onCancel = self.onCancel

        return try await withTaskCancellationHandler {
            try await Task.sleep(nanoseconds: self.interval.value)
            return self.elements.next()
        } onCancel: {
            onCancel()
        }
    }

    func makeAsyncIterator() -> AsyncIterator {
        self
    }
}

final class AsyncSequence_FlatMapLatestTests: XCTestCase {
    func testFlatMapLatest_switches_to_latest_asyncSequence_and_cancels_previous_ones() {
        let firstChildSequenceHasEmittedTwoElementsExpectation = expectation(description: "The first child sequence has emitted two elements")
        let secondChildSequenceHasEmittedOneElementsExpectation = expectation(description: "The second child sequence has emitted one element")
        let thirdChildSequenceHasEmittedTwoElementsExpectation = expectation(description: "The third child sequence has emitted two elements")

        let firstChildSequenceIsCancelled = expectation(description: "First child sequence has been cancelled")
        let secondChildSequenceIsCancelled = expectation(description: "Second child sequence has been cancelled")

        let baseSequence = AsyncStreams.CurrentValue<Int>(1)

        let sut = baseSequence.flatMapLatest { element -> AnyAsyncSequence<Int> in
            let childElement1 = (element * 10) + 1
            let childElement2 = (element * 10) + 2
            let childElement3 = (element * 10) + 3

            return AsyncSequences
                .From([childElement1, childElement2, childElement3], interval: .milliSeconds(100))
                .eraseToAnyAsyncSequence()
        }

        Task {
            var receivedElements = [Int]()
            for try await element in sut {
                receivedElements.append(element)

                if element == 12 {
                    firstChildSequenceHasEmittedTwoElementsExpectation.fulfill()
                    wait(for: [firstChildSequenceIsCancelled], timeout: 1)
                }

                if element == 21 {
                    secondChildSequenceHasEmittedOneElementsExpectation.fulfill()
                    wait(for: [secondChildSequenceIsCancelled], timeout: 1)
                }

                if element == 32 {
                    XCTAssertEqual(receivedElements, [11, 12, 21, 31, 32])
                    thirdChildSequenceHasEmittedTwoElementsExpectation.fulfill()
                }
            }
        }

        wait(for: [firstChildSequenceHasEmittedTwoElementsExpectation], timeout: 1)

        baseSequence.send(2)
        firstChildSequenceIsCancelled.fulfill()

        wait(for: [secondChildSequenceHasEmittedOneElementsExpectation], timeout: 1)

        baseSequence.send(3)
        secondChildSequenceIsCancelled.fulfill()

        wait(for: [thirdChildSequenceHasEmittedTwoElementsExpectation], timeout: 1)
    }

    func testFlatMapLatest_propagates_errors_when_transform_function_fails() async {
        let expectedError = MockError(code: Int.random(in: 0...100))

        let sut = [1, 2]
            .asyncElements
            .flatMapLatest { element throws -> AnyAsyncSequence<Int> in
                throw expectedError
            }

        do {
            for try await _ in sut {}
        } catch {
            XCTAssertEqual(error as? MockError, expectedError)
        }
    }

    func testFlatMapLatest_propagates_errors() async {
        let expectedError = MockError(code: Int.random(in: 0...100))

        let sut = AsyncSequences.From([1, 2])
            .flatMapLatest { element -> AnyAsyncSequence<Int> in
                if element == 1 {
                    return AsyncSequences.From([1], interval: .milliSeconds(100)).eraseToAnyAsyncSequence()
                }

                return AsyncSequences.Fail<Int>(error: expectedError).eraseToAnyAsyncSequence()
            }
            .eraseToAnyAsyncSequence()

        do {
            for try await _ in sut {}
        } catch {
            XCTAssertEqual(error as? MockError, expectedError)
        }
    }
    
    func testFlatMapLatest_finishes_when_task_is_cancelled_after_switched() {
        let canCancelExpectation = expectation(description: "The first element has been emitted")
        let hasCancelExceptation = expectation(description: "The task has been cancelled")
        let taskHasFinishedExpectation = expectation(description: "The task has finished")

        let sut = [1, 2, 3]
            .asyncElements
            .flatMapLatest { element in
                LongAsyncSequence(elements: [element], interval: .milliSeconds(50), onCancel: {} )
            }

        let task = Task {
            var firstElement: Int?
            for try await element in sut {
                firstElement = element
                canCancelExpectation.fulfill()
                wait(for: [hasCancelExceptation], timeout: 5)
            }
            XCTAssertEqual(firstElement, 3)
            taskHasFinishedExpectation.fulfill()
        }

        wait(for: [canCancelExpectation], timeout: 5) // one element has been emitted, we can cancel the task

        task.cancel()

        hasCancelExceptation.fulfill() // we can release the lock in the for loop

        wait(for: [taskHasFinishedExpectation], timeout: 5) // task has been cancelled and has finished
    }

    func testFlatMapLatest_switches_to_latest_element() async throws {
        var receivedElement = [String]()

        let sut = [1, 2, 3]
            .asyncElements
            .flatMapLatest { element -> String in
                try await Task.sleep(nanoseconds: 50_000_000)
                return "a\(element)"
            }

        for try await element in sut {
            receivedElement.append(element)
        }

        XCTAssertEqual(receivedElement, ["a3"])
    }
}
