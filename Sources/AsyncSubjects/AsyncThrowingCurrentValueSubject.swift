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
    var deliveries = SubjectDeliveryQueue()
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
    let shouldDrain = self.state.withCriticalRegion { state in
      state.current = element
      let channels = Array(state.channels.values)
      return state.deliveries.enqueue {
        for channel in channels {
          channel.send(element)
        }
      }
    }
    if shouldDrain { self.drainDeliveries() }
  }

  /// Finishes the subject with either a normal ending or an error.
  /// - Parameter termination: The termination to finish the subject.
  public func send(_ termination: Termination<Failure>) {
    let shouldDrain = self.state.withCriticalRegion { state in
      state.terminalState = termination
      let channels = Array(state.channels.values)
      state.channels.removeAll()
      return state.deliveries.enqueue {
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
    if shouldDrain { self.drainDeliveries() }
  }

  func drainDeliveries() {
    while let delivery = self.state.withCriticalRegion({ $0.deliveries.next() }) {
      // Continuation resumption must not hold a lock needed by cancellation,
      // including a cancellation handler that sends back into this subject.
      delivery()
    }
  }

  func handleNewConsumer(
  ) -> (iterator: AsyncThrowingBufferedChannel<Element, Error>.Iterator, unregister: @Sendable () -> Void) {
    let asyncBufferedChannel = AsyncThrowingBufferedChannel<Element, Error>()

    let consumerId = self.state.withCriticalRegion { state -> Int? in
      if let terminalState = state.terminalState {
        switch terminalState {
          case .finished:
            asyncBufferedChannel.finish()
          case .failure(let error):
            asyncBufferedChannel.fail(error)
        }
        return nil
      }

      asyncBufferedChannel.send(state.current)

      state.ids += 1
      state.channels[state.ids] = asyncBufferedChannel
      return state.ids
    }

    guard let consumerId = consumerId else {
      return (asyncBufferedChannel.makeAsyncIterator(), {})
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
