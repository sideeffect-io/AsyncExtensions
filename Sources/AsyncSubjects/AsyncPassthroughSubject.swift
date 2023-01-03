//
//  AsyncPassthroughSubject.swift
//
//
//  Created by Thibault Wittemberg on 07/01/2022.
//

/// An `AsyncPassthroughSubject` is an async sequence in which one can send values over time.
/// When the `AsyncPassthroughSubject` is terminated, new consumers will
/// immediately resume with this termination.
///
/// ```
/// let passthrough = AsyncPassthroughSubject<Int>()
///
/// Task {
///   for await element in passthrough {
///     print(element) // will print 1 2
///   }
/// }
///
/// Task {
///   for await element in passthrough {
///     print(element) // will print 1 2
///   }
/// }
///
/// ... later in the application flow
///
/// passthrough.send(1)
/// passthrough.send(2)
/// passthrough.send(.finished)
/// ```
public final class AsyncPassthroughSubject<Element>: AsyncSubject {
  public typealias Element = Element
  public typealias Failure = Never
  public typealias AsyncIterator = Iterator

  struct State {
    var terminalState: Termination<Never>?
    var channels: [Int: AsyncBufferedChannel<Element>]
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
    self.state.withCriticalRegion { state in
      for channel in state.channels.values {
        channel.send(element)
      }
    }
  }

  /// Finishes the subject with a normal ending.
  /// - Parameter termination: The termination to finish the subject
  public func send(_ termination: Termination<Failure>) {
    self.state.withCriticalRegion { state in
      state.terminalState = termination
      let channels = Array(state.channels.values)
      state.channels.removeAll()
      for channel in channels {
        channel.finish()
      }
    }
  }

  func handleNewConsumer() -> (iterator: AsyncBufferedChannel<Element>.Iterator, unregister: @Sendable () -> Void) {
    let asyncBufferedChannel = AsyncBufferedChannel<Element>()

    let terminalState = self.state.withCriticalRegion { state in
      state.terminalState
    }

    if let terminalState = terminalState, terminalState.isFinished {
      asyncBufferedChannel.finish()
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
    var iterator: AsyncBufferedChannel<Element>.Iterator
    let unregister: @Sendable () -> Void

    init(asyncSubject: AsyncPassthroughSubject) {
      (self.iterator, self.unregister) = asyncSubject.handleNewConsumer()
    }

    public var hasBufferedElements: Bool {
      self.iterator.hasBufferedElements
    }

    public mutating func next() async -> Element? {
      await withTaskCancellationHandler {
        await self.iterator.next()
      } onCancel: { [unregister] in
        unregister()
      }
    }
  }
}
