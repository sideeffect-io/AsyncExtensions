//
//  AsyncStreamTests.swift
//  
//
//  Created by Thibault Wittemberg on 16/01/2022.
//

@testable import AsyncExtensions
import XCTest

// MARK: tests for AsyncStreams.Continuations
final class AsyncStreamTests: XCTestCase {
    func testContinuations_register_adds_the_continuation() {
        let continuationIsRegisteredExpectation = expectation(description: "Continuation is registered")

        let id = UUID()
        let sut = AsyncStreams.Continuations<String>()

        _ = AsyncThrowingStream(String.self, bufferingPolicy: .unbounded) { continuation in
            sut.register(continuation: continuation, forId: id)
            continuationIsRegisteredExpectation.fulfill()
        }

        waitForExpectations(timeout: 1)

        let continuations = sut.continuations

        XCTAssertNotNil(continuations[id])
    }

    func testContinuations_send_yields_element_in_continuations() async {
        let continuationIsRegisteredExpectation = expectation(description: "Continuation is registered")

        let sut = AsyncStreams.Continuations<String>()

        let asyncStream = AsyncThrowingStream(String.self, bufferingPolicy: .unbounded) { continuation in
            sut.register(continuation: continuation, forId: UUID())
            continuationIsRegisteredExpectation.fulfill()
        }

        await waitForExpectations(timeout: 1)

        let elementIsReceivedExpectation = expectation(description: "Element is received")

        Task {
            var receivedElements = [String]()

            for try await element in asyncStream {
                receivedElements.append(element)
            }
            XCTAssertEqual(receivedElements, ["element"])
            elementIsReceivedExpectation.fulfill()
        }

        sut.send("element")
        sut.send(.finished)

        await waitForExpectations(timeout: 1)
    }

    func testContinuations_unregister_removes_the_continuation() {
        let continuationIsRegisteredExpectation = expectation(description: "Continuation is registered")
        let continuationIsUnregisteredExpectation = expectation(description: "Continuation is unregistered")

        let id = UUID()
        let sut = AsyncStreams.Continuations<String>()

        _ = AsyncThrowingStream(String.self, bufferingPolicy: .unbounded) { continuation in
            sut.register(continuation: continuation, forId: id)
            continuationIsRegisteredExpectation.fulfill()
        }

        wait(for: [continuationIsRegisteredExpectation], timeout: 1)

        let continuationsAfterRegister = sut.continuations

        XCTAssertNotNil(continuationsAfterRegister[id])

        sut.unregister(id: id)
        continuationIsUnregisteredExpectation.fulfill()

        wait(for: [continuationIsUnregisteredExpectation], timeout: 1)

        let continuationsAfterUnregister = sut.continuations

        XCTAssertNil(continuationsAfterUnregister[id])
    }
}

// MARK: tests for AsyncStreams.Iterator
extension AsyncStreamTests {
    func testIterator_calls_onCancelOrFinish_when_finished() {
        let asyncStreamIsReadyToBeIteratedExpectation = expectation(description: "The AsyncStream can be iterated")
        let onCancelOrFinishHasBeenCalled = expectation(description: "onCancelOrFinish has been called")

        let clientId = UUID()
        let continuations = AsyncStreams.Continuations<Int>()

        let asyncStream = AsyncThrowingStream<Int, Error> { continuation in
            continuations.register(continuation: continuation, forId: clientId)
            continuation.finish(throwing: nil)
            asyncStreamIsReadyToBeIteratedExpectation.fulfill()
        }

        wait(for: [asyncStreamIsReadyToBeIteratedExpectation], timeout: 1)

        let baseIterator = asyncStream.makeAsyncIterator()

        Task {
            var sut = AsyncStreams.Iterator<Int>(
                baseIterator: baseIterator,
                onCancelOrFinish: {
                    onCancelOrFinishHasBeenCalled.fulfill()
                }
            )

            while let _ = try await sut.next() {}
        }

        wait(for: [onCancelOrFinishHasBeenCalled], timeout: 1)
    }

    func testIterator_calls_onCancelOrFinish_when_cancelled() {
        let asyncStreamIsReadyToBeIteratedExpectation = expectation(description: "The AsyncStream can be iterated")
        let taskCanBeCancelledExpectation = expectation(description: "Task can be cancelled")
        let taskHasBeenCancelledExpectation = expectation(description: "Task has been cancelled")
        let onCancelOrFinishHasBeenCalled = expectation(description: "onCancelOrFinish has been called")

        let clientId = UUID()
        let continuations = AsyncStreams.Continuations<Int>()

        let asyncStream = AsyncThrowingStream<Int, Error> { continuation in
            (0...100).forEach { element in
                continuation.yield(element)
            }
            continuations.register(continuation: continuation, forId: clientId)
            asyncStreamIsReadyToBeIteratedExpectation.fulfill()
        }

        wait(for: [asyncStreamIsReadyToBeIteratedExpectation], timeout: 1)

        let baseIterator = asyncStream.makeAsyncIterator()

        let task = Task {
            var sut = AsyncStreams.Iterator<Int>(
                baseIterator: baseIterator,
                onCancelOrFinish: {
                    onCancelOrFinishHasBeenCalled.fulfill()
                }
            )

            try await withTaskCancellationHandler {
                while let element = try await sut.next() {
                    if element == 50 {
                        taskCanBeCancelledExpectation.fulfill()
                    }
                }
            } onCancel: {
                taskHasBeenCancelledExpectation.fulfill()
            }
        }

        wait(for: [taskCanBeCancelledExpectation], timeout: 1)

        task.cancel()

        wait(for: [taskHasBeenCancelledExpectation, onCancelOrFinishHasBeenCalled], timeout: 1)
    }

    func testIterator_calls_onCancelOrFinish_when_cancelled_with_cancellationError() {
        let asyncStreamIsReadyToBeIteratedExpectation = expectation(description: "The AsyncStream can be iterated")
        let taskHasBeenCancelledExpectation = expectation(description: "Task has been cancelled")
        let onCancelOrFinishHasBeenCalled = expectation(description: "onCancelOrFinish has been called")

        let clientId = UUID()
        let continuations = AsyncStreams.Continuations<Int>()

        let asyncStream = AsyncThrowingStream<Int, Error> { continuation in
            (0...100).forEach { element in
                continuation.yield(element)
            }
            continuation.finish(throwing: CancellationError())
            continuations.register(continuation: continuation, forId: clientId)
            asyncStreamIsReadyToBeIteratedExpectation.fulfill()
        }

        wait(for: [asyncStreamIsReadyToBeIteratedExpectation], timeout: 1)

        let baseIterator = asyncStream.makeAsyncIterator()


        Task {
            var sut = AsyncStreams.Iterator<Int>(
                baseIterator: baseIterator,
                onCancelOrFinish: {
                    onCancelOrFinishHasBeenCalled.fulfill()
                }
            )

            do {
                while let _ = try await sut.next() {}
            } catch is CancellationError {
                taskHasBeenCancelledExpectation.fulfill()
            } catch {}
        }

        wait(for: [taskHasBeenCancelledExpectation, onCancelOrFinishHasBeenCalled], timeout: 2)
    }

    func testIterator_calls_onCancelOrFinish_when_cancelled_before_iterating() {
        let asyncStreamIsReadyToBeIteratedExpectation = expectation(description: "The AsyncStream can be iterated")
        let taskHasBeenCancelledExpectation = expectation(description: "Task has been cancelled")
        let onCancelOrFinishHasBeenCalled = expectation(description: "onCancelOrFinish has been called")

        let clientId = UUID()
        let continuations = AsyncStreams.Continuations<Int>()

        let asyncStream = AsyncThrowingStream<Int, Error> { continuation in
            (0...100).forEach { element in
                continuation.yield(element)
            }
            continuations.register(continuation: continuation, forId: clientId)
            asyncStreamIsReadyToBeIteratedExpectation.fulfill()
        }

        wait(for: [asyncStreamIsReadyToBeIteratedExpectation], timeout: 1)

        let baseIterator = asyncStream.makeAsyncIterator()

        Task {
            var sut = AsyncStreams.Iterator<Int>(
                baseIterator: baseIterator,
                onCancelOrFinish: {
                    onCancelOrFinishHasBeenCalled.fulfill()
                }
            )

            let count = continuations.continuations.count
            XCTAssertEqual(count, 1)

            try await withTaskCancellationHandler {
                while let _ = try await sut.next() {}
            } onCancel: {
                taskHasBeenCancelledExpectation.fulfill()
            }
        }.cancel()

        wait(for: [taskHasBeenCancelledExpectation, onCancelOrFinishHasBeenCalled], timeout: 1)
    }
}
