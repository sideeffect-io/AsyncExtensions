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

public final class AsyncCurrentValueStream<Element>: Stream, @unchecked Sendable {
    final class Storage {
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

    // we must make sure the inner continuations and storage can be used in a concurrent context since there can be multiple
    // operations happening at the same time (concurrent registrations and sendings).
    // we could use an Actor to enforce that BUT there is a drawback. If we use an Actor to handle Continuations,
    // when registering a new continuation, the register function would have to be called within a Task
    // because of its async nature. Doing so, it means that we could call `send` while the registration is not done and we
    // would loose the value.
    let serialQueue = DispatchQueue(label: UUID().uuidString)

    let continuations = AsyncStreams.Continuations<Element>()
    let storage: Storage

    public var element: Element {
        get {
            self.serialQueue.sync {
                self.storage.retrieve()
            }
        }

        set {
            self.send(newValue)
        }
    }

    public init(_ element: Element) {
        self.storage = Storage(element)
    }

    /// Sends a value to all underlying async sequences
    /// - Parameter element: the value to send
    public func send(_ element: Element) {
        self.serialQueue.async { [weak self] in
            self?.storage.update(element)
            self?.continuations.send(element)
        }
    }

    /// Finishes the async sequences with either a normal ending or an error.
    /// - Parameter termination: The termination to finish the async sequence.
    public func send(termination: Termination) {
        self.serialQueue.async { [weak self] in
            self?.continuations.send(termination)
        }
    }

    func makeStream(forClientId clientId: UUID) -> AsyncThrowingStream<Element, Error> {
        return AsyncThrowingStream<Element, Error>(Element.self, bufferingPolicy: .unbounded) { [weak self] continuation in
            self?.serialQueue.async { [weak self] in
                self?.continuations.register(continuation: continuation, forId: clientId)
                guard let element = self?.storage.retrieve() else { return }
                continuation.yield(element)
            }
        }
    }

    public func makeAsyncIterator() -> AsyncIterator {
        let clientId = UUID()
        let stream = self.makeStream(forClientId: clientId)
        return AsyncStreams.Iterator<Element>(
            baseIterator: stream.makeAsyncIterator(),
            onCancelOrFinish: { [weak self] in
                self?.serialQueue.async { [weak self] in
                    self?.continuations.unregister(id: clientId)
                }
            }
        )
    }
}
