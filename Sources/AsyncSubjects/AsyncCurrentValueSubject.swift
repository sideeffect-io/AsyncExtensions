//
//  AsyncCurrentValueSubject.swift
//  
//
//  Created by Thibault Wittemberg on 07/01/2022.
//

/// A n`AsyncCurrentValueSubject` is an async sequence in which one can send values over time.
/// The current value is always accessible as an instance variable.
/// The current value is replayed in any new async for in loops.
/// When the `AsyncCurrentValueSubject` is terminated, new consumers will
/// immediately resume with this termination.
/// 
/// ```
/// let currentValue = AsyncCurrentValueSubject<Int>(1)
///
/// Task {
///   for await element in currentValue {
///     print(element) // will print 1 2
///   }
/// }
///
/// Task {
///   for await element in currentValue {
///     print(element) // will print 1 2
///   }
/// }
///
/// .. later in the application flow
///
/// await currentValue.send(2)
///
/// print(currentValue.element) // will print 2
/// ```
public final class AsyncCurrentValueSubject<Element>: AsyncSubject where Element: Sendable {
  public typealias Element = Element
  public typealias Failure = Never
  public typealias AsyncIterator = Iterator

  struct State: Sendable {
    var terminalState: Termination<Failure>?
    var current: Element
    var channels: [Int: AsyncBufferedChannel<Element>]
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

  /// Creates an AsyncCurrentValueSubject with a current element
  /// - Parameter element: the current element
  public init(_ element: Element) {
    self.state = ManagedCriticalState(
      State(terminalState: nil, current: element, channels: [:], ids: 0)
    )
  }

  /// Sends a value to all consumers
  /// - Parameter element: the value to send
  public func send(_ element: Element) {
    let channels = self.state.withCriticalRegion { state -> [AsyncBufferedChannel<Element>] in
      state.current = element
      return Array(state.channels.values)
    }

    for channel in channels {
      channel.send(element)
    }
  }

  /// Finishes the async sequences with a normal ending.
  /// - Parameter termination: The termination to finish the subject.
  public func send(_ termination: Termination<Failure>) {
    let channels = self.state.withCriticalRegion { state -> [AsyncBufferedChannel<Element>] in
      state.terminalState = termination
      let channels = Array(state.channels.values)
      state.channels.removeAll()
      return channels
    }

    for channel in channels {
      channel.finish()
    }
  }

  func handleNewConsumer() -> (iterator: AsyncBufferedChannel<Element>.Iterator, unregister: @Sendable () -> Void) {
    let asyncBufferedChannel = AsyncBufferedChannel<Element>()

    let (terminalState, current) = self.state.withCriticalRegion { state -> (Termination?, Element) in
      (state.terminalState, state.current)
    }

    if let terminalState = terminalState, terminalState.isFinished {
      asyncBufferedChannel.finish()
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
    var iterator: AsyncBufferedChannel<Element>.Iterator
    let unregister: @Sendable () -> Void

    init(asyncSubject: AsyncCurrentValueSubject) {
      (self.iterator, self.unregister) = asyncSubject.handleNewConsumer()
    }

    public var hasBufferedElements: Bool {
      self.iterator.hasBufferedElements
    }

    public mutating func next() async -> Element? {
      await withTaskCancellationHandler { [unregister] in
        unregister()
      } operation: {
        await self.iterator.next()
      }
    }
  }
}
