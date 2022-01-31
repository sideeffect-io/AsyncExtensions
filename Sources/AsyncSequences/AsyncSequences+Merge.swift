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

    actor UpstreamAsyncIteratorState {
        var busy = false
        var finished = false

        func setBusy(_ value: Bool) {
            self.busy = value
        }

        func setFinished() {
            self.finished = true
            self.busy = false
        }

        func isAvailable() -> Bool {
            !self.busy && !self.finished
        }
    }

    final class UpstreamAsyncIterator<BaseAsyncIterator: AsyncIteratorProtocol>: AsyncIteratorProtocol {
        public typealias Element = BaseAsyncIterator.Element
        var iterator: BaseAsyncIterator?
        let state = UpstreamAsyncIteratorState()

        init(iterator: BaseAsyncIterator?) {
            self.iterator = iterator
        }

        public func next() async throws -> BaseAsyncIterator.Element? {
            guard !Task.isCancelled else { return nil }

            await self.state.setBusy(true)
            let next = try await self.iterator?.next()
            if next == nil {
                await self.state.setFinished()
            }
            await self.state.setBusy(false)
            return next
        }

        public func isAvailable() async -> Bool {
            await self.state.isAvailable()
        }
    }

    enum UpstreamElement {
        case element(Element)
        case finished
    }

    public struct Iterator: AsyncIteratorProtocol {
        let passthrough = AsyncStreams.Passthrough<UpstreamElement>()
        var passthroughIterator: AsyncStreams.Passthrough<UpstreamElement>.AsyncIterator
        let upstreamIterators: [UpstreamAsyncIterator<UpstreamAsyncSequence.AsyncIterator>]
        var numberOfFinished = 0

        public init(upstreamIterators: [UpstreamAsyncSequence.AsyncIterator]) {
            self.upstreamIterators = upstreamIterators.map { UpstreamAsyncIterator(iterator: $0) }
            self.passthroughIterator = self.passthrough.makeAsyncIterator()
        }

        // swiftlint:disable:next cyclomatic_complexity
        public mutating func next() async throws -> Element? {
            guard !Task.isCancelled else { return nil }

            let localPassthrough = self.passthrough

            // iterating over the upstream iterators to ask for their next element. Only
            // the available iterators are requested (not already being computing the next
            // element from the previous iteration)
            for upstreamIterator in self.upstreamIterators {
                guard !Task.isCancelled else { break }

                let localUpstreamIterator = upstreamIterator

                // isAvailable() means is not busy and not finished
                if await localUpstreamIterator.isAvailable() {
                    Task {
                        do {
                            let nextElement = try await localUpstreamIterator.next()

                            // if the next element is nil, it means one if the upstream iterator
                            // is finished ... its does not mean the zipped async sequence is finished
                            guard let nonNilNextElement = nextElement else {
                                localPassthrough.send(.finished)
                                return
                            }

                            localPassthrough.send(.element(nonNilNextElement))
                        } catch is CancellationError {
                            localPassthrough.send(.finished)
                        } catch {
                            localPassthrough.send(termination: .failure(error))
                        }
                    }
                }
            }

            var noValue = true
            var value: Element?

            // we now have to eliminate the intermediate ".finished" values until the next
            // true value is found.
            // if every upstream iterator has finished, then the zipped async sequence is also finished
            while noValue {
                guard let nextChildElement = try await self.passthroughIterator.next() else {
                    // the passthrough is finished, so is the zipped async sequence
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
                    // nominal case: a net element is available
                    noValue = false
                    value = element
                }
            }

            return value
        }
    }
}
