//
//  AsyncSequence+Prepend.swift
//  
//
//  Created by Thibault Wittemberg on 31/12/2021.
//

public extension AsyncSequence {
    /// Prepends an element to the upstream async sequence.
    ///
    /// ```
    /// let sourceSequence = AsyncSequences.From([1, 2, 3])
    /// let prependSequence = sourceSequence.prepend(0)
    ///
    /// for try await element in prependSequence {
    ///     print(element)
    /// }
    ///
    /// // will print:
    /// // Element is 0
    /// // Element is 1
    /// // Element is 2
    /// // Element is 3
    /// ```
    ///
    /// - Parameter element: The element to prepend.
    /// - Returns: The async sequence prepended with the element.
    func prepend(_ element: Element) -> AsyncPrependSequence<Self> {
        AsyncPrependSequence(self, prependElement: { element })
    }

    /// Prepends an element to the async sequence. The element is the result of an async operation.
    ///
    /// ```
    /// let sourceSequence = [1, 2, 3].asyncElements
    /// let prependSequence = sourceSequence.prepend { await getAsyncInt(0) }
    ///
    /// for try await element in prependSequence {
    ///     print(element)
    /// }
    ///
    /// // will print:
    /// // Element is 0
    /// // Element is 1
    /// // Element is 2
    /// // Element is 3
    /// ```
    ///
    /// - Parameter element: The element to prepend.
    /// - Returns: The async sequence prepended with the element.
    func prepend(_ element: @escaping () async throws -> Element) -> AsyncPrependSequence<Self> {
        AsyncPrependSequence(self, prependElement: element)
    }
}

public struct AsyncPrependSequence<UpstreamAsyncSequence: AsyncSequence>: AsyncSequence {
    public typealias Element = UpstreamAsyncSequence.Element
    public typealias AsyncIterator = Iterator

    private var upstreamAsyncSequence: UpstreamAsyncSequence
    private var prependElement: () async throws -> Element

    public init(
        _ upstreamAsyncSequence: UpstreamAsyncSequence,
        prependElement: @escaping () async throws -> Element
    ) {
        self.upstreamAsyncSequence = upstreamAsyncSequence
        self.prependElement = prependElement
    }

    public func makeAsyncIterator() -> AsyncIterator {
        Iterator(
            upstreamIterator: self.upstreamAsyncSequence.makeAsyncIterator(),
            prependElement: self.prependElement
        )
    }

    public struct Iterator: AsyncIteratorProtocol {
        var upstreamIterator: UpstreamAsyncSequence.AsyncIterator
        var prependElement: () async throws -> Element
        var hasBeenDelivered = false

        public init(
            upstreamIterator: UpstreamAsyncSequence.AsyncIterator,
            prependElement: @escaping () async throws -> Element
        ) {
            self.upstreamIterator = upstreamIterator
            self.prependElement = prependElement
        }

        public mutating func next() async throws -> Element? {
            guard !Task.isCancelled else { return nil }

            if !self.hasBeenDelivered {
                self.hasBeenDelivered = true
                return try await prependElement()
            }

            return try await self.upstreamIterator.next()
        }
    }
}
