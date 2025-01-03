//
//  AsyncThrowingBufferedChannel.swift
//
//
//  Created by Thibault Wittemberg on 07/01/2022.
//

import Atomics
import DequeModule
import OrderedCollections

/// A channel for sending elements from one task to another.
///
/// The `AsyncThrowingBufferedChannel` class is intended to be used as a communication type between tasks,
/// particularly when one task produces values and another task consumes those values. The values are
/// buffered awaiting a consumer to consume them from iteration.
/// `finish()` and `fail()` induce a terminal state and no further elements can be sent.
///
/// ```swift
/// let channel = AsyncThrowingBufferedChannel<Int, Error>()
///
/// Task {
///   do {
///     for try await element in channel {
///       print(element) // will print 1, 2, 3
///     }
///   } catch {
///     print(error) // will catch MyError
///   }
/// }
///
/// sut.send(1)
/// sut.send(2)
/// sut.send(3)
/// sut.fail(MyError())
/// ```
public final class AsyncThrowingBufferedChannel<Element, Failure: Error>: AsyncSequence, Sendable where Element: Sendable {
  public typealias Element = Element
  public typealias AsyncIterator = Iterator

  enum Termination: Sendable {
    case finished
    case failure(Failure)
  }

  struct Awaiting: Hashable {
    let id: Int
    let continuation: UnsafeContinuation<Element?, Error>?

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
    case finish([Awaiting])
    case fail([Awaiting], Error)
    case nothing
  }

  enum AwaitingDecision {
    case resume(Element?)
    case fail(Error)
    case suspend
  }

  enum Value {
    case element(Element)
    case termination(Termination)
  }

  enum State: @unchecked Sendable {
    case idle
    case queued(Deque<Value>)
    case awaiting([Awaiting])
    case terminated(Termination)

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
        case .terminated:
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
        case (.idle, .termination(let termination)):
          state = .terminated(termination)
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
        case (.awaiting(let awaitings), .termination(.failure(let error))):
          state = .terminated(.failure(error))
          return .fail(Array(awaitings), error)
        case (.awaiting(let awaitings), .termination(.finished)):
          state = .terminated(.finished)
          return .finish(Array(awaitings))
        case (.terminated, _):
          return .nothing
      }
    }

    switch decision {
      case .nothing:
        break
      case .finish(let awaitings):
        awaitings.forEach { $0.continuation?.resume(returning: nil) }
      case .fail(let awaitings, let error):
        awaitings.forEach { $0.continuation?.resume(throwing: error) }
      case let .resume(awaiting, element):
        awaiting.continuation?.resume(returning: element)
    }
  }

  public func send(_ element: Element) {
    self.send(.element(element))
  }

  public func fail(_ error: Failure) where Failure == Error {
    self.send(.termination(.failure(error)))
  }

  public func finish() {
    self.send(.termination(.finished))
  }

  func next(onSuspend: (() -> Void)? = nil) async throws -> Element? {
    let awaitingId = self.generateId()
    let cancellation = ManagedAtomic<Bool>(false)

    return try await withTaskCancellationHandler {
      try await withUnsafeThrowingContinuation { [state] (continuation: UnsafeContinuation<Element?, Error>) in
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
                case .termination(.finished):
                  state = .terminated(.finished)
                  return .resume(nil)
                case .termination(.failure(let error)):
                  state = .terminated(.failure(error))
                  return .fail(error)
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
            case .terminated(.finished):
              return .resume(nil)
            case .terminated(.failure(let error)):
              return .fail(error)
          }
        }

        switch decision {
          case .resume(let element): continuation.resume(returning: element)
          case .fail(let error): continuation.resume(throwing: error)
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
    let channel: AsyncThrowingBufferedChannel<Element, Failure>

    var hasBufferedElements: Bool {
      self.channel.hasBufferedElements
    }

    public func next() async throws -> Element? {
      try await self.channel.next()
    }
  }
}
