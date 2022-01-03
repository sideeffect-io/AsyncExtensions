//
//  SharedAsyncIterator.swift
//  
//
//  Created by Thibault Wittemberg on 23/01/2022.
//

public final class SharedAsyncIterator<BaseAsyncIterator: AsyncIteratorProtocol>: AsyncIteratorProtocol {
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
