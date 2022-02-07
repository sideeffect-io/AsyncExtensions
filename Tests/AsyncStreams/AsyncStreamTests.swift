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
    func testContinuations_register_adds_the_continuation() async{
        let continuationIsRegisteredExpectation = expectation(description: "Continuation is registered")

        let id = UUID()
        let sut = AsyncStreams.Continuations<String>()

        _ = AsyncThrowingStream(String.self, bufferingPolicy: .unbounded) { continuation in
            Task {
                await sut.register(continuation: continuation, forId: id)
                continuationIsRegisteredExpectation.fulfill()
            }
        }

        await waitForExpectations(timeout: 1)
        let continuations = await sut.continuations

        XCTAssertNotNil(continuations[id])
    }

    func testContinuations_send_yields_element_in_continuations() async{
        let continuationIsRegisteredExpectation = expectation(description: "Continuation is registered")

        let sut = AsyncStreams.Continuations<String>()

        let asyncStream = AsyncThrowingStream(String.self, bufferingPolicy: .unbounded) { continuation in
            Task {
                await sut.register(continuation: continuation, forId: UUID())
                continuationIsRegisteredExpectation.fulfill()
            }
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

        await sut.send("element")
        await sut.send(.finished)

        await waitForExpectations(timeout: 1)
    }

    func testContinuations_unregister_removes_the_continuation() async {
        let continuationIsRegisteredExpectation = expectation(description: "Continuation is registered")

        let id = UUID()
        let sut = AsyncStreams.Continuations<String>()

        _ = AsyncThrowingStream(String.self, bufferingPolicy: .unbounded) { continuation in
            Task {
                await sut.register(continuation: continuation, forId: id)
                continuationIsRegisteredExpectation.fulfill()
            }
        }

        await waitForExpectations(timeout: 1)

        let continuationsAfterRegister = await sut.continuations

        XCTAssertNotNil(continuationsAfterRegister[id])

        await sut.unregister(id: id)

        let continuationsAfterUnregister = await sut.continuations

        XCTAssertNil(continuationsAfterUnregister[id])
    }
}

// MARK: tests for AsyncStreams.Iterator
extension AsyncStreamTests {
    func testIterator_unregisters_continuation_when_cancelled() {
        let asyncStreamIsReadyToBeIteratedExpectation = expectation(description: "The AsyncStream can be iterated")
        let taskCanBeCancelledExpectation = expectation(description: "Task can be cancelled")
        let taskHasBeenCancelledExpectation = expectation(description: "Task has been cancelled")
        let continuationHasBeenUnregisteredContinuation = expectation(description: "Continuation has been unregistered")

        let clientId = UUID()
        let continuations = AsyncStreams.Continuations<Int>()

        let asyncStream = AsyncThrowingStream<Int, Error> { continuation in
            Task {
                (0...100).forEach { element in
                    continuation.yield(element)
                }
                await continuations.register(continuation: continuation, forId: clientId)
                asyncStreamIsReadyToBeIteratedExpectation.fulfill()
            }
        }

        wait(for: [asyncStreamIsReadyToBeIteratedExpectation], timeout: 1)

        let baseIterator = asyncStream.makeAsyncIterator()


        let task = Task {
            var sut = AsyncStreams.Iterator<Int>(
                clientId: clientId,
                baseIterator: baseIterator,
                continuations: continuations
            )

            let count = await continuations.continuations.count
            XCTAssertEqual(count, 1)

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

        wait(for: [taskHasBeenCancelledExpectation], timeout: 1)

        Task {
            let count = await continuations.continuations.count
            XCTAssertEqual(count, 0)
            continuationHasBeenUnregisteredContinuation.fulfill()
        }

        wait(for: [continuationHasBeenUnregisteredContinuation], timeout: 1)
    }

    func testIterator_unregisters_continuation_when_cancelled_with_cancellationError() {
        let asyncStreamIsReadyToBeIteratedExpectation = expectation(description: "The AsyncStream can be iterated")
        let taskHasBeenCancelledExpectation = expectation(description: "Task has been cancelled")
        let continuationHasBeenUnregisteredContinuation = expectation(description: "Continuation has been unregistered")

        let clientId = UUID()
        let continuations = AsyncStreams.Continuations<Int>()

        let asyncStream = AsyncThrowingStream<Int, Error> { continuation in
            Task {
                (0...100).forEach { element in
                    continuation.yield(element)
                }
                continuation.finish(throwing: CancellationError())
                await continuations.register(continuation: continuation, forId: clientId)
                asyncStreamIsReadyToBeIteratedExpectation.fulfill()
            }
        }

        wait(for: [asyncStreamIsReadyToBeIteratedExpectation], timeout: 1)

        let baseIterator = asyncStream.makeAsyncIterator()


        Task {
            var sut = AsyncStreams.Iterator<Int>(
                clientId: clientId,
                baseIterator: baseIterator,
                continuations: continuations
            )

            let count = await continuations.continuations.count
            XCTAssertEqual(count, 1)

            do {
                while let _ = try await sut.next() {}
            } catch is CancellationError {
                taskHasBeenCancelledExpectation.fulfill()
            } catch {}
        }

        wait(for: [taskHasBeenCancelledExpectation], timeout: 2)

        Task {
            let count = await continuations.continuations.count
            XCTAssertEqual(count, 0)
            continuationHasBeenUnregisteredContinuation.fulfill()
        }

        wait(for: [continuationHasBeenUnregisteredContinuation], timeout: 1)
    }

    func testIterator_unregisters_continuation_when_cancelled_before_iterating() {
        let asyncStreamIsReadyToBeIteratedExpectation = expectation(description: "The AsyncStream can be iterated")
        let taskHasBeenCancelledExpectation = expectation(description: "Task has been cancelled")
        let continuationHasBeenUnregisteredContinuation = expectation(description: "Continuation has been unregistered")

        let clientId = UUID()
        let continuations = AsyncStreams.Continuations<Int>()

        let asyncStream = AsyncThrowingStream<Int, Error> { continuation in
            Task {
                (0...100).forEach { element in
                    continuation.yield(element)
                }
                await continuations.register(continuation: continuation, forId: clientId)
                asyncStreamIsReadyToBeIteratedExpectation.fulfill()
            }
        }

        wait(for: [asyncStreamIsReadyToBeIteratedExpectation], timeout: 1)

        let baseIterator = asyncStream.makeAsyncIterator()

        Task {
            var sut = AsyncStreams.Iterator<Int>(
                clientId: clientId,
                baseIterator: baseIterator,
                continuations: continuations
            )

            let count = await continuations.continuations.count
            XCTAssertEqual(count, 1)

            try await withTaskCancellationHandler {
                while let _ = try await sut.next() {}
            } onCancel: {
                taskHasBeenCancelledExpectation.fulfill()
            }
        }.cancel()

        wait(for: [taskHasBeenCancelledExpectation], timeout: 1)

        Task {
            let count = await continuations.continuations.count
            XCTAssertEqual(count, 0)
            continuationHasBeenUnregisteredContinuation.fulfill()
        }

        wait(for: [continuationHasBeenUnregisteredContinuation], timeout: 1)
    }
}
