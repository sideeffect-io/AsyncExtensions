//
//  AsyncThrowingPassthroughSubject.swift
//
//
//  Created by Thibault Wittemberg on 07/01/2022.
//

/// An `AsyncThrowingPassthroughSubject` is an async sequence in which one can send values over time.
/// When the `AsyncThrowingPassthroughSubject` is terminated, new consumers will
/// immediately resume with this termination, whether it is a finish or a failure.
///
/// ```
/// let passthrough = AsyncThrowingPassthroughSubject<Int, Error>()
///
/// Task {
///   for try await element in passthrough {
///     print(element) // will print 1 2 and throw
///   }
/// }
///
/// Task {
///   for try await element in passthrough {
///     print(element) // will print 1 2 and throw
///   }
/// }
///
/// ... later in the application flow
///
/// passthrough.send(1)
/// passthrough.send(2)
/// passthrough.send(.failure(error))
/// ```
///
public final class AsyncThrowingPassthroughSubject<Element, Failure: Error>: AsyncSubject where Element: Sendable {
  public typealias Element = Element
  public typealias Failure = Failure
  public typealias AsyncIterator = Iterator

  struct State {
    var terminalState: Termination<Failure>?
    var channels: [Int: AsyncThrowingBufferedChannel<Element, Error>]
    var ids: Int
  }

  let state: ManagedCriticalState<State>

  public init() {
    self.state = ManagedCriticalState(
      State(terminalState: nil, channels: [:], ids: 0)
    )
  }

  /// Sends a value to all consumers
  /// - Parameter element: the value to send
  public func send(_ element: Element) {
    let channels = self.state.withCriticalRegion { state in
      state.channels.values
    }

    for channel in channels {
      channel.send(element)
    }
  }

  /// Finishes the subject with either a normal ending or an error.
  /// - Parameter termination: The termination to finish the subject
  public func send(_ termination: Termination<Failure>) {
    let channels = self.state.withCriticalRegion { state -> [AsyncThrowingBufferedChannel<Element, Error>] in
      state.terminalState = termination
      let channels = Array(state.channels.values)
      state.channels.removeAll()
      return channels
    }

    for channel in channels {
      switch termination {
        case .finished:
          channel.finish()
        case .failure(let error):
          channel.fail(error)
      }
    }
  }

  func handleNewConsumer(
  ) -> (iterator: AsyncThrowingBufferedChannel<Element, Error>.Iterator, unregister: @Sendable () -> Void) {
    let asyncBufferedChannel = AsyncThrowingBufferedChannel<Element, Error>()

    let terminalState = self.state.withCriticalRegion { state in
      state.terminalState
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

    init(asyncSubject: AsyncThrowingPassthroughSubject) {
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
