//
//  AsyncStreams+Passthrough.swift
//
//
//  Created by Thibault Wittemberg on 07/01/2022.
//

import Foundation

public extension AsyncStreams {
    /// A `Passthrough` is an async sequence in which one can send values over time.
    ///
    /// ```
    /// let passthrough = AsyncStreams.Passthrough<Int>()
    ///
    /// Task {
    ///     for try await element in passthrough {
    ///         print(element) // will print 1 2
    ///     }
    /// }
    ///
    /// Task {
    ///     for try await element in passthrough {
    ///         print(element) // will print 1 2
    ///     }
    /// }
    ///
    /// .. later in the application flow
    ///
    /// passthrough.send(1)
    /// passthrough.send(2)
    /// ```
    typealias Passthrough<Element> = AsyncPassthroughStream<Element>
}

public final class AsyncPassthroughStream<Element>: AsyncSequence, Stream, Sendable {
    public typealias AsyncIterator = AsyncStreams.Iterator<Element>

    let continuations = AsyncStreams.Continuations<Element>()

    public init() {}

    /// Sends a value to all underlying async sequences
    /// - Parameter element: the value to send
    public func send(_ element: Element) {
        self.continuations.send(element)
    }

    /// Finishes the async sequences with either a normal ending or an error.
    /// - Parameter termination: The termination to finish the async sequence.
    public func send(termination: Termination) {
        self.continuations.send(termination)
    }

    func makeStream(forClientId clientId: UUID) -> AsyncThrowingStream<Element, Error> {
        return AsyncThrowingStream<Element, Error>(Element.self, bufferingPolicy: .unbounded) { [continuations] continuation in
            continuations.register(continuation: continuation, forId: clientId)
        }
    }

    public func makeAsyncIterator() -> AsyncIterator {
        let clientId = UUID()
        let stream = self.makeStream(forClientId: clientId)
        return AsyncStreams.Iterator<Element>(
            clientId: clientId,
            baseIterator: stream.makeAsyncIterator(),
            continuations: self.continuations
        )
    }
}
