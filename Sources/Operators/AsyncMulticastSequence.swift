//
//  AsyncSequence+Multicast.swift
//
//
//  Created by Thibault Wittemberg on 21/02/2022.
//

public extension AsyncSequence {
  /// Use multicast  when you have multiple client iterations, but you want the base async sequence
  /// to only produce a single `AsyncIterator`.
  /// This is useful when upstream async sequences are doing expensive work you don’t want to duplicate,
  /// like performing network requests.
  ///
  /// The following example uses an async sequence as a counter to emit three random numbers.
  /// It uses a ``AsyncSequence/multicast(_:)`` operator with a ``AsyncThrowingPassthroughSubject`
  /// to share the same random number to each of two client loops.
  /// Because the upstream iterator only begins after a call to ``connect()``.
  ///
  /// ```
  /// let stream = AsyncThrowingPassthroughSubject<(String, Int), Error>()
  /// let multicastedAsyncSequence = ["First", "Second", "Third"]
  ///   .async
  ///   .map { ($0, Int.random(in: 0...100)) }
  ///   .handleEvents(onElement: { print("AsyncSequence produces: \($0)") })
  ///   .multicast(stream)
  ///
  /// Task {
  ///   try await multicastedAsyncSequence.collect { print ("Task 1 received: \($0)") }
  /// }
  ///
  /// Task {
  ///   try await multicastedAsyncSequence.collect { print ("Task 2 received: \($0)") }
  /// }
  ///
  /// multicastedAsyncSequence.connect()
  ///
  /// // will print:
  /// // AsyncSequence produces: ("First", 78)
  /// // Stream 2 received: ("First", 78)
  /// // Stream 1 received: ("First", 78)
  /// // AsyncSequence produces: ("Second", 98)
  /// // Stream 2 received: ("Second", 98)
  /// // Stream 1 received: ("Second", 98)
  /// // AsyncSequence produces: ("Third", 61)
  /// // Stream 2 received: ("Third", 61)
  /// // Stream 1 received: ("Third", 61)
  /// ```
  /// In this example, the output shows that the upstream async sequence produces each random value only one time,
  /// and then sends the value to both client loops.
  ///
  /// - Parameter subject: An `AsyncSubject` to deliver elements to downstream client loops.
  func multicast<S: AsyncSubject>(_ subject: S) -> AsyncMulticastSequence<Self, S>
  where S.Element == Element, S.Failure == Error {
    AsyncMulticastSequence(self, subject: subject)
  }
}

public final class AsyncMulticastSequence<Base: AsyncSequence, Subject: AsyncSubject>: AsyncSequence, Sendable
where Base.Element == Subject.Element, Subject.Failure == Error, Base.AsyncIterator: Sendable {
  public typealias Element = Base.Element
  public typealias AsyncIterator = Iterator

  enum State {
    case available(Base.AsyncIterator)
    case busy
  }

  let state: ManagedCriticalState<State>
  let subject: Subject

  let connectedGate = AsyncReplaySubject<Void>(bufferSize: 1)
  let isConnected = ManagedCriticalState<Bool>(false)

  public init(_ base: Base, subject: Subject) {
    self.state = ManagedCriticalState(.available(base.makeAsyncIterator()))
    self.subject = subject
  }

  /// Automates the process of connecting the multicasted async sequence.
  ///
  /// ```
  /// let stream = AsyncPassthroughSubject<(String, Int)>()
  /// let multicastedAsyncSequence = ["First", "Second", "Third"]
  ///     .async
  ///     .multicast(stream)
  ///     .autoconnect()
  ///
  /// try await multicastedAsyncSequence
  ///     .collect { print ("received: \($0)") }
  ///
  /// // will print:
  /// // received: First
  /// // received: Second
  /// // received: Third
  ///
  /// - Returns: A `AsyncMulticastSequence` which automatically connects.
  public func autoconnect() -> Self {
    self.isConnected.apply(criticalState: true)
    return self
  }

  /// Allow the `AsyncIterator` to produce elements.
  public func connect() {
    self.connectedGate.send(())
  }

  func next() async {
    await Task {
      let (canAccessBase, iterator) = self.state.withCriticalRegion { state -> (Bool, Base.AsyncIterator?) in
        switch state {
          case .available(let iterator):
            state = .busy
            return (true, iterator)
          case .busy:
            return (false, nil)
        }
      }

      guard canAccessBase, var iterator = iterator else { return }

      let toSend: Result<Element?, Error>
      do {
        let element = try await iterator.next()
        toSend = .success(element)
      } catch {
        toSend = .failure(error)
      }

      self.state.withCriticalRegion { state in
        state = .available(iterator)
      }

      switch toSend {
        case .success(.some(let element)): self.subject.send(element)
        case .success(.none): self.subject.send(.finished)
        case .failure(let error): self.subject.send(.failure(error))
      }
    }.value
  }

  public func makeAsyncIterator() -> AsyncIterator {
    return Iterator(
      asyncMulticastSequence: self,
      subjectIterator: self.subject.makeAsyncIterator(),
      connectedGateIterator: self.connectedGate.makeAsyncIterator(),
      isConnected: self.isConnected
    )
  }

  public struct Iterator: AsyncIteratorProtocol, Sendable {
    let asyncMulticastSequence: AsyncMulticastSequence<Base, Subject>
    var subjectIterator: Subject.AsyncIterator

    var connectedGateIterator: AsyncReplaySubject<Void>.AsyncIterator
    let isConnected: ManagedCriticalState<Bool>

    public mutating func next() async rethrows -> Element? {
      guard !Task.isCancelled else { return nil }
      
      let shouldWaitForGate = self.isConnected.withCriticalRegion { isConnected -> Bool in
        if !isConnected {
          isConnected = true
          return true
        }
        return false
      }
      if shouldWaitForGate {
        await self.connectedGateIterator.next()
      }

      if !self.subjectIterator.hasBufferedElements {
        await self.asyncMulticastSequence.next()
      }

      let element = try await self.subjectIterator.next()
      return element
    }
  }
}
