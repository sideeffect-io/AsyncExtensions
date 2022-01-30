//
//  AsyncSequences+Empty.swift
//  
//
//  Created by Thibault Wittemberg on 31/12/2021.
//

import Foundation

public extension AsyncSequences {
    /// `Empty` is an AsyncSequence that immediately finishes without emitting values.
    /// 
    /// ```
    /// let emptySequence = AsyncSequences.Empty<Int>()
    /// for try await element in emptySequence {
    ///     // will never be called
    /// }
    /// ```
    typealias Empty<Element> = AsyncEmptySequence<Element>
}

public struct AsyncEmptySequence<Element>: AsyncSequence {
    public typealias Element = Element
    public typealias AsyncIterator = Iterator

    public init() {}

    public func makeAsyncIterator() -> AsyncIterator {
        Iterator()
    }

    public struct Iterator: AsyncIteratorProtocol {
        public func next() async -> Element? {
            nil
        }
    }
}
