//
//  SharedAsyncIteratorTests.swift
//  
//
//  Created by Thibault Wittemberg on 08/02/2022.
//

@testable import AsyncExtensions
import XCTest

private actor Spy<Element> {
    var storage = [Element]()

    func record(_ element: Element) {
        self.storage.append(element)
    }
}

final class SharedAsyncIteratorTests: XCTestCase {}

// MARK: tests for NonBlockingGate
extension SharedAsyncIteratorTests {
    func testNonBlockingGate_inits_isLockable_to_true() async {
        let sut = NonBlockingGate()
        let isLockable = await sut.isLockable
        XCTAssertTrue(isLockable)
    }

    func testNonBlockingGate_lock_sets_isLockable_to_false_and_returns_true() async {
        let sut = NonBlockingGate()
        let wasLockable = await sut.lock()
        let isLockable = await sut.isLockable
        XCTAssertTrue(wasLockable)
        XCTAssertFalse(isLockable)
    }

    func testNonBlockingGate_unlock_sets_isLockable_to_true() async {
        let sut = NonBlockingGate()
        _ = await sut.lock()
        let isLockableBefore = await sut.isLockable
        XCTAssertFalse(isLockableBefore)
        _ = await sut.unlock()
        let isLockableAfter = await sut.isLockable
        XCTAssertTrue(isLockableAfter)
    }
}

// MARK: tests for FinishState
extension SharedAsyncIteratorTests {
    func testFinishState_inits_finished_to_false() async {
        let sut = FinishState()
        let isFinished = await sut.finished
        XCTAssertFalse(isFinished)
    }

    func testFinishState_setFinished_sets_finished_to_true() async {
        let sut = FinishState()
        await sut.setFinished()
        let isFinished = await sut.finished
        XCTAssertTrue(isFinished)
    }

    func testFinishState_isFinished_gets_finished() async {
        let sut = FinishState()
        let isFinishedA = await sut.isFinished()
        let isFinishedB = await sut.finished
        XCTAssertEqual(isFinishedA, isFinishedB)
    }
}

// MARK: tests for SharedAsyncIterator
extension SharedAsyncIteratorTests {
    func testSharedAsyncIterator_returns_notAvailable_when_already_processing_next() async {
        let tasksHaveRecordedTheIteratorNextElementExpectation = expectation(description: "Tasks have received an element from shared iterator")
        tasksHaveRecordedTheIteratorNextElementExpectation.expectedFulfillmentCount = 2

        let asyncSequence = AsyncSequences.From([1], interval: .milliSeconds(500))
        let spy = Spy<SharedElement<Int>>()

        let sut = SharedAsyncIterator(iterator: asyncSequence.makeAsyncIterator())

        Task {
            let next = try await sut.next()
            await spy.record(next!)
            tasksHaveRecordedTheIteratorNextElementExpectation.fulfill()
        }

        Task {
            let next = try await sut.next()
            await spy.record(next!)
            tasksHaveRecordedTheIteratorNextElementExpectation.fulfill()
        }

        await waitForExpectations(timeout: 1)

        let recorded = await spy.storage
        XCTAssertEqual(recorded.count, 2)

        if case .notAvailable = recorded[0] {
            XCTAssertEqual(recorded[1], .value(1))
        }

        if case .notAvailable = recorded[1] {
            XCTAssertEqual(recorded[0], .value(1))
        }
    }

    func testSharedAsyncIterator_propagates_finish() async throws {
        let asyncSequence = AsyncSequences.Empty<Int>()
        let sut = SharedAsyncIterator(iterator: asyncSequence.makeAsyncIterator())

        _ = try await sut.next()
        let isFinishedA = await sut.isFinished()
        XCTAssertTrue(isFinishedA)

        _ = try await sut.next()
        let isFinishedB = await sut.isFinished()
        XCTAssertTrue(isFinishedB)
    }

    func testSharedAsyncIterator_unlocks_gate_when_next_element() async throws {
        let asyncSequence = AsyncSequences.Empty<Int>()
        let sut = SharedAsyncIterator(iterator: asyncSequence.makeAsyncIterator())

        _ = try await sut.next()
        let isLockable = await sut.gate.isLockable
        XCTAssertTrue(isLockable)
    }

    func testSharedAsyncIterator_finishes_when_task_is_cancelled() {
        let canCancelExpectation = expectation(description: "The first element has been emitted")
        let hasCancelExceptation = expectation(description: "The task has been cancelled")
        let taskHasFinishedExpectation = expectation(description: "The task has finished")

        let asyncSequence = AsyncSequences.From([1, 2])
        let sut = SharedAsyncIterator(iterator: asyncSequence.makeAsyncIterator())

        let task = Task {
            var firstElement: SharedElement<Int>?
            while let element = try await sut.next() {
                firstElement = element
                canCancelExpectation.fulfill()
                wait(for: [hasCancelExceptation], timeout: 5)
            }
            XCTAssertEqual(firstElement, .value(1))
            taskHasFinishedExpectation.fulfill()
        }

        wait(for: [canCancelExpectation], timeout: 5) // one element has been emitted, we can cancel the task

        task.cancel()

        hasCancelExceptation.fulfill() // we can release the lock in the for loop

        wait(for: [taskHasFinishedExpectation], timeout: 5) // task has been cancelled and has finished
    }
}
