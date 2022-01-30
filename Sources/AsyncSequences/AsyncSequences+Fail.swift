//
//  AsyncSequences+Fail.swift
//  
//
//  Created by Thibault Wittemberg on 04/01/2022.
//

public extension AsyncSequences {
    /// `Fail` is an AsyncSequence that outputs no elements and throws an error.
    /// If the parent task is cancelled while iterating then the iteration finishes before emitting the error.
    ///
    /// ```
    /// let failSequence = AsyncSequences.Fail<Int, Swift.Error>(error: NSError(domain: "", code: 1))
    /// do {
    ///     for try await element in failSequence {
    ///         // will never be called
    ///     }
    /// } catch {
    ///     // will catch `NSError(domain: "", code: 1)` here
    /// }
    /// ```
    typealias Fail<Element> = AsyncFailSequence<Element>
}

public struct AsyncFailSequence<Element>: AsyncSequence {
    public typealias Element = Element
    public typealias AsyncIterator = Iterator

    var error: Error

    public init<Failure: Error>(error: Failure) {
        self.error = error
    }

    public func makeAsyncIterator() -> AsyncIterator {
        Iterator(error: self.error)
    }

    public struct Iterator: AsyncIteratorProtocol {
        var error: Error

        public mutating func next() async throws -> Element? {
            guard !Task.isCancelled else { return nil }

            throw self.error
        }
    }
}
