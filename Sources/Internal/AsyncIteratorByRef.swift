//
//  AsyncIteratorByRef.swift
//  
//
//  Created by Thibault Wittemberg on 08/02/2022.
//

/// Allows to store an iterator and mutate it, when in a non mutating environment.
final class AsyncIteratorByRef<BaseAsyncIterator: AsyncIteratorProtocol>: AsyncIteratorProtocol {
    public typealias Element = BaseAsyncIterator.Element
    var iterator: BaseAsyncIterator?

    init(iterator: BaseAsyncIterator?) {
        self.iterator = iterator
    }

    public func next() async throws -> BaseAsyncIterator.Element? {
        guard !Task.isCancelled else { return nil }
        return try await self.iterator?.next()
    }
}
