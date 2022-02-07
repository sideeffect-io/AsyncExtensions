//
//  AsyncStreams.swift
//  
//
//  Created by Thibault Wittemberg on 08/01/2022.
//

import Foundation

public protocol Stream: AnyObject, AsyncSequence {
    func send(_ element: Element) async
    func send(termination: Termination) async
}

public extension Stream {
    func nonBlockingSend(_ element: Element) {
        Task { [weak self] in
            await self?.send(element)
        }
    }

    func nonBlockingSend(termination: Termination) {
        Task { [weak self] in
            await self?.send(termination: termination)
        }
    }
}

public enum AsyncStreams {}

extension AsyncStreams {
    actor Continuations<Element> {
        var continuations = [AnyHashable: AsyncThrowingStream<Element, Error>.Continuation]()

        func send(_ element: Element) {
            self.continuations.values.forEach { $0.yield(element) }
        }

        func send(_ termination: Termination) {
            switch termination {
            case .finished: self.continuations.values.forEach { $0.finish() }
            case let .failure(error): self.continuations.values.forEach { $0.finish(throwing: error) }
            }
            self.continuations.removeAll()
        }

        func register(continuation: AsyncThrowingStream<Element, Error>.Continuation, forId id: AnyHashable) {
            self.continuations[id] = continuation
        }

        func unregister(id: AnyHashable) {
            self.continuations[id] = nil
        }
    }

    public struct Iterator<Element>: AsyncIteratorProtocol {
        public typealias Element = Element

        var baseIterator: AsyncThrowingStream<Element, Error>.Iterator
        let unregisterBlock: () async -> Void

        init(
            clientId: UUID,
            baseIterator: AsyncThrowingStream<Element, Error>.Iterator,
            continuations: AsyncStreams.Continuations<Element>
        ) {
            self.baseIterator = baseIterator
            self.unregisterBlock = { await continuations.unregister(id: clientId) }
        }

        public mutating func next() async throws -> Element? {
            guard !Task.isCancelled else {
                await self.unregisterBlock()
                return nil
            }

            do {
                let next = try await self.baseIterator.next()
                if next == nil {
                    await self.unregisterBlock()
                }
                return next
            } catch {
                await self.unregisterBlock()
                throw error
            }
        }
    }
}
