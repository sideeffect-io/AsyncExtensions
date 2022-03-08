//
//  AsyncStreams+Replay.swift
//  
//
//  Created by Thibault Wittemberg on 31/12/2021.
//

import Foundation

public extension AsyncStreams {
    /// A `Replay`is an async sequence in which one can send values over time.
    /// Values are buffered in a FIFO fashion so they can be iterated over by new loops.
    /// When the `bufferSize` is outreached the oldest value is dropped.
    ///
    /// ```
    /// let replay = AsyncStreams.Replay<Int>(bufferSize: 3)
    ///
    /// for i in (1...5) { await replay.send(i) }
    ///
    /// for try await element in replay {
    ///     print(element) // will print 3, 4, 5
    /// }
    /// ```
    typealias Replay<Element> = AsyncReplayStream<Element>
}

public final class AsyncReplayStream<Element>: Stream, @unchecked Sendable {
    final class Storage {
        var buffer = ContiguousArray<Element>()
        let bufferSize: Int

        var elements: ContiguousArray<Element> {
            return self.buffer
        }

        var size: Int {
            return self.bufferSize
        }

        init(bufferSize: Int) {
            precondition(bufferSize >= 0, "The bufferSize cannot be negative.")
            self.bufferSize = bufferSize
        }

        func push(_ element: Element) {
            self.buffer.append(element)
            if self.buffer.count > self.bufferSize {
                self.buffer.removeFirst()
            }
        }

        func clear() {
            self.buffer.removeAll()
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

    /// Creates a `Replay` buffering values in a buffer with  a positive `bufferSize`
    /// - Parameter bufferSize: The maximum number of replayable values to store in the buffer
    public init(bufferSize: Int) {
        self.storage = Storage(bufferSize: bufferSize)
    }

    /// Sends a value to all underlying async sequences
    /// - Parameter element: the value to send
    public func send(_ element: Element) {
        self.serialQueue.sync { [weak self] in
            self?.storage.push(element)
            self?.continuations.send(element)
        }
    }

    /// Finishes the async sequences with either a normal ending or an error.
    /// - Parameter completion: The termination to finish the async sequence.
    public func send(termination: Termination) {
        self.serialQueue.sync { [weak self] in
            self?.continuations.send(termination)
            self?.storage.clear()
        }
    }

    func makeStream(forClientId clientId: UUID) -> AsyncThrowingStream<Element, Error> {
        return AsyncThrowingStream<Element, Error>(Element.self, bufferingPolicy: .unbounded) { [weak self] continuation in
            self?.serialQueue.async { [weak self] in
                self?.continuations.register(continuation: continuation, forId: clientId)
                self?.storage.elements.forEach { continuation.yield($0) }
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
