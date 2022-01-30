//
//  AsyncSequence+Scan.swift
//  
//
//  Created by Thibault Wittemberg on 31/12/2021.
//

public extension AsyncSequence {
    /// Transforms elements from the upstream async sequence by providing the current element to a closure
    /// along with the last value returned by the closure.
    ///
    /// ```
    /// let sourceSequence = [1, 2, 3, 4, 5].asyncElements
    /// let scannedSequence = sourceSequence.scan("") { accumulator, element in
    ///     return accumulator + "\(element)"
    /// }
    /// for try await element in scannedSequence {
    ///     print(element)
    /// }
    ///
    /// // will print:
    /// "1"
    /// "12"
    /// "123"
    /// "1234"
    /// "12345"
    /// ```
    ///
    /// - Parameters:
    ///   - initialResult: The initial value of the result.
    ///   - nextPartialResult: The closure to execute on each element of the source sequence.
    /// - Returns: The async sequence of all the partial results.
    func scan<Output>(
        _ initialResult: Output,
        _ nextPartialResult: @escaping (Output, Element) async -> Output
    ) -> AsyncScanSequence<Self, Output> {
        AsyncScanSequence(self, initialResult: initialResult, nextPartialResult: nextPartialResult)
    }
}

public struct AsyncScanSequence<UpstreamAsyncSequence: AsyncSequence, Output>: AsyncSequence {
    public typealias Element = Output
    public typealias AsyncIterator = Iterator

    var upstreamAsyncSequence: UpstreamAsyncSequence
    var initialResult: Output
    let nextPartialResult: (Output, UpstreamAsyncSequence.Element) async -> Output

    public init(
        _ upstreamAsyncSequence: UpstreamAsyncSequence,
        initialResult: Output,
        nextPartialResult: @escaping (Output, UpstreamAsyncSequence.Element) async -> Output
    ) {
        self.upstreamAsyncSequence = upstreamAsyncSequence
        self.initialResult = initialResult
        self.nextPartialResult = nextPartialResult
    }

    public func makeAsyncIterator() -> AsyncIterator {
        Iterator(
            upstreamIterator: self.upstreamAsyncSequence.makeAsyncIterator(),
            initialResult: self.initialResult,
            nextPartialResult: self.nextPartialResult
        )
    }

    public struct Iterator: AsyncIteratorProtocol {
        var upstreamIterator: UpstreamAsyncSequence.AsyncIterator
        var currentValue: Output
        let nextPartialResult: (Output, UpstreamAsyncSequence.Element) async -> Output

        public init(
            upstreamIterator: UpstreamAsyncSequence.AsyncIterator,
            initialResult: Output,
            nextPartialResult: @escaping (Output, UpstreamAsyncSequence.Element) async -> Output
        ) {
            self.upstreamIterator = upstreamIterator
            self.currentValue = initialResult
            self.nextPartialResult = nextPartialResult
        }

        public mutating func next() async rethrows -> Output? {
            guard !Task.isCancelled else { return nil }

            let nextUpstreamValue = try await self.upstreamIterator.next()
            guard let nonNilNextUpstreamValue = nextUpstreamValue else { return nil }
            self.currentValue = await self.nextPartialResult(self.currentValue, nonNilNextUpstreamValue)
            return self.currentValue
        }
    }
}
