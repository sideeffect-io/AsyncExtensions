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

        wait(for: [continuationIsRegisteredExpectation], timeout: 1)
        let continuations = sut.continuations

        XCTAssertNotNil(continuations[id])
    }

    func testContinuations_send_yields_element_in_continuations() {
        let continuationIsRegisteredExpectation = expectation(description: "Continuation is registered")
        let elementIsReceivedExpectation = expectation(description: "Element is received")

        let sut = AsyncStreams.Continuations<String>()

        let asyncStream = AsyncThrowingStream(String.self, bufferingPolicy: .unbounded) { continuation in
            sut.register(continuation: continuation, forId: UUID())
            continuationIsRegisteredExpectation.fulfill()
        }

        wait(for: [continuationIsRegisteredExpectation], timeout: 1)

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

        wait(for: [elementIsReceivedExpectation], timeout: 1)
    }

    func testContinuations_unregister_removes_the_continuation() {
        let continuationIsRegisteredExpectation = expectation(description: "Continuation is registered")

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

        let continuationsAfterUnregister = sut.continuations

        XCTAssertNil(continuationsAfterUnregister[id])
    }
}

// MARK: tests for AsyncStreams.Iterator
extension AsyncStreamTests {
    func testIterator_unregisters_continuation_when_cancelled() {
        let asyncStreamIsReadyToBeIteratedExpectation = expectation(description: "The AsyncStream can be iterated")
        let taskCanBeCancelledExpectation = expectation(description: "The iterator task can be cancelled")
        let taskHasBeenCancelledExpectation = expectation(description: "The iterator task has been cancelled")

        let clientId = UUID()
        let continuations = AsyncStreams.Continuations<Int>()

        let asyncStream = AsyncThrowingStream<Int, Error> { continuation in
            continuations.register(continuation: continuation, forId: clientId)
            asyncStreamIsReadyToBeIteratedExpectation.fulfill()
            (0...1000).forEach { element in
                continuation.yield(element)
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

            let count = continuations.continuations.count
            XCTAssertEqual(count, 1)

            try await withTaskCancellationHandler {
                while let element = try await sut.next() {
                    if element == 500 {
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

        let count = continuations.continuations.count

        XCTAssertEqual(count, 0)
    }
}
