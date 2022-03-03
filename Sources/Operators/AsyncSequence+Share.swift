//
//  AsyncSequence+Share.swift
//  
//
//  Created by Thibault Wittemberg on 03/03/2022.
//

public extension AsyncSequence {
    /// Shares the output of an upstream async sequence with multiple client loops.
    ///
    ///  - Tip: ``share()`` is effectively a shortcut for ``multicast()`` using a ``Passthrough`` stream, with an implicit ``autoconnect()``.
    ///
    /// The following example uses an async sequence as a counter to emit three random numbers. Each element is delayed by 1s to give the seconf loop a chance to
    /// catch all the values.
    ///
    /// ```
    ///     let sharedAsyncSequence = AsyncSequences.From(["first", "second", "third"], interval: .seconds(1))
    ///         .map { ($0, Int.random(in: 0...100)) }
    ///         .handleEvents(onElement: { print("AsyncSequence produces: \($0)") })
    ///         .share()
    ///
    ///     Task {
    ///         try await sharedAsyncSequence
    ///             .collect { print ("Task 1 received: \($0)") }
    ///     }
    ///
    ///     Task {
    ///         try await sharedAsyncSequence
    ///             .collect { print ("Task 2 received: \($0)") }
    ///     }
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
    /// Without the ``share()`` operator, loop 1 receives three random values, followed by loop 2 receiving three different random values.
    ///
    /// Also note that ``AsyncShareSequence`` is a class rather than a structure like most other publishers.
    /// This means you can use this operator to create a publisher instance that uses reference semantics.
    /// - Returns: A class instance that shares elements received from its upstream async sequence to multiple client loops.
    func share() -> AsyncSequences.AsyncShareSequence<Self> {
        let stream = AsyncStreams.Passthrough<Element>()
        return self.multicast(stream).autoconnect()
    }
}

extension AsyncSequences {
    public typealias AsyncShareSequence<UpstreamAsyncSequence: AsyncSequence> =
    AsyncMulticastSequence<UpstreamAsyncSequence,AsyncStreams.Passthrough<UpstreamAsyncSequence.Element>>
}
