//
//  AsyncSequence+WithLatestFrom.swift
//  
//
//  Created by Thibault Wittemberg on 07/03/2022.
//

public extension AsyncSequence {
    ///  Merges two AsyncSequences into a single one by combining each value
    ///  from self with the latest value from the other sequence, if any.
    ///
    ///  ```
    ///  let seq1 = AsyncStreams.CurrentValue<Int>(1)
    ///  let seq2 = AsyncStreams.CurrentValue<String>("1")
    ///
    ///  let combinedSeq = seq1.withLatestFrom(seq2)
    ///
    ///  Task {
    ///     for try await element in combinedSeq {
    ///         print(element)
    ///     }
    ///  }
    ///
    ///  seq1.send(2)
    ///  seq2.send("2")
    ///  seq1.send(3)
    ///
    ///  // will print:
    ///  (1, "1")
    ///  (2, "1")
    ///  (3, "2")
    ///  ```
    ///
    ///  - parameter other: the other async sequence
    ///
    ///  - returns: An async sequence emitting the result of combining each value of the self
    ///  with the latest value from the other sequence. If the other sequence finishes, the returned sequence
    ///  will finish with the next value from self. if the other sequence fails, the returned sequence will fail
    ///  with the next value from self.
    ///
    func withLatestFrom<OtherAsyncSequence: AsyncSequence>(
        _ other: OtherAsyncSequence,
        otherPriority: TaskPriority? = nil
    ) -> AsyncWithLatestFromSequence<Self, OtherAsyncSequence> {
        AsyncWithLatestFromSequence(
            self,
            other: other,
            otherPriority: otherPriority
        )
    }
}

public struct AsyncWithLatestFromSequence<UpstreamAsyncSequence: AsyncSequence, OtherAsyncSequence: AsyncSequence>: AsyncSequence {
    public typealias Element = (UpstreamAsyncSequence.Element, OtherAsyncSequence.Element)
    public typealias AsyncIterator = Iterator

    let upstreamAsyncSequence: UpstreamAsyncSequence
    let otherAsyncSequence: OtherAsyncSequence
    let otherPriority: TaskPriority?

    public init(
        _ upstreamAsyncSequence: UpstreamAsyncSequence,
        other otherAsyncSequence: OtherAsyncSequence,
        otherPriority: TaskPriority? = nil
    ) {
        self.upstreamAsyncSequence = upstreamAsyncSequence
        self.otherAsyncSequence = otherAsyncSequence
        self.otherPriority = otherPriority
    }

    public func makeAsyncIterator() -> AsyncIterator {
        Iterator(
            self.upstreamAsyncSequence.makeAsyncIterator(),
            other: self.otherAsyncSequence.makeAsyncIterator(),
            otherPriority: self.otherPriority
        )
    }

    final class OtherIteratorManager {
        var otherElement: OtherAsyncSequence.Element?
        var otherError: Error?

        var otherIterator: OtherAsyncSequence.AsyncIterator
        var hasStarted = false

        let otherPriority: TaskPriority?

        init(
            otherIterator: OtherAsyncSequence.AsyncIterator,
            otherPriority: TaskPriority?
        ) {
            self.otherIterator = otherIterator
            self.otherPriority = otherPriority
        }

        /// iterates over the other sequence and track its current value
        func startOtherIterator() async throws {
            guard !self.hasStarted else { return }
            self.hasStarted = true

            self.otherElement = try await self.otherIterator.next()

            Task(priority: self.otherPriority) { [weak self] in
                do {
                    while let element = try await self?.otherIterator.next() {
                        guard !Task.isCancelled else { break }

                        self?.otherElement = element
                    }
                    self?.otherElement = nil
                } catch {
                    self?.otherError = error
                }
            }
        }
    }

    public struct Iterator: AsyncIteratorProtocol {
        var upstreamAsyncIterator: UpstreamAsyncSequence.AsyncIterator
        let otherIteratorManager: OtherIteratorManager

        init(
            _ upstreamAsyncIterator: UpstreamAsyncSequence.AsyncIterator,
            other otherAsyncIterator: OtherAsyncSequence.AsyncIterator,
            otherPriority: TaskPriority?
        ) {
            self.upstreamAsyncIterator = upstreamAsyncIterator
            self.otherIteratorManager = OtherIteratorManager(
                otherIterator: otherAsyncIterator,
                otherPriority: otherPriority
            )
        }

        public mutating func next() async throws -> Element? {
            guard !Task.isCancelled else { return nil }

            try await self.otherIteratorManager.startOtherIterator()

            let upstreamElement = try await self.upstreamAsyncIterator.next()
            let otherElement = self.otherIteratorManager.otherElement

            if let otherError = self.otherIteratorManager.otherError {
                throw otherError
            }

            guard let nonNilUpstreamElement = upstreamElement,
                  let nonNilOtherElement = otherElement else {
                      return nil
                  }

            return (nonNilUpstreamElement, nonNilOtherElement)
        }
    }
}
