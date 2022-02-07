//
//  AsyncSequence+SwitchToLatestTests.swift
//  
//
//  Created by Thibault Wittemberg on 04/01/2022.
//

@testable import AsyncExtensions
import XCTest

private struct MockError: Error, Equatable {
    let code: Int
}

import Combine

private struct LongAsyncSequence<Element>: AsyncSequence, AsyncIteratorProtocol {
    typealias Element = Element
    typealias AsyncIterator = LongAsyncSequence
    
    var elements: IndexingIterator<[Element]>
    let interval: AsyncSequences.Interval
    var hasEmitted = false
    let onCancel: () -> Void
    
    init(elements: [Element], interval: AsyncSequences.Interval = .immediate, onCancel: @escaping () -> Void) {
        self.onCancel = onCancel
        self.elements = elements.makeIterator()
        self.interval = interval
    }
    
    mutating func next() async throws -> Element? {
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

final class AsyncSequence_SwitchToLatestTests: XCTestCase {
    func testSwitchToLatest_switches_to_latest_asyncSequence_and_cancels_previous_ones() async throws {
        var asyncSequence1IsCancelled = false
        var asyncSequence2IsCancelled = false
        var asyncSequence3IsCancelled = false

        let childAsyncSequence1 = LongAsyncSequence(elements: [1, 2, 3], interval: .milliSeconds(200), onCancel: { asyncSequence1IsCancelled = true })
            .prepend(0)
        let childAsyncSequence2 = LongAsyncSequence(elements: [5, 6, 7], interval: .milliSeconds(200), onCancel: { asyncSequence2IsCancelled = true })
            .prepend(4)
        let childAsyncSequence3 = LongAsyncSequence(elements: [9, 10, 11], interval: .milliSeconds(200), onCancel: { asyncSequence3IsCancelled = true })
            .prepend(8)

        let mainAsyncSequence = LongAsyncSequence(elements: [childAsyncSequence1, childAsyncSequence2, childAsyncSequence3],
                                                  interval: .milliSeconds(30),
                                                  onCancel: {})

        let sut = mainAsyncSequence.switchToLatest()

        var receivedElements = [Int]()
        let expectedElements = [0, 4, 8, 9, 10, 11]
        for try await element in sut {
            receivedElements.append(element)
        }

        XCTAssertEqual(receivedElements, expectedElements)
        XCTAssertTrue(asyncSequence1IsCancelled)
        XCTAssertTrue(asyncSequence2IsCancelled)
        XCTAssertFalse(asyncSequence3IsCancelled)
    }

    func testSwitchToLatest_propagates_errors() async {
        let expectedError = MockError(code: Int.random(in: 0...100))
        
        let sourceSequence = [
            LongAsyncSequence(elements: [1], onCancel: {}).eraseToAnyAsyncSequence(),
            AsyncSequences.Fail<Int>(error: expectedError).eraseToAnyAsyncSequence()].asyncElements
        
        let sut = sourceSequence.switchToLatest()
        
        do {
            for try await _ in sut {}
        } catch {
            XCTAssertEqual(error as? MockError, expectedError)
        }
    }
    
    func testSwitchToLatest_finishes_when_task_is_cancelled_after_switched() {
        let canCancelExpectation = expectation(description: "The first element has been emitted")
        let hasCancelExceptation = expectation(description: "The task has been cancelled")
        let taskHasFinishedExpectation = expectation(description: "The task has finished")

        let sourceSequence = [1, 2, 3].asyncElements
        let mappedSequence = sourceSequence.map { element in LongAsyncSequence(
            elements: [element],
            interval: .milliSeconds(50),
            onCancel: {}
        )}
        let sut = mappedSequence.switchToLatest()
        
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
}
