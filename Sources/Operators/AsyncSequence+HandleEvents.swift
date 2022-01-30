//
//  AsyncSequence+HandleEvents.swift
//  
//
//  Created by Thibault Wittemberg on 31/12/2021.
//

import Combine

public extension AsyncSequence {
    /// Performs the specified closures when async sequences events occur.
    ///
    /// ```
    /// let sourceSequence = AsyncSequences.From([1, 2, 3, 4, 5])
    /// let handledSequence = sourceSequence.handleEvents {
    ///    print("Begin looping")
    /// } onElement: { element in
    ///    print("Element is \(element)")
    /// } onCancel: {
    ///    print("Cancelled")
    /// } onFinish: { termination in
    ///    print(termination)
    /// }
    ///
    /// for try await element in handledSequence {}
    ///
    /// // will print:
    /// // Begin looping
    /// // Element is 1
    /// // Element is 2
    /// // Element is 3
    /// // Element is 4
    /// // Element is 5
    /// // finished
    /// ```
    ///
    /// - Parameters:
    ///   - onStart: The operation to execute when the async sequence is first iterated.
    ///   - onElement: The operation to execute on each element.
    ///   - onCancel: The operation to execute when the task suppoerting the async sequence looping is cancelled.
    ///   - onFinish: The operation to execute when the async sequence looping is finished, whether it is due to an error or a normal termination.
    /// - Returns: The AsyncSequence that executes the `receiveElement` operation for each element of the source sequence.
    func handleEvents(
        onStart: (() async -> Void)? = nil,
        onElement: ((Element) async -> Void)? = nil,
        onCancel: (() async -> Void)? = nil,
        onFinish: ((Termination) async -> Void)? = nil
    ) -> AsyncHandleEventsSequence<Self> {
        AsyncHandleEventsSequence(self, onStart: onStart, onElement: onElement, onCancel: onCancel, onFinish: onFinish)
    }
}

public struct AsyncHandleEventsSequence<UpstreamAsyncSequence: AsyncSequence>: AsyncSequence {
    public typealias Element = UpstreamAsyncSequence.Element
    public typealias AsyncIterator = Iterator

    var upstreamAsyncSequence: UpstreamAsyncSequence
    let onStart: (() async -> Void)?
    let onElement: ((UpstreamAsyncSequence.Element) async -> Void)?
    let onCancel: (() async -> Void)?
    let onFinish: ((Termination) async -> Void)?

    public init(
        _ upstreamAsyncSequence: UpstreamAsyncSequence,
        onStart: (() async -> Void)?,
        onElement: ((UpstreamAsyncSequence.Element) async -> Void)?,
        onCancel: (() async -> Void)?,
        onFinish: ((Termination) async -> Void)?
    ) {
        self.upstreamAsyncSequence = upstreamAsyncSequence
        self.onStart = onStart
        self.onElement = onElement
        self.onCancel = onCancel
        self.onFinish = onFinish
    }

    public func makeAsyncIterator() -> AsyncIterator {
        Iterator(
            upstreamIterator: self.upstreamAsyncSequence.makeAsyncIterator(),
            onStart: self.onStart,
            onElement: self.onElement,
            onCancel: self.onCancel,
            onFinish: onFinish
        )
    }

    public struct Iterator: AsyncIteratorProtocol {
        var upstreamIterator: UpstreamAsyncSequence.AsyncIterator

        let onStart: (() async -> Void)?
        let onElement: ((UpstreamAsyncSequence.Element) async -> Void)?
        let onCancel: (() async -> Void)?
        let onFinish: ((Termination) async -> Void)?

        var onStartExecuted = false

        public init(
            upstreamIterator: UpstreamAsyncSequence.AsyncIterator,
            onStart: (() async -> Void)?,
            onElement: ((UpstreamAsyncSequence.Element) async -> Void)?,
            onCancel: (() async -> Void)?,
            onFinish: ((Termination) async -> Void)?
        ) {
            self.upstreamIterator = upstreamIterator
            self.onStart = onStart
            self.onElement = onElement
            self.onCancel = onCancel
            self.onFinish = onFinish
        }

        public mutating func next() async throws -> Element? {
            guard !Task.isCancelled else {
                await self.onCancel?()
                return nil
            }

            if !self.onStartExecuted {
                await self.onStart?()
                self.onStartExecuted = true
            }

            let localOnCancel = self.onCancel

            do {
                return try await withTaskCancellationHandler(operation: {
                    let nextElement = try await self.upstreamIterator.next()

                    if let element = nextElement {
                        await self.onElement?(element)
                    } else {
                        await self.onFinish?(.finished)
                    }

                    return nextElement
                }, onCancel: {
                    Task {
                        await localOnCancel?()
                    }
                })
            } catch {
                await self.onFinish?(.failure(error))
                throw error
            }
        }
    }
}
