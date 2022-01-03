//
//  AsyncSequence+SwitchToLatest.swift
//  
//
//  Created by Thibault Wittemberg on 04/01/2022.
//

public extension AsyncSequence where Element: AsyncSequence {
    /// Republishes elements sent by the most recently received async sequence.
    ///
    /// ```
    /// let sourceSequence = [1, 2, 3].asyncElements
    /// let mappedSequence = sourceSequence.map { element in ["a\(element)", "b\(element)"].asyncElements }
    /// let switchedSequence = mappedSequence.switchToLatest()
    ///
    /// for try await element in switchedSequence {
    ///     print(element)
    /// }
    ///
    /// // will print:
    /// a3, b3
    /// ```
    ///
    /// - Returns: The async sequence that republishes elements sent by the most recently received async sequence.
    func switchToLatest() -> AsyncSwitchToLatestSequence<Self> {
        AsyncSwitchToLatestSequence<Self>(self)
    }
}

public struct AsyncSwitchToLatestSequence<UpstreamAsyncSequence: AsyncSequence>: AsyncSequence where UpstreamAsyncSequence.Element: AsyncSequence {
    public typealias Element = UpstreamAsyncSequence.Element.Element
    public typealias AsyncIterator = Iterator

    let upstreamAsyncSequence: UpstreamAsyncSequence

    public init(_ upstreamAsyncSequence: UpstreamAsyncSequence) {
        self.upstreamAsyncSequence = upstreamAsyncSequence
    }

    public func makeAsyncIterator() -> AsyncIterator {
        Iterator(upstreamIterator: self.upstreamAsyncSequence.makeAsyncIterator())
    }

    final class UpstreamIteratorManager {
        var upstreamIterator: UpstreamAsyncSequence.AsyncIterator
        var currentChildIterator: UpstreamAsyncSequence.Element.AsyncIterator?
        var hasStarted = false
        var currentTask: Task<Element?, Error>?

        init(upstreamIterator: UpstreamAsyncSequence.AsyncIterator) {
            self.upstreamIterator = upstreamIterator
        }

        func setCurrentTask(task: Task<Element?, Error>) {
            self.currentTask = task
        }

        /// iterates over the upstream sequence and maintain the current async iterator while cancelling the current .next() task for each new element
        func startUpstreamIterator() async throws {
            guard !self.hasStarted else { return }
            self.hasStarted = true

            let firstChildSequence = try await self.upstreamIterator.next()
            self.currentChildIterator = firstChildSequence?.makeAsyncIterator()

            Task {
                while let nextChildSequence = try await self.upstreamIterator.next() {
                    self.currentChildIterator = nextChildSequence.makeAsyncIterator()
                    self.currentTask?.cancel()
                    self.currentTask = nil
                }
            }
        }

        func nextOnCurrentChildIterator() async throws -> Element? {
            let nextElement = try await self.currentChildIterator?.next()
            return nextElement
        }
    }

    public struct Iterator: AsyncIteratorProtocol {
        let upstreamIteratorManager: UpstreamIteratorManager

        init(upstreamIterator: UpstreamAsyncSequence.AsyncIterator) {
            self.upstreamIteratorManager = UpstreamIteratorManager(upstreamIterator: upstreamIterator)
        }

        public mutating func next() async throws -> Element? {
            guard !Task.isCancelled else { return nil }

            var noValueHasBeenEmitted = true
            var emittedElement: Element?
            var currentTask: Task<Element?, Error>

            try await self.upstreamIteratorManager.startUpstreamIterator()
            let localUpstreamIteratorManager = self.upstreamIteratorManager

            while noValueHasBeenEmitted {
                currentTask = Task {
                    do {
                        return try await localUpstreamIteratorManager.nextOnCurrentChildIterator()
                    } catch is CancellationError {
                        return nil
                    } catch {
                        throw error
                    }
                }
                localUpstreamIteratorManager.setCurrentTask(task: currentTask)
                emittedElement = try await currentTask.value
                noValueHasBeenEmitted = (emittedElement == nil && currentTask.isCancelled)
            }

            return emittedElement
        }
    }
}
