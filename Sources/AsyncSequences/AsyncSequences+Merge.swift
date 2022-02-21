//
//  AsyncSequences+Merge.swift
//  
//
//  Created by Thibault Wittemberg on 31/12/2021.
//
import Foundation

public extension AsyncSequences {
    /// `Merge` is an AsyncSequence that merges several async sequences respecting
    /// their temporality while being iterated over. If the parent task is cancelled while iterating
    /// then the iteration finishes.
    /// When all the async sequences have finished, so too does the merged async sequence.
    ///
    /// ```
    /// // 0.1ms   1ms    1.5ms   2ms     3ms     4.5ms
    /// //  4       1       5      2       3        6
    ///
    /// let asyncSequence1 = AsyncStream(Int.self, bufferingPolicy: .unbounded) { continuation in
    ///     Task {
    ///         try await Task.sleep(nanoseconds: 1_000_000)
    ///         continuation.yield(1)
    ///         try await Task.sleep(nanoseconds: 1_000_000)
    ///         continuation.yield(2)
    ///         try await Task.sleep(nanoseconds: 1_000_000)
    ///         continuation.yield(3)
    ///         continuation.finish()
    ///     }
    /// }
    ///
    /// let asyncSequence2 = AsyncStream(Int.self, bufferingPolicy: .unbounded) { continuation in
    ///     Task {
    ///         try await Task.sleep(nanoseconds: 100_000)
    ///         continuation.yield(4)
    ///         try await Task.sleep(nanoseconds: 1_400_000)
    ///         continuation.yield(5)
    ///         try await Task.sleep(nanoseconds: 3_000_000)
    ///         continuation.yield(6)
    ///         continuation.finish()
    ///     }
    /// }
    ///
    /// let mergedAsyncSequence = AsyncSequences.Merge([asyncSequence1, asyncSequence2])
    ///
    /// for try await element in mergedAsyncSequence {
    ///     print(element) // will print -> 4 1 5 2 3 6
    /// }
    /// ```
    typealias Merge<UpstreamAsyncSequence: AsyncSequence> = AsyncMergeSequence<UpstreamAsyncSequence>
}

public struct AsyncMergeSequence<UpstreamAsyncSequence: AsyncSequence>: AsyncSequence {
    public typealias Element = UpstreamAsyncSequence.Element
    public typealias AsyncIterator = Iterator

    let upstreamAsyncSequences: [UpstreamAsyncSequence]

    public init(_ upstreamAsyncSequences: [UpstreamAsyncSequence]) {
        self.upstreamAsyncSequences = upstreamAsyncSequences
    }

    public init(_ upstreamAsyncSequences: UpstreamAsyncSequence...) {
        self.init(upstreamAsyncSequences)
    }

    public func makeAsyncIterator() -> Iterator {
        return Iterator(upstreamAsyncSequences: self.upstreamAsyncSequences)
    }

    enum UpstreamElement {
        case element(Element)
        case finished
    }

    //    actor ElementCounter {
    //        var counter = 0
    //
    //        func increaseCounter() {
    //            self.counter += 1
    //        }
    //
    //        func decreaseCounter() {
    //            guard self.counter > 0 else { return }
    //            self.counter -= 1
    //        }
    //
    //        func hasElement() -> Bool {
    //            self.counter > 0
    //        }
    //    }

    public struct Iterator: AsyncIteratorProtocol {

        var downstreamIterator: AsyncStreams.Passthrough<UpstreamElement>.AsyncIterator
        let upstreamAsyncSequenceRegulators: [ConcurrentAccessRegulator<UpstreamAsyncSequence>]
        // let elementCounter = ElementCounter()
        var numberOfFinished = 0

        public init(upstreamAsyncSequences: [UpstreamAsyncSequence]) {
            let downstreamStream = AsyncStreams.Passthrough<UpstreamElement>()
            self.downstreamIterator = downstreamStream.makeAsyncIterator()
            self.upstreamAsyncSequenceRegulators = upstreamAsyncSequences.map { upstreamAsyncSequence in
                var isAlreadyFinished = false
                return ConcurrentAccessRegulator(
                    upstreamAsyncSequence,
                    onNext: { element in
                        if let nonNilElement = element {
                            // await localElementCounter.increaseCounter()
                            downstreamStream.send(.element(nonNilElement))
                            return
                        }

                        guard !isAlreadyFinished else { return }

                        isAlreadyFinished = true
                        downstreamStream.send(.finished)
                    },
                    onError: { error in
                        downstreamStream.send(termination: .failure(error))
                    },
                    onCancel: {
                        guard !isAlreadyFinished else { return }
                        isAlreadyFinished = true
                        downstreamStream.send(.finished)
                    })
            }
        }

        mutating func nextElementFromDownstreamStream() async throws -> Element? {
            var noValue = true
            var value: Element?

            // we now have to eliminate the intermediate ".finished" values until the next
            // true value is found.
            // if every upstream iterator has finished, then the zipped async sequence is also finished
            while noValue {
                guard let nextChildElement = try await self.downstreamIterator.next() else {
                    // the downstream stream is finished, so is the zipped async sequence
                    noValue = false
                    value = nil
                    break
                }

                switch nextChildElement {
                case .finished:

                    self.numberOfFinished += 1

                    if self.numberOfFinished == self.upstreamAsyncSequenceRegulators.count {
                        noValue = false
                        value = nil
                        break
                    }
                case let .element(element):
                    // nominal case: a next element is available
                    noValue = false
                    value = element
                    // await self.elementCounter.decreaseCounter()
                }
            }

            return value
        }

        public mutating func next() async throws -> Element? {
            guard !Task.isCancelled else { return nil }

            // before requesting elements from the upstream iterators, we should request the next element from the sink iterator
            // if it has some stacked values
            // for now we leave it commented as I'm not sure it is not counterproductive.
            // This "early" drain might prevent from requesting the next available upstream iterators as soon as possible
            // since the sink iterator might deliver a value and the next will return right away

            //            guard await !self.elementCounter.hasElement() else {
            //                return try await self.nextElementFromSink()
            //            }

            // iterating over the upstream iterators to ask for their next element. Only
            // the available iterators will respond (not already being computing the next
            // element from the previous iteration and not already finished)
            for upstreamAsyncSequenceRegulator in self.upstreamAsyncSequenceRegulators {
                Task {
                    await upstreamAsyncSequenceRegulator.requestNextIfAvailable()
                }
            }

            // we wait for the sink iterator to deliver the next element
            return try await self.nextElementFromDownstreamStream()
        }
    }
}
