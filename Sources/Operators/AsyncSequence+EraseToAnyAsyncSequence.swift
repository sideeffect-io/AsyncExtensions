//
//  AsyncSequence+EraseToAnyAsyncSequence.swift
//  
//
//  Created by Thibault Wittemberg on 31/12/2021.
//

public extension AsyncSequence {
    /// Type erase the AsyncSequence into an AnyAsyncSequence.
    /// - Returns: A type erased AsyncSequence.
    func eraseToAnyAsyncSequence() -> AnyAsyncSequence<Element> {
        AnyAsyncSequence(self)
    }
}

/// Type erased version of an AsyncSequence.
public struct AnyAsyncSequence<Element>: AsyncSequence {
    public typealias Element = Element
    public typealias AsyncIterator = Iterator

    private let makeAsyncIteratorClosure: () -> AsyncIterator

    public init<BaseAsyncSequence: AsyncSequence>(_ baseAsyncSequence: BaseAsyncSequence) where BaseAsyncSequence.Element == Element {
        self.makeAsyncIteratorClosure = { Iterator(baseIterator: baseAsyncSequence.makeAsyncIterator()) }
    }

    public func makeAsyncIterator() -> AsyncIterator {
        Iterator(baseIterator: self.makeAsyncIteratorClosure())
    }

    public struct Iterator: AsyncIteratorProtocol {
        private let nextClosure: () async throws -> Element?

        public init<BaseAsyncIterator: AsyncIteratorProtocol>(baseIterator: BaseAsyncIterator) where BaseAsyncIterator.Element == Element {
            var baseIterator = baseIterator
            self.nextClosure = { try await baseIterator.next() }
        }

        public func next() async throws -> Element? {
            try await self.nextClosure()
        }
    }
}
