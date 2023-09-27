//
//  AsyncThrowingCurrentValueSubject.swift
//
//
//  Created by Thibault Wittemberg on 07/01/2022.
//

/// An`AsyncThrowingCurrentValueSubject` is an async sequence in which one can send values over time.
/// The current value is always accessible as an instance variable.
/// The current value is replayed in any new async for in loops.
/// When the `AsyncThrowingCurrentValueSubject` is terminated, new consumers will
/// immediately resume with this termination, whether it is a finish or a failure.
///
/// ```
/// let currentValue = AsyncThrowingCurrentValueSubject<Int, Error>(1)
///
/// Task {
///   for try await element in currentValue {
///     print(element) // will print 1 2 and throw
///   }
/// }
///
/// Task {
///   for try await element in currentValue {
///     print(element) // will print 1 2 and throw
///   }
/// }
///
/// .. later in the application flow
///
/// await currentValue.send(2)
///
/// print(currentValue.element) // will print 2
/// await currentValue.send(.failure(error))
///
/// ```
public final class AsyncThrowingCurrentValueSubject<Element, Failure: Error>: AsyncSubject where Element: Sendable {
  public typealias Element = Element
  public typealias Failure = Failure
  public typealias AsyncIterator = Iterator

  struct State {
    var terminalState: Termination<Failure>?
    var current: Element
    var channels: [Int: AsyncThrowingBufferedChannel<Element, Error>]
    var ids: Int
  }

  let state: ManagedCriticalState<State>

  public var value: Element {
    get {
      self.state.criticalState.current
    }

    set {
      self.send(newValue)
    }
  }

  public init(_ element: Element) {
    self.state = ManagedCriticalState(
      State(terminalState: nil, current: element, channels: [:], ids: 0)
    )
  }

  /// Sends a value to all consumers
  /// - Parameter element: the value to send
  public func send(_ element: Element) {
    self.state.withCriticalRegion { state in
      state.current = element
      for channel in state.channels.values {
        channel.send(element)
      }
    }
  }

  /// Finishes the subject with either a normal ending or an error.
  /// - Parameter termination: The termination to finish the subject.
  public func send(_ termination: Termination<Failure>) {
    self.state.withCriticalRegion { state in
      state.terminalState = termination
      let channels = Array(state.channels.values)
      state.channels.removeAll()
      for channel in channels {
        switch termination {
          case .finished:
            channel.finish()
          case .failure(let error):
            channel.fail(error)
        }
      }
    }
  }

  func handleNewConsumer(
  ) -> (iterator: AsyncThrowingBufferedChannel<Element, Error>.Iterator, unregister: @Sendable () -> Void) {
    let asyncBufferedChannel = AsyncThrowingBufferedChannel<Element, Error>()

    let (terminalState, current) = self.state.withCriticalRegion { state -> (Termination?, Element) in
      (state.terminalState, state.current)
    }

    if let terminalState = terminalState {
      switch terminalState {
        case .finished:
          asyncBufferedChannel.finish()
        case .failure(let error):
          asyncBufferedChannel.fail(error)
      }
      return (asyncBufferedChannel.makeAsyncIterator(), {})
    }

    asyncBufferedChannel.send(current)

    let consumerId = self.state.withCriticalRegion { state -> Int in
      state.ids += 1
      state.channels[state.ids] = asyncBufferedChannel
      return state.ids
    }

    let unregister = { @Sendable [state] in
      state.withCriticalRegion { state in
        state.channels[consumerId] = nil
      }
    }

    return (asyncBufferedChannel.makeAsyncIterator(), unregister)
  }

  public func makeAsyncIterator() -> AsyncIterator {
    Iterator(asyncSubject: self)
  }

  public struct Iterator: AsyncSubjectIterator {
    var iterator: AsyncThrowingBufferedChannel<Element, Error>.Iterator
    let unregister: @Sendable () -> Void

    init(asyncSubject: AsyncThrowingCurrentValueSubject) {
      (self.iterator, self.unregister) = asyncSubject.handleNewConsumer()
    }

    public var hasBufferedElements: Bool {
      self.iterator.hasBufferedElements
    }

    public mutating func next() async throws -> Element? {
      try await withTaskCancellationHandler {
        try await self.iterator.next()
      } onCancel: { [unregister] in
        unregister()
      }
    }
  }
}
