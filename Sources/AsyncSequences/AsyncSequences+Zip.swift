//
//  AsyncSequences+ZipMany.swift
//
//
//  Created by Thibault Wittemberg on 13/01/2022.
//

// swiftlint:disable operator_usage_whitespace
public extension AsyncSequences {
    /// `Zip2` is an AsyncSequence that combines the latest elements from two sequences according to their temporality
    /// and emits a tuple to the client. If any Async Sequence ends successfully or fails with an error, so too does the zipped
    /// Async Sequence.
    ///
    /// ```
    /// let asyncSequence1 = [1, 2, 3, 4, 5].asyncElements
    /// let asyncSequence2 = ["1", "2", "3", "4", "5"].asyncElements
    ///
    /// let zippedAsyncSequence = AsyncSequences.Zip2(asyncSequence1, asyncSequence2)
    ///
    /// for try await element in zippedAsyncSequence {
    ///     print(element) // will print -> (1, "1") (2, "2") (3, "3") (4, "4") (5, "5")
    /// }
    /// ```
    typealias Zip2<UpstreamAsyncSequenceA: AsyncSequence,
                   UpstreamAsyncSequenceB: AsyncSequence> = AsyncZip2Sequence<UpstreamAsyncSequenceA,
                                                                              UpstreamAsyncSequenceB>

    /// `Zip3` is an AsyncSequence that combines the latest elements from three sequences according to their temporality
    /// and emits a tuple to the client. If any Async Sequence ends successfully or fails with an error, so too does the zipped
    /// Async Sequence.
    ///
    /// ```
    /// let asyncSequence1 = [1, 2, 3, 4, 5].asyncElements
    /// let asyncSequence2 = ["1", "2", "3", "4", "5"].asyncElements
    /// let asyncSequence3 = [true, false, true, false, true].asyncElements
    ///
    /// let zippedAsyncSequence = AsyncSequences.Zip3(asyncSequence1, asyncSequence2, asyncSequence3)
    ///
    /// for try await element in zippedAsyncSequence {
    ///     print(element) // will print -> (1, "1", true) (2, "2", false) (3, "3", true) (4, "4", false) (5, "5", true)
    /// }
    /// ```
    typealias Zip3<UpstreamAsyncSequenceA: AsyncSequence,
                   UpstreamAsyncSequenceB: AsyncSequence,
                   UpstreamAsyncSequenceC: AsyncSequence> = AsyncZip3Sequence<UpstreamAsyncSequenceA,
                                                                              UpstreamAsyncSequenceB,
                                                                              UpstreamAsyncSequenceC>

    /// `Zip` is an AsyncSequence that combines the latest elements from several sequences according to their temporality
    /// and emits an array to the client. If any Async Sequence ends successfully or fails with an error, so too does the zipped
    /// Async Sequence.
    ///
    /// ```
    /// let asyncSequence1 = [1, 2, 3].asyncElements
    /// let asyncSequence2 = [1, 2, 3].asyncElements
    /// let asyncSequence3 = [1, 2, 3].asyncElements
    /// let asyncSequence4 = [1, 2, 3].asyncElements
    /// let asyncSequence5 = [1, 2, 3].asyncElements
    ///
    /// let zippedAsyncSequence = AsyncSequences.Zip(asyncSequence1, asyncSequence2, asyncSequence3, asyncSequence4, asyncSequence5)
    ///
    /// for try await element in zippedAsyncSequence {
    ///     print(element) // will print -> [1, 1, 1, 1, 1] [2, 2, 2, 2, 2] [3, 3, 3, 3, 3]
    /// }
    /// ```
    typealias Zip<UpstreamAsyncSequence: AsyncSequence> = AsyncZipSequence<UpstreamAsyncSequence>
}

public struct AsyncZip2Sequence<UpstreamAsyncSequenceA: AsyncSequence, UpstreamAsyncSequenceB: AsyncSequence>: AsyncSequence {
    public typealias Element = (UpstreamAsyncSequenceA.Element, UpstreamAsyncSequenceB.Element)
    public typealias AsyncIterator = Iterator

    let upstreamAsyncSequenceA: UpstreamAsyncSequenceA
    let upstreamAsyncSequenceB: UpstreamAsyncSequenceB

    public init(_ upstreamAsyncSequenceA: UpstreamAsyncSequenceA, _ upstreamAsyncSequenceB: UpstreamAsyncSequenceB) {
        self.upstreamAsyncSequenceA = upstreamAsyncSequenceA
        self.upstreamAsyncSequenceB = upstreamAsyncSequenceB
    }

    public func makeAsyncIterator() -> AsyncIterator {
        return Iterator(
            upstreamIteratorA: SharedAsyncIterator(iterator: self.upstreamAsyncSequenceA.makeAsyncIterator()),
            upstreamIteratorB: SharedAsyncIterator(iterator: self.upstreamAsyncSequenceB.makeAsyncIterator())
        )
    }

    public struct Iterator: AsyncIteratorProtocol {
        let upstreamIteratorA: SharedAsyncIterator<UpstreamAsyncSequenceA.AsyncIterator>
        let upstreamIteratorB: SharedAsyncIterator<UpstreamAsyncSequenceB.AsyncIterator>

        public mutating func next() async throws -> Element? {
            guard !Task.isCancelled else { return nil }

            let localUpstreamIteratorA = self.upstreamIteratorA
            let localUpstreamIteratorB = self.upstreamIteratorB

            // we ask for the next value for the 2 iterators in a concurrent fashion
            // we have to keep track of the order of the values because of the sepcific chronology of each sequence
            // we proceed concurrently in order to be able the finish the zipped sequence whenever a sequence finishes
            let element = try await withThrowingTaskGroup(of: (Int, Any).self) { group -> (UpstreamAsyncSequenceA.Element?,
                                                                                           UpstreamAsyncSequenceB.Element?) in
                _ = group.addTaskUnlessCancelled {
                    let nextElement = try await localUpstreamIteratorA.next()
                    return (1, nextElement as Any)
                }

                _ = group.addTaskUnlessCancelled {
                    let nextElement = try await localUpstreamIteratorB.next()
                    return (2, nextElement as Any)
                }

                var nextA: UpstreamAsyncSequenceA.Element?
                var nextB: UpstreamAsyncSequenceB.Element?

                for try await element in group {
                    guard !Task.isCancelled else { break }

                    if element.0 == 1 {
                        nextA = element.1 as? UpstreamAsyncSequenceA.Element
                    }

                    if element.0 == 2 {
                        nextB = element.1 as? UpstreamAsyncSequenceB.Element
                    }
                }

                return (nextA, nextB)
            }

            guard let nonNilElementA = element.0 else { return nil }
            guard let nonNilElementB = element.1 else { return nil }

            return (nonNilElementA, nonNilElementB)
        }
    }
}

public struct AsyncZip3Sequence < UpstreamAsyncSequenceA: AsyncSequence,
                                UpstreamAsyncSequenceB: AsyncSequence,
                                UpstreamAsyncSequenceC: AsyncSequence>: AsyncSequence {
    public typealias Element = (UpstreamAsyncSequenceA.Element, UpstreamAsyncSequenceB.Element, UpstreamAsyncSequenceC.Element)
    public typealias AsyncIterator = Iterator

    let upstreamAsyncSequenceA: UpstreamAsyncSequenceA
    let upstreamAsyncSequenceB: UpstreamAsyncSequenceB
    let upstreamAsyncSequenceC: UpstreamAsyncSequenceC

    public init(_ upstreamAsyncSequenceA: UpstreamAsyncSequenceA,
                _ upstreamAsyncSequenceB: UpstreamAsyncSequenceB,
                _ upstreamAsyncSequenceC: UpstreamAsyncSequenceC) {
        self.upstreamAsyncSequenceA = upstreamAsyncSequenceA
        self.upstreamAsyncSequenceB = upstreamAsyncSequenceB
        self.upstreamAsyncSequenceC = upstreamAsyncSequenceC
    }

    public func makeAsyncIterator() -> AsyncIterator {
        return Iterator(
            upstreamIteratorA: SharedAsyncIterator(iterator: self.upstreamAsyncSequenceA.makeAsyncIterator()),
            upstreamIteratorB: SharedAsyncIterator(iterator: self.upstreamAsyncSequenceB.makeAsyncIterator()),
            upstreamIteratorC: SharedAsyncIterator(iterator: self.upstreamAsyncSequenceC.makeAsyncIterator())
        )
    }

    public struct Iterator: AsyncIteratorProtocol {
        let upstreamIteratorA: SharedAsyncIterator<UpstreamAsyncSequenceA.AsyncIterator>
        let upstreamIteratorB: SharedAsyncIterator<UpstreamAsyncSequenceB.AsyncIterator>
        let upstreamIteratorC: SharedAsyncIterator<UpstreamAsyncSequenceC.AsyncIterator>

        public mutating func next() async throws -> Element? {
            guard !Task.isCancelled else { return nil }

            let localUpstreamIteratorA = self.upstreamIteratorA
            let localUpstreamIteratorB = self.upstreamIteratorB
            let localUpstreamIteratorC = self.upstreamIteratorC

            // we ask for the next value for the 3 iterators in a concurrent fashion
            // we have to keep track of the order of the values because of the sepcific chronology of each sequence
            // we proceed concurrently in order to be able the finish the zipped sequence whenever a sequence finishes
            let element = try await withThrowingTaskGroup(of: (Int, Any).self) { group -> (UpstreamAsyncSequenceA.Element?,
                                                                                           UpstreamAsyncSequenceB.Element?,
                                                                                           UpstreamAsyncSequenceC.Element?) in
                _ = group.addTaskUnlessCancelled {
                    let nextElement = try await localUpstreamIteratorA.next()
                    return (1, nextElement as Any)
                }

                _ = group.addTaskUnlessCancelled {
                    let nextElement = try await localUpstreamIteratorB.next()
                    return (2, nextElement as Any)
                }

                _ = group.addTaskUnlessCancelled {
                    let nextElement = try await localUpstreamIteratorC.next()
                    return (3, nextElement as Any)
                }

                var nextA: UpstreamAsyncSequenceA.Element?
                var nextB: UpstreamAsyncSequenceB.Element?
                var nextC: UpstreamAsyncSequenceC.Element?

                for try await element in group {
                    guard !Task.isCancelled else { break }

                    if element.0 == 1 {
                        nextA = element.1 as? UpstreamAsyncSequenceA.Element
                    }

                    if element.0 == 2 {
                        nextB = element.1 as? UpstreamAsyncSequenceB.Element
                    }

                    if element.0 == 3 {
                        nextC = element.1 as? UpstreamAsyncSequenceC.Element
                    }
                }

                return (nextA, nextB, nextC)
            }

            guard let nonNilElementA = element.0 else { return nil }
            guard let nonNilElementB = element.1 else { return nil }
            guard let nonNilElementC = element.2 else { return nil }

            return (nonNilElementA, nonNilElementB, nonNilElementC)
        }
    }
}

public struct AsyncZipSequence<UpstreamAsyncSequence: AsyncSequence>: AsyncSequence {
    public typealias Element = [UpstreamAsyncSequence.Element]
    public typealias AsyncIterator = Iterator

    let upstreamAsyncSequences: [UpstreamAsyncSequence]

    public init(_ upstreamAsyncSequences: [UpstreamAsyncSequence]) {
        self.upstreamAsyncSequences = upstreamAsyncSequences
    }

    public init(_ upstreamAsyncSequences: UpstreamAsyncSequence...) {
        self.init(upstreamAsyncSequences)
    }

    public func makeAsyncIterator() -> AsyncIterator {
        return Iterator(upstreamIterators: self.upstreamAsyncSequences.map { SharedAsyncIterator(iterator: $0.makeAsyncIterator()) })
    }

    actor SequenceIndexGenerator {
        var index: Int = 0

        func nextIndex() -> Int {
            self.index += 1
            return index
        }
    }

    public struct Iterator: AsyncIteratorProtocol {
        let upstreamIterators: [SharedAsyncIterator<UpstreamAsyncSequence.AsyncIterator>]

        public mutating func next() async throws -> Element? {
            guard !Task.isCancelled else { return nil }

            let sequenceIndexGenerator = SequenceIndexGenerator()

            // we ask for the next value for every iterators in a concurrent fashion
            // we have to keep track of the order of the values because of the specific chronology of each sequence
            // we proceed concurrently in order to be able the finish the zipped sequence whenever a sequence finishes
            let elements = try await withThrowingTaskGroup(
                of: (Int, UpstreamAsyncSequence.Element?).self
            ) { group -> [(Int, UpstreamAsyncSequence.Element?)] in
                for upstreamIterator in self.upstreamIterators {
                    let nextIndex = await sequenceIndexGenerator.nextIndex()
                    _ = group.addTaskUnlessCancelled {
                        let localUpstreamIterator = upstreamIterator
                        let nextElement = try await localUpstreamIterator.next()
                        return (nextIndex, nextElement)
                    }
                }

                var result = [(Int, UpstreamAsyncSequence.Element?)]()

                for try await element in group {
                    guard !Task.isCancelled else {
                        result.append((0, nil))
                        break
                    }

                    result.append(element)
                    if element.1 == nil {
                        group.cancelAll()
                        break
                    }
                }
                return result
            }

            if elements.contains(where: { $0.1 == nil }) {
                return nil
            }

            return elements.sorted(by: { $0.0 < $1.0 }).compactMap { $0.1 }
        }
    }
}
