//
//  AsyncThrowingReplaySubject.swift
//
//
//  Created by Thibault Wittemberg on 31/12/2021.
//

/// An `AsyncThrowingReplaySubject` is an async sequence in which one can send values over time.
/// Values are buffered in a FIFO fashion so they can be replayed by new consumers.
/// When the `bufferSize` is outreached the oldest value is dropped.
/// When the `AsyncThrowingReplaySubject` is terminated, new consumers will
/// immediately resume with this termination, whether it is a finish or a failure.
///
/// ```
/// let replay = AsyncThrowingReplaySubject<Int, Error>(bufferSize: 3)
///
/// for i in (1...5) { replay.send(i) }
/// replay.senf(.failure(error))
///
/// for try await element in replay {
///   print(element) // will print 3, 4, 5 and throw
/// }
/// ```
public final class AsyncThrowingReplaySubject<Element, Failure: Error>: AsyncSubject where Element: Sendable {
  public typealias Element = Element
  public typealias Failure = Failure
  public typealias AsyncIterator = Iterator

  struct State {
    var terminalState: Termination<Failure>?
    var bufferSize: UInt
    var buffer: [Element]
    var channels: [Int: AsyncThrowingBufferedChannel<Element, Error>]
    var ids: Int
  }

  let state: ManagedCriticalState<State>

  public init(bufferSize: UInt) {
    self.state = ManagedCriticalState(
      State(terminalState: nil, bufferSize: bufferSize, buffer: [], channels: [:], ids: 0)
    )
  }

  /// Sends a value to all consumers
  /// - Parameter element: the value to send
  public func send(_ element: Element) {
    self.state.withCriticalRegion { state in
      if state.buffer.count >= state.bufferSize && !state.buffer.isEmpty {
        state.buffer.removeFirst()
      }
      state.buffer.append(element)
      for channel in state.channels.values {
        channel.send(element)
      }
    }
  }

  /// Finishes the subject with either a normal ending or an error.
  /// - Parameter termination: The termination to finish the subject
  public func send(_ termination: Termination<Failure>) {
    self.state.withCriticalRegion { state in
      state.terminalState = termination
      let channels = Array(state.channels.values)
      state.channels.removeAll()
      state.buffer.removeAll()
      state.bufferSize = 0
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

    let (terminalState, elements) = self.state.withCriticalRegion { state in
      (state.terminalState, state.buffer)
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

    for element in elements {
      asyncBufferedChannel.send(element)
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

    init(asyncSubject: AsyncThrowingReplaySubject) {
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
