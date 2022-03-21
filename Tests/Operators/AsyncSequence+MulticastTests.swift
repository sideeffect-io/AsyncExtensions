//
//  AsyncSequence+MulticastTests.swift
//  
//
//  Created by Thibault Wittemberg on 21/02/2022.
//

import AsyncExtensions
import XCTest

private struct SpyAsyncSequenceForOnNextCall<Element>: AsyncSequence {
    typealias Element = Element
    typealias AsyncIterator = Iterator

    let onNext: () -> Void

    func makeAsyncIterator() -> AsyncIterator {
        Iterator(onNext: self.onNext)
    }

    struct Iterator: AsyncIteratorProtocol {
        let onNext: () -> Void

        func next() async throws -> Element? {
            self.onNext()
            try await Task.sleep(nanoseconds: 100_000_000_000)
            return nil
        }
    }
}

private class SpyAsyncSequenceForNumberOfIterators<Element>: AsyncSequence {
    typealias Element = Element
    typealias AsyncIterator = Iterator

    let element: Element
    let numberOfTimes: Int

    var numberOfIterators = 0

    init(element: Element, numberOfTimes: Int) {
        self.element = element
        self.numberOfTimes = numberOfTimes
    }

    func makeAsyncIterator() -> AsyncIterator {
        self.numberOfIterators += 1
        return Iterator(element: self.element, numberOfTimes: self.numberOfTimes)
    }

    struct Iterator: AsyncIteratorProtocol {
        let element: Element
        var numberOfTimes: Int

        mutating func next() async throws -> Element? {
            guard self.numberOfTimes > 0 else { return nil }
            self.numberOfTimes -= 1
            return element
        }
    }
}

private struct MockError: Error, Equatable {
    let code: Int
}

final class AsyncSequence_MulticastTests: XCTestCase {
    func test_multiple_loops_receive_elements_from_single_upstreamIterator() {
        let tasksHaveFinishedExpectation = expectation(description: "Tasks have finished")
        tasksHaveFinishedExpectation.expectedFulfillmentCount = 2

        let spyUpstreamSequence = SpyAsyncSequenceForNumberOfIterators(element: 1, numberOfTimes: 3)
        let stream = AsyncStreams.Passthrough<Int>()
        let sut = spyUpstreamSequence.multicast(stream)

        Task(priority: .high) {
            var receivedElement = [Int]()
            for try await element in sut {
                receivedElement.append(element)
            }
            XCTAssertEqual(receivedElement, [1, 1, 1])
            tasksHaveFinishedExpectation.fulfill()
        }

        Task(priority: .high) {
            var receivedElement = [Int]()
            for try await element in sut {
                receivedElement.append(element)
            }
            XCTAssertEqual(receivedElement, [1, 1, 1])
            tasksHaveFinishedExpectation.fulfill()
        }

        sut.connect()

        wait(for: [tasksHaveFinishedExpectation], timeout: 1)

        XCTAssertEqual(spyUpstreamSequence.numberOfIterators, 1)
    }

    func test_multiple_loops_uses_provided_stream() {
        let tasksHaveFinishedExpectation = expectation(description: "Tasks have finished")
        tasksHaveFinishedExpectation.expectedFulfillmentCount = 3

        let stream = AsyncStreams.Passthrough<Int>()
        let spyUpstreamSequence = SpyAsyncSequenceForNumberOfIterators(element: 1, numberOfTimes: 3)
        let sut = spyUpstreamSequence.multicast(stream)

        Task {
            var receivedElement = [Int]()
            try await stream.collect { receivedElement.append($0) }
            XCTAssertEqual(receivedElement, [1, 1, 1])
            tasksHaveFinishedExpectation.fulfill()
        }

        Task {
            var receivedElement = [Int]()
            for try await element in sut {
                receivedElement.append(element)
            }
            XCTAssertEqual(receivedElement, [1, 1, 1])
            tasksHaveFinishedExpectation.fulfill()
        }

        Task {
            var receivedElement = [Int]()
            for try await element in sut {
                receivedElement.append(element)
            }
            XCTAssertEqual(receivedElement, [1, 1, 1])
            tasksHaveFinishedExpectation.fulfill()
        }

        sut.connect()

        wait(for: [tasksHaveFinishedExpectation], timeout: 1)

        XCTAssertEqual(spyUpstreamSequence.numberOfIterators, 1)
    }

    func test_multicast_propagates_error_when_autoconnect() async {
        let expectedError = MockError(code: Int.random(in: 0...100))

        let stream = AsyncStreams.Passthrough<Int>()
        let sut = AsyncSequences.Fail<Int>(error: expectedError)
            .multicast(stream)
            .autoconnect()

        do {
            for try await element in sut {
                print(element)
            }
        } catch {
            XCTAssertEqual(error as? MockError, expectedError)
        }
    }

    func test_multicast_finishes_when_task_is_cancelled() {
        let taskHasFinishedExpectation = expectation(description: "Task has finished")

        let stream = AsyncStreams.Passthrough<Int>()
        let sut = AsyncSequences.From<[Int]>([1, 2, 3, 4, 5], interval: .seconds(100))
            .multicast(stream)
            .autoconnect()

        Task {
            for try await _ in sut {}
            taskHasFinishedExpectation.fulfill()
        }.cancel()

        wait(for: [taskHasFinishedExpectation], timeout: 1)
    }

    func test_multicast_finishes_when_task_is_cancelled_while_waiting_for_next() {
        let canCancelExpectation = expectation(description: "the task can be cancelled")
        let taskHasFinishedExpectation = expectation(description: "Task has finished")

        let spyAsyncSequence = SpyAsyncSequenceForOnNextCall<Int> {
            canCancelExpectation.fulfill()
        }

        let stream = AsyncStreams.Passthrough<Int>()
        let sut = spyAsyncSequence
            .multicast(stream)
            .autoconnect()

        let task = Task {
            for try await _ in sut {}
            taskHasFinishedExpectation.fulfill()
        }

        wait(for: [canCancelExpectation], timeout: 1)

        task.cancel()

        wait(for: [taskHasFinishedExpectation], timeout: 1)
    }
}
