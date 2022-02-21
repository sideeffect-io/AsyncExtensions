//
//  ConcurrentAccessRegulatorTests.swift
//  
//
//  Created by Thibault Wittemberg on 24/02/2022.
//

@testable import AsyncExtensions
import XCTest

private struct SpyAsyncSequence<Element>: AsyncSequence {
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

private struct MockError: Error, Equatable {
    let code: Int
}

final class ConcurrentAccessRegulatorTests: XCTestCase {}

// MARK: tests for NonBlockingGate
extension ConcurrentAccessRegulatorTests {
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

extension ConcurrentAccessRegulatorTests {
    func testRequestNextIfAvailable_calls_onCancel_when_task_is_cancelled() {
        let onCancelIsCalledExpectation = expectation(description: "onCancel has been called")

        let sut = ConcurrentAccessRegulator(
            AsyncSequences.Just(1),
            onNext: { _ in },
            onError: { _ in },
            onCancel: { onCancelIsCalledExpectation.fulfill() }
        )

        Task {
            await sut.requestNextIfAvailable()
        }.cancel()

        waitForExpectations(timeout: 1)
    }

    func testRequestNextIfAvailable_calls_onCancel_when_task_is_cancelled_while_waiting_for_next() {
        let canCancelExpectation = expectation(description: "the task can be cancelled")
        let onCancelIsCalledExpectation = expectation(description: "onCancel has been called")

        let spyAsyncSequence = SpyAsyncSequence<Int> {
            canCancelExpectation.fulfill()
        }

        let sut = ConcurrentAccessRegulator(spyAsyncSequence) { _ in
        } onError: { _ in
        } onCancel: {
            onCancelIsCalledExpectation.fulfill()
        }

        let task = Task {
            await sut.requestNextIfAvailable()
        }

        wait(for: [canCancelExpectation], timeout: 1)

        task.cancel()

        wait(for: [onCancelIsCalledExpectation], timeout: 1)
    }

    func testRequestNextIfAvailable_calls_onError_when_upstream_asyncSequence_fails() {
        let onErrorIsCalledExpectation = expectation(description: "onError has been called")

        var receivedError: MockError?
        let expectedError = MockError(code: Int.random(in: 0...100))

        let sut = ConcurrentAccessRegulator(AsyncSequences.Fail<Int>(error: expectedError)) { _ in
        } onError: { error in
            receivedError = error as? MockError
            onErrorIsCalledExpectation.fulfill()
        } onCancel: {
        }

        Task {
            await sut.requestNextIfAvailable()
        }

        wait(for: [onErrorIsCalledExpectation], timeout: 1)

        XCTAssertEqual(receivedError, expectedError)
    }

    func testRequestNextIfAvailable_calls_onNext_when_upstream_asyncSequence_returns_elements() {
        let onNextIsCalledExpectation = expectation(description: "onNext has been called")

        var receivedElement: Int?
        let expectedElement = Int.random(in: 0...100)

        let sut = ConcurrentAccessRegulator(AsyncSequences.Just<Int>(expectedElement)) { element in
            receivedElement = element
            onNextIsCalledExpectation.fulfill()
        } onError: { _ in
        } onCancel: {
        }

        Task {
            await sut.requestNextIfAvailable()
        }

        wait(for: [onNextIsCalledExpectation], timeout: 1)

        XCTAssertEqual(receivedElement, expectedElement)
    }
}
