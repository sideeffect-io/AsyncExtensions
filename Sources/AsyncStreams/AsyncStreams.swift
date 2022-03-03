//
//  AsyncStreams.swift
//  
//
//  Created by Thibault Wittemberg on 08/01/2022.
//

import Foundation

public protocol Stream: AnyObject, AsyncSequence {
    func send(_ element: Element)
    func send(termination: Termination)
}

public enum AsyncStreams {}

extension AsyncStreams {
    // Continuations can be accessed in a concurrent context. It is up to the caller to ensure
    // the usage in a safe way (cf Passthrough, CurrrentValue and Replay)
    final class Continuations<Element> {
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

        func register(
            continuation: AsyncThrowingStream<Element, Error>.Continuation,
            forId id: AnyHashable
        ) {
            self.continuations[id] = continuation
        }

        func unregister(
            id: AnyHashable
        ) {
            self.continuations[id] = nil
        }
    }

    public struct Iterator<Element>: AsyncIteratorProtocol {
        public typealias Element = Element

        var baseIterator: AsyncThrowingStream<Element, Error>.Iterator
        let onCancelOrFinish: () -> Void

        public mutating func next() async throws -> Element? {
            guard !Task.isCancelled else {
                self.onCancelOrFinish()
                return nil
            }

            do {
                let next = try await self.baseIterator.next()
                if next == nil {
                    self.onCancelOrFinish()
                }
                return next
            } catch {
                self.onCancelOrFinish()
                throw error
            }
        }
    }
}
