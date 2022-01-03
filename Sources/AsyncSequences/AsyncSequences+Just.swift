//
//  AsyncSequences+Just.swift
//  
//
//  Created by Thibault Wittemberg on 04/01/2022.
//

public extension AsyncSequences {
    /// `Just` is an AsyncSequence that outputs a single value and finishes.
    /// If the parent task is cancelled while iterating then the iteration finishes before emitting the value.
    ///
    /// ```
    /// let justSequence = AsyncSequences.Just<Int>(1)
    /// for try await element in justSequence {
    ///     // will be called once with element = 1
    /// }
    /// ```
    typealias Just<Element> = AsyncJustSequence<Element>
}

public struct AsyncJustSequence<Element>: AsyncSequence {
    public typealias Element = Element
    public typealias AsyncIterator = Iterator

    var element: () async throws -> Element

    public init(_ element: Element) {
        self.element = { element }
    }

    public init(_ element: @escaping () async throws -> Element) {
        self.element = element
    }

    public func makeAsyncIterator() -> AsyncIterator {
        Iterator(element: self.element)
    }

    public struct Iterator: AsyncIteratorProtocol {
        var element: (() async throws -> Element)?

        public mutating func next() async throws -> Element? {
            guard !Task.isCancelled else { return nil }

            let elementToReturn: Element? = try await self.element?()
            self.element = nil
            return elementToReturn
        }
    }
}
