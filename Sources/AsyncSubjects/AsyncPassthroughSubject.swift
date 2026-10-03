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
public final class AsyncPassthroughSubject<Element: Sendable>: AsyncSubject {
  public typealias Element = Element
  public typealias Failure = Never
  public typealias AsyncIterator = Iterator

  struct State {
    var terminalState: Termination<Never>?
    var channels: [Int: AsyncBufferedChannel<Element>]
    var ids: Int
    var deliveries = SubjectDeliveryQueue()
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
    let shouldDrain = self.state.withCriticalRegion { state in
      let channels = Array(state.channels.values)
      return state.deliveries.enqueue {
        for channel in channels {
          channel.send(element)
        }
      }
    }
    if shouldDrain { self.drainDeliveries() }
  }

  /// Finishes the subject with a normal ending.
  /// - Parameter termination: The termination to finish the subject
  public func send(_ termination: Termination<Failure>) {
    let shouldDrain = self.state.withCriticalRegion { state in
      state.terminalState = termination
      let channels = Array(state.channels.values)
      state.channels.removeAll()
      return state.deliveries.enqueue {
        for channel in channels {
          channel.finish()
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

  func handleNewConsumer() -> (iterator: AsyncBufferedChannel<Element>.Iterator, unregister: @Sendable () -> Void) {
    let asyncBufferedChannel = AsyncBufferedChannel<Element>()

    let consumerId = self.state.withCriticalRegion { state -> Int? in
      if let terminalState = state.terminalState, terminalState.isFinished {
        asyncBufferedChannel.finish()
        return nil
      }

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
    var iterator: AsyncBufferedChannel<Element>.Iterator
    let subscription: SubjectSubscription

    init(asyncSubject: AsyncPassthroughSubject) {
      let consumer = asyncSubject.handleNewConsumer()
      self.iterator = consumer.iterator
      self.subscription = SubjectSubscription(unregister: consumer.unregister)
    }

    public var hasBufferedElements: Bool {
      self.iterator.hasBufferedElements
    }

    public mutating func next() async -> Element? {
      await withTaskCancellationHandler {
        await self.iterator.next()
      } onCancel: { [subscription] in
        subscription.unregister()
      }
    }
  }
}
