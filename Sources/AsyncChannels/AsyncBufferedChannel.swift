//
//  AsyncBufferedChannel.swift
//
//
//  Created by Thibault Wittemberg on 07/01/2022.
//

import Atomics
import DequeModule
import OrderedCollections

/// A channel for sending elements from one task to another.
///
/// The `AsyncBufferedChannel` class is intended to be used as a communication type between tasks,
/// particularly when one task produces values and another task consumes those values. The values are
/// buffered awaiting a consumer to consume them from iteration.
/// `finish()` induces a terminal state and no further elements can be sent.
///
/// ```swift
/// let channel = AsyncBufferedChannel<Int>()
///
/// Task {
///   for await element in channel {
///     print(element) // will print 1, 2, 3
///   }
/// }
///
/// sut.send(1)
/// sut.send(2)
/// sut.send(3)
/// sut.finish()
/// ```
public final class AsyncBufferedChannel<Element>: AsyncSequence, Sendable {
  public typealias Element = Element
  public typealias AsyncIterator = Iterator

  struct Awaiting: Hashable {
    let id: Int
    let continuation: UnsafeContinuation<Element?, Never>?

    static func placeHolder(id: Int) -> Awaiting {
      Awaiting(id: id, continuation: nil)
    }

    func hash(into hasher: inout Hasher) {
      hasher.combine(self.id)
    }

    static func == (lhs: Awaiting, rhs: Awaiting) -> Bool {
      lhs.id == rhs.id
    }
  }

  enum SendDecision {
    case resume(Awaiting, Element)
    case terminate([Awaiting])
    case nothing
  }

  enum AwaitingDecision {
    case resume(Element?)
    case suspend
  }

  enum Value {
    case element(Element)
    case termination
  }

  enum State: @unchecked Sendable {
    case idle
    case queued(Deque<Value>)
    case awaiting([Awaiting])
    case finished

    static var initial: State {
      .idle
    }
  }

  let ids: ManagedAtomic<Int>
  let state: ManagedCriticalState<State>

  public init() {
    self.ids = ManagedAtomic(0)
    self.state = ManagedCriticalState(.initial)
  }

  func generateId() -> Int {
    ids.wrappingIncrementThenLoad(by: 1, ordering: .relaxed)
  }

  var hasBufferedElements: Bool {
    self.state.withCriticalRegion { state in
      switch state {
        case .idle:
          return false
        case .queued(let values) where !values.isEmpty:
          return true
        case .awaiting, .queued:
          return false
        case .finished:
          return true
      }
    }
  }

  func send(_ value: Value) {
    let decision = self.state.withCriticalRegion { state -> SendDecision in
      switch (state, value) {
        case (.idle, .element):
          state = .queued([value])
          return .nothing
        case (.idle, .termination):
          state = .finished
          return .nothing
        case (.queued(var values), _):
          values.append(value)
          state = .queued(values)
          return .nothing
        case (.awaiting(var awaitings), .element(let element)):
          let awaiting = awaitings.removeFirst()
          if awaitings.isEmpty {
            state = .idle
          } else {
            state = .awaiting(awaitings)
          }
          return .resume(awaiting, element)
        case (.awaiting(let awaitings), .termination):
          state = .finished
          return .terminate(Array(awaitings))
        case (.finished, _):
          return .nothing
      }
    }
    switch decision {
      case .nothing:
        break
      case .terminate(let awaitings):
        awaitings.forEach { $0.continuation?.resume(returning: nil) }
      case let .resume(awaiting, element):
        awaiting.continuation?.resume(returning: element)
    }
  }

  public func send(_ element: Element) {
    self.send(.element(element))
  }

  public func finish() {
    self.send(.termination)
  }

  func next(onSuspend: (() -> Void)? = nil) async -> Element? {
    let awaitingId = self.generateId()
    let cancellation = ManagedAtomic<Bool>(false)

    return await withTaskCancellationHandler {
      await withUnsafeContinuation { [state] (continuation: UnsafeContinuation<Element?, Never>) in
        let decision = state.withCriticalRegion { state -> AwaitingDecision in
          let isCancelled = cancellation.load(ordering: .acquiring)
          guard !isCancelled else { return .resume(nil) }

          switch state {
            case .idle:
              state = .awaiting([Awaiting(id: awaitingId, continuation: continuation)])
              return .suspend
            case .queued(var values):
              let value = values.popFirst()
              switch value {
                case .termination:
                  state = .finished
                  return .resume(nil)
                case .element(let element) where !values.isEmpty:
                  state = .queued(values)
                  return .resume(element)
                case .element(let element):
                  state = .idle
                  return .resume(element)
                default:
                  state = .idle
                  return .suspend
              }
            case .awaiting(var awaitings):
              let awaiting = Awaiting(id: awaitingId, continuation: continuation)

              if let index = awaitings.firstIndex(where: { $0 == awaiting }) {
                awaitings[index] = awaiting
              } else {
                awaitings.append(awaiting)
              }
              state = .awaiting(awaitings)
              return .suspend
            case .finished:
              return .resume(nil)
          }
        }

        switch decision {
          case .resume(let element): continuation.resume(returning: element)
          case .suspend:
            onSuspend?()
        }
      }
    } onCancel: { [state] in
      let awaiting = state.withCriticalRegion { state -> Awaiting? in
        cancellation.store(true, ordering: .releasing)
        switch state {
          case .awaiting(var awaitings):
            let index = awaitings.firstIndex(where: { $0 == .placeHolder(id: awaitingId) })
            guard let index else { return nil }
            let awaiting = awaitings[index]
            awaitings.remove(at: index)
            if awaitings.isEmpty {
              state = .idle
            } else {
              state = .awaiting(awaitings)
            }
            return awaiting
          default:
            return nil
        }
      }

      awaiting?.continuation?.resume(returning: nil)
    }
  }

  public func makeAsyncIterator() -> AsyncIterator {
    Iterator(
      channel: self
    )
  }

  public struct Iterator: AsyncIteratorProtocol, Sendable {
    let channel: AsyncBufferedChannel<Element>

    var hasBufferedElements: Bool {
      self.channel.hasBufferedElements
    }

    public func next() async -> Element? {
      await self.channel.next()
    }
  }
}
