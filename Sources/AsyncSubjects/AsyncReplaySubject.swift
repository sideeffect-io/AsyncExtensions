//
//  AsyncReplaySubject.swift
//  
//
//  Created by Thibault Wittemberg on 31/12/2021.
//

/// An `AsyncReplaySubject` is an async sequence in which one can send values over time.
/// Values are buffered in a FIFO fashion so they can be replayed by new consumers.
/// When the `bufferSize` is outreached the oldest value is dropped.
/// When the `AsyncReplaySubject` is terminated, new consumers will
/// immediately resume with this termination, whether it is a finish or a failure.
///
/// ```
/// let replay = AsyncReplaySubject<Int>(bufferSize: 3)
///
/// for i in (1...5) { replay.send(i) }
///
/// for await element in replay {
///   print(element) // will print 3, 4, 5
/// }
/// ```
public final class AsyncReplaySubject<Element>: AsyncSubject where Element: Sendable {
  public typealias Element = Element
  public typealias Failure = Never
  public typealias AsyncIterator = Iterator

  struct State {
    var terminalState: Termination<Failure>?
    var bufferSize: UInt
    var buffer: [Element]
    var channels: [Int: AsyncBufferedChannel<Element>]
    var ids: Int
  }

  let state: ManagedCriticalState<State>

  /// Creates a replay subject with a buffer of replayable values
  /// - Parameter bufferSize: the number of values that will be replayed to new consumers
  public init(bufferSize: UInt) {
    self.state = ManagedCriticalState(
      State(terminalState: nil, bufferSize: bufferSize, buffer: [], channels: [:], ids: 0)
    )
  }

  /// Sends a value to all consumers
  /// - Parameter element: the value to send
  public func send(_ element: Element) {
    let channels = self.state.withCriticalRegion { state -> [AsyncBufferedChannel<Element>] in
      if state.buffer.count >= state.bufferSize && !state.buffer.isEmpty {
        state.buffer.removeFirst()
      }
      state.buffer.append(element)
      return Array(state.channels.values)
    }

    for channel in channels {
      channel.send(element)
    }
  }

  /// Finishes the subject with a normal ending.
  /// - Parameter termination: The termination to finish the subject.
  public func send(_ termination: Termination<Failure>) {
    let channels = self.state.withCriticalRegion { state -> [AsyncBufferedChannel<Element>] in
      state.terminalState = termination
      let channels = Array(state.channels.values)
      state.channels.removeAll()
      state.buffer.removeAll()
      state.bufferSize = 0
      return channels
    }

    for channel in channels {
      channel.finish()
    }
  }

  func handleNewConsumer() -> (iterator: AsyncBufferedChannel<Element>.Iterator, unregister: @Sendable () -> Void) {
    let asyncBufferedChannel = AsyncBufferedChannel<Element>()
    var consumerId: Int!
    var unregister: (@Sendable () -> Void)?

    self.state.withCriticalRegion { state in
      let terminalState = state.terminalState
      if let terminalState, terminalState.isFinished {
        asyncBufferedChannel.finish()
      } else {
        for element in state.buffer {
          asyncBufferedChannel.send(element)
        }
        state.ids &+= 1
        consumerId = state.ids
        state.channels[consumerId] = asyncBufferedChannel
      }
    }

    if let consumerId {
      unregister = { @Sendable [state, consumerId] in
        state.withCriticalRegion { state in
          state.channels[consumerId] = nil
        }
      }
    }

    return (asyncBufferedChannel.makeAsyncIterator(), unregister ?? {})
  }

  public func makeAsyncIterator() -> AsyncIterator {
    Iterator(asyncSubject: self)
  }

  public struct Iterator: AsyncSubjectIterator {
    var iterator: AsyncBufferedChannel<Element>.Iterator
    let unregister: @Sendable () -> Void
    // unregisters the consumer when the last copy of this iterator goes, however it stopped
    private let registration: AsyncSubjectRegistration
    var isFinished = false

    init(asyncSubject: AsyncReplaySubject) {
      (self.iterator, self.unregister) = asyncSubject.handleNewConsumer()
      registration = AsyncSubjectRegistration(unregister)
    }

    public var hasBufferedElements: Bool {
      self.iterator.hasBufferedElements
    }

    public mutating func next() async -> Element? {
      // Don't proceed if we've already finished
      guard !isFinished else { return nil }

      let result = await withTaskCancellationHandler {
        await self.iterator.next()
      } onCancel: { [unregister] in
        unregister()
      }

      // If iteration completed normally (returned nil), unregister the channel
      if result == nil {
        isFinished = true
        unregister()
      }

      return result
    }
  }
}
