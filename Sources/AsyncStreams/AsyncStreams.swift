//
//  AsyncStreams.swift
//  
//
//  Created by Thibault Wittemberg on 08/01/2022.
//

import Foundation

public protocol Stream {
    associatedtype Element

    func send(_ element: Element) async
    func send(termination: Termination) async
}

public enum AsyncStreams {}

extension AsyncStreams {
    final class Continuations<Element>: @unchecked Sendable {
        var continuations = [AnyHashable: AsyncThrowingStream<Element, Error>.Continuation]()
        let queue = DispatchQueue(label: UUID().uuidString)

        func register(continuation: AsyncThrowingStream<Element, Error>.Continuation, forId id: AnyHashable) {
            self.queue.sync {
                self.continuations[id] = continuation
            }
        }

        func send(_ element: Element) {
            self.queue.sync {
                self.continuations.values.forEach { $0.yield(element) }
            }
        }

        func send(_ termination: Termination) {
            self.queue.sync {
                switch termination {
                case .finished: self.continuations.values.forEach { $0.finish() }
                case let .failure(error): self.continuations.values.forEach { $0.finish(throwing: error) }
                }
                self.continuations.removeAll()
            }
        }

        func unregister(id: AnyHashable) {
            self.queue.sync {
                self.continuations[id] = nil
            }
        }
    }

    public struct Iterator<Element>: AsyncIteratorProtocol {
        public typealias Element = Element

        let clientId: UUID
        var baseIterator: AsyncThrowingStream<Element, Error>.Iterator
        let continuations: AsyncStreams.Continuations<Element>

        init(
            clientId: UUID,
            baseIterator: AsyncThrowingStream<Element, Error>.Iterator,
            continuations: AsyncStreams.Continuations<Element>
        ) {
            self.clientId = clientId
            self.baseIterator = baseIterator
            self.continuations = continuations
        }

        public mutating func next() async throws -> Element? {
            guard !Task.isCancelled else {
                self.continuations.unregister(id: self.clientId)
                return nil
            }

            let localContinuations = self.continuations
            let localClientId = self.clientId

            return try await withTaskCancellationHandler(operation: {
                try await self.baseIterator.next()
            }, onCancel: {
                localContinuations.unregister(id: localClientId)
            })
        }
    }
}
