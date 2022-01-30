//
//  AsyncSequences+From.swift
//  
//
//  Created by Thibault Wittemberg on 01/01/2022.
//

public extension AsyncSequences {
    /// `From` is an AsyncSequence that outputs elements from a traditional Sequence.
    /// If the parent task is cancelled while iterating then the iteration finishes.
    typealias From<Base: Swift.Sequence> = AsyncFromSequence<Base>
}

public extension Sequence {
    /// Creates an AsyncSequence of the sequence elements.
    /// - Returns: The AsyncSequence that outputs the elements from the sequence.
    var asyncElements: AsyncSequences.From<Self> {
        AsyncSequences.From(self)
    }
}

public struct AsyncFromSequence<BaseSequence: Sequence>: AsyncSequence {
    public typealias Element = BaseSequence.Element
    public typealias AsyncIterator = Iterator

    private var baseSequence: BaseSequence
    private var interval: AsyncSequences.Interval

    public init(_ baseSequence: BaseSequence, interval: AsyncSequences.Interval = .immediate) {
        self.baseSequence = baseSequence
        self.interval = interval
    }

    public func makeAsyncIterator() -> AsyncIterator {
        Iterator(baseIterator: self.baseSequence.makeIterator(), interval: self.interval)
    }

    public struct Iterator: AsyncIteratorProtocol {
        var baseIterator: BaseSequence.Iterator
        var interval: AsyncSequences.Interval

        public mutating func next() async -> BaseSequence.Element? {
            guard !Task.isCancelled else { return nil }

            if self.interval != .immediate {
                do {
                    try await Task.sleep(nanoseconds: self.interval.value)
                } catch {}
            }

            let next = self.baseIterator.next()
            return next
        }
    }
}
