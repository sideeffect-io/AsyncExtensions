//
//  AsyncSequence+Multicast.swift
//  
//
//  Created by Thibault Wittemberg on 21/02/2022.
//

public extension AsyncSequence {
    /// Use multicast  when you have multiple client loops, but you want the upstream async sequence to only produce a single `AsyncIterator`.
    /// This is useful when upstream async sequences are doing expensive work you don’t want to duplicate, like performing network requests.
    ///
    /// The following example uses an async sequence as a counter to emit three random numbers.
    /// It uses a ``AsyncSequence/multicast(_:)`` operator with a ``Passthrough`` to share the same random number to each of two client loops.
    /// Because the upstream iterator only begins after a call to ``connect()``.
    ///
    /// ```
    ///     let stream = AsyncStreams.Passthrough<(String, Int)>()
    ///     let multicastedAsyncSequence = ["First", "Second", "Third"]
    ///         .asyncElements
    ///         .map { ($0, Int.random(in: 0...100)) }
    ///         .handleEvents(onElement: { print("AsyncSequence produces: ($0)") })
    ///         .multicast(stream)
    ///
    ///     Task {
    ///         try await multicastedAsyncSequence
    ///             .collect { print ("Task 1 received: \($0)") }
    ///     }
    ///
    ///     Task {
    ///         try await multicastedAsyncSequence
    ///             .collect { print ("Task 2 received: \($0)") }
    ///     }
    ///
    ///     multicastedAsyncSequence.connect()
    ///
    ///     // will print:
    ///     // AsyncSequence produces: ("First", 78)
    ///     // Stream 2 received: ("First", 78)
    ///     // Stream 1 received: ("First", 78)
    ///     // AsyncSequence produces: ("Second", 98)
    ///     // Stream 2 received: ("Second", 98)
    ///     // Stream 1 received: ("Second", 98)
    ///     // AsyncSequence produces: ("Third", 61)
    ///     // Stream 2 received: ("Third", 61)
    ///     // Stream 1 received: ("Third", 61)
    /// ```
    /// In this example, the output shows that the upstream async sequence produces each random value only one time, and then sends the value to both client loops.
    ///
    /// - Parameter stream: A `Stream` to deliver elements to downstream client loops.
    func multicast<S: Stream>(_ stream: S) -> AsyncMulticastSequence<Self, S> where S.Element == Element {
        AsyncMulticastSequence(upstreamAsyncSequence: self, downstreamStream: stream)
    }
}

public class AsyncMulticastSequence<UpstreamAsyncSequence: AsyncSequence, DownstreamStream: Stream>: AsyncSequence
where UpstreamAsyncSequence.Element == DownstreamStream.Element {
    public typealias Element = UpstreamAsyncSequence.Element
    public typealias AsyncIterator = Iterator

    var upstreamAsyncSequenceRegulator: ConcurrentAccessRegulator<UpstreamAsyncSequence>
    let downstreamStream: DownstreamStream
    let connectedGate = AsyncStreams.Replay<Void>(bufferSize: 1)
    var isConnected = false

    public init(upstreamAsyncSequence: UpstreamAsyncSequence, downstreamStream: DownstreamStream) {
        self.upstreamAsyncSequenceRegulator = ConcurrentAccessRegulator(upstreamAsyncSequence, onNext: { element in
            if let nonNilElement = element {
                downstreamStream.send(nonNilElement)
            } else {
                downstreamStream.send(termination: .finished)
            }
        }, onError: { error in
            downstreamStream.send(termination: .failure(error))
        }, onCancel: {
            downstreamStream.send(termination: .finished)
        })
        self.downstreamStream = downstreamStream
    }

    /// Automates the process of connecting the multicasted async sequence.
    ///
    ///```
    ///     let stream = AsyncStreams.Passthrough<(String, Int)>()
    ///     let multicastedAsyncSequence = ["First", "Second", "Third"]
    ///         .asyncElements
    ///         .multicast(stream)
    ///         .autoconnect()
    ///
    ///     try await multicastedAsyncSequence
    ///         .collect { print ("received: \($0)") }
    ///
    ///      // will print:
    ///      // received: First
    ///      // received: Second
    ///      // received: Third
    ///
    /// - Returns: A `AsyncMulticastSequence` which automatically connects.
    public func autoconnect() -> Self {
        self.isConnected = true
        return self
    }

    /// Allow the `AsyncIterator` to produce elements.
    public func connect() {
        self.connectedGate.send(())
    }

    public func makeAsyncIterator() -> AsyncIterator {
        return Iterator(
            upstreamAsyncSequenceRegulator: self.upstreamAsyncSequenceRegulator,
            downstreamStreamIterator: self.downstreamStream.makeAsyncIterator(),
            connectedGateIterator: self.connectedGate.makeAsyncIterator(),
            isConnected: self.isConnected
        )
    }

    public struct Iterator: AsyncIteratorProtocol {
        let upstreamAsyncSequenceRegulator: ConcurrentAccessRegulator<UpstreamAsyncSequence>
        var downstreamStreamIterator: DownstreamStream.AsyncIterator
        var connectedGateIterator: AsyncStreams.Replay<Void>.AsyncIterator
        var isConnected: Bool

        public mutating func next() async throws -> Element? {
            guard !Task.isCancelled else { return nil }

            if !self.isConnected {
                try await self.connectedGateIterator.next()
                self.isConnected = true
            }

            await self.upstreamAsyncSequenceRegulator.requestNextIfAvailable()
            return try await self.downstreamStreamIterator.next()
        }
    }
}
