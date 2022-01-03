//
//  SharedAsyncIteratorTests.swift
//  
//
//  Created by Thibault Wittemberg on 23/01/2022.
//

@testable import AsyncExtensions
import XCTest

private struct MockError: Error, Equatable {
    let code: Int
}

final class SharedAsyncIteratorTests: XCTestCase {
    func testSharedAsyncIterator_forwards_elements_from_input_iterator() async throws {
        let baseSequence = [1, 2, 3].asyncElements
        let sut = SharedAsyncIterator(iterator: baseSequence.makeAsyncIterator())

        var receivedElements = [Int]()
        while let element = try await sut.next() {
            receivedElements.append(element)
        }
        XCTAssertEqual(receivedElements, [1, 2, 3])
    }

    func testSharedAsyncIterator_forwards_errors_from_input_iterator() async throws {
        let mockError = MockError(code: Int.random(in: 0...100))

        let baseSequence = AsyncSequences.Fail<Int>(error: mockError)
        let sut = SharedAsyncIterator(iterator: baseSequence.makeAsyncIterator())

        do {
            while let _ = try await sut.next() {}
        } catch {
            XCTAssertEqual(error as? MockError, mockError)
        }
    }

    func testSharedAsyncIterator_finishes_when_task_is_cancelled() {
        let canCancelExpectation = expectation(description: "The first element has been emitted")
        let hasCancelExceptation = expectation(description: "The task has been cancelled")
        let taskHasFinishedExpectation = expectation(description: "The task has finished")

        let baseSequence = [1, 2, 3, 4, 5].asyncElements
        let sut = SharedAsyncIterator(iterator: baseSequence.makeAsyncIterator())

        let task = Task {
            var firstElement: Int?
            while let element = try await sut.next() {
                firstElement = element
                canCancelExpectation.fulfill()
                wait(for: [hasCancelExceptation], timeout: 5)
            }
            XCTAssertEqual(firstElement, 1)
            taskHasFinishedExpectation.fulfill()
        }

        wait(for: [canCancelExpectation], timeout: 5) // one element has been emitted, we can cancel the task

        task.cancel()

        hasCancelExceptation.fulfill() // we can release the lock in the for loop

        wait(for: [taskHasFinishedExpectation], timeout: 5) // task has been cancelled and has finished
    }
}
