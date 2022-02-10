//
//  AsyncSequences+Merge.swift
//  
//
//  Created by Thibault Wittemberg on 31/12/2021.
//

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
        return Iterator(upstreamIterators: self.upstreamAsyncSequences.map { $0.makeAsyncIterator() })
    }

    enum UpstreamElement {
        case element(Element)
        case finished
    }

    actor ElementCounter {
        var counter = 0

        func increaseCounter() {
            self.counter += 1
        }

        func decreaseCounter() {
            guard self.counter > 0 else { return }
            self.counter -= 1
        }

        func hasElement() -> Bool {
            self.counter > 0
        }
    }

    public struct Iterator: AsyncIteratorProtocol {
        let sink = AsyncStreams.Passthrough<UpstreamElement>()
        var sinkIterator: AsyncStreams.Passthrough<UpstreamElement>.AsyncIterator
        let upstreamIterators: [SharedAsyncIterator<UpstreamAsyncSequence.AsyncIterator>]
        let elementCounter = ElementCounter()
        var numberOfFinished = 0

        public init(upstreamIterators: [UpstreamAsyncSequence.AsyncIterator]) {
            self.upstreamIterators = upstreamIterators.map { SharedAsyncIterator(iterator: $0) }
            self.sinkIterator = self.sink.makeAsyncIterator()
        }

        mutating func nextElementFromSink() async throws -> Element? {
            var noValue = true
            var value: Element?

            // we now have to eliminate the intermediate ".finished" values until the next
            // true value is found.
            // if every upstream iterator has finished, then the zipped async sequence is also finished
            while noValue {
                guard let nextChildElement = try await self.sinkIterator.next() else {
                    // the sink stream is finished, so is the zipped async sequence
                    noValue = false
                    value = nil
                    break
                }

                switch nextChildElement {
                case .finished:
                    self.numberOfFinished += 1

                    if self.numberOfFinished == self.upstreamIterators.count {
                        noValue = false
                        value = nil
                        break
                    }
                case let .element(element):
                    // nominal case: a next element is available
                    noValue = false
                    value = element
                    await self.elementCounter.decreaseCounter()
                }
            }

            return value
        }

        public mutating func next() async throws -> Element? {
            guard !Task.isCancelled else { return nil }

            // before requesting elements from the upstream iterators, we should reauest the next element from the sink iterator
            // if it has some stacked values

            // for now we leave it commented as I'm not sure it is not counterproductive.
            // This "early" drain might prevent from requesting the next available upstream iterators as soon as possible
            // since the sink iterator might deliver a value and the next will return right away

//            guard await !self.elementCounter.hasElement() else {
//                return try await self.nextElementFromSink()
//            }

            let localSink = self.sink
            let localElementCounter = self.elementCounter

            // iterating over the upstream iterators to ask for their next element. Only
            // the available iterators are requested (not already being computing the next
            // element from the previous iteration and not already finished)
            for upstreamIterator in self.upstreamIterators {
                guard !Task.isCancelled else { break }

                let localUpstreamIterator = upstreamIterator
                guard await !localUpstreamIterator.isFinished() else { continue }
                Task {
                    do {
                        let nextSharedElement = try await localUpstreamIterator.next()

                        // if the next element is nil, it means one of the upstream iterator
                        // is finished ... its does not mean the zipped async sequence is finished (all upstream iterators have to be finished)
                        guard let nextNonNilSharedElement = nextSharedElement else {
                            await localSink.send(.finished)
                            return
                        }

                        guard case let .value(nextElement) = nextNonNilSharedElement else {
                            // the upstream iterator was not available ... see you at the next iteration
                            return
                        }

                        // we have a next element from an upstream iterator, pushing it in the sink stream
                        await localSink.send(.element(nextElement))
                        await localElementCounter.increaseCounter()
                    } catch is CancellationError {
                        await localSink.send(.finished)
                    } catch {
                        await localSink.send(termination: .failure(error))
                    }
                }
            }

            // we wait for the sink iterator to deliver the next element
            return try await self.nextElementFromSink()
        }
    }
}
