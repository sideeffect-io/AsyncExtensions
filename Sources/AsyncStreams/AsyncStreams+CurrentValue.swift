//
//  AsyncStreams+CurrentValue.swift
//  
//
//  Created by Thibault Wittemberg on 07/01/2022.
//

import Foundation

public extension AsyncStreams {
    /// A `CurrentValue` is an async sequence in which one can send values over time.
    /// The current value is always accessible as an instance variable.
    /// The current value is replayed in any new async for in loops.
    ///
    /// ```
    /// let currentValue = AsyncStreams.CurrentValue<Int>(1)
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
    /// await currentValue.send(2)
    ///
    /// print(currentValue.element) // will print 2
    /// ```
    typealias CurrentValue<Element> = AsyncCurrentValueStream<Element>
}

public final class AsyncCurrentValueStream<Element>: Stream, Sendable {
    actor Storage {
        var element: Element

        init(_ element: Element) {
            self.element = element
        }

        func update(_ element: Element) {
            self.element = element
        }

        func retrieve() -> Element {
            self.element
        }
    }

    public typealias AsyncIterator = AsyncStreams.Iterator<Element>
    let continuations = AsyncStreams.Continuations<Element>()
    let storage: Storage

    public var element: Element {
        get async {
            await self.storage.retrieve()
        }
    }

    public init(_ element: Element) {
        self.storage = Storage(element)
    }

    /// Sends a value to all underlying async sequences
    /// - Parameter element: the value to send
    public func send(_ element: Element) async {
        await self.storage.update(element)
        await self.continuations.send(element)
    }

    /// Finishes the async sequences with either a normal ending or an error.
    /// - Parameter termination: The termination to finish the async sequence.
    public func send(termination: Termination) async {
        await self.continuations.send(termination)
    }

    func makeStream(forClientId clientId: UUID) -> AsyncThrowingStream<Element, Error> {
        return AsyncThrowingStream<Element, Error>(Element.self, bufferingPolicy: .unbounded) { [continuations, storage] continuation in
            Task {
                // registration is async because the continuations are managed by an actor (to avoid race conditions on its internal storage).
                // registering a continuation is possible only when the actor is available.
                let element = await storage.retrieve()
                continuation.yield(element)
                await continuations.register(continuation: continuation, forId: clientId)
            }
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
