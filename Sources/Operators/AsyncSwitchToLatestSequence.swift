//
//  AsyncSwitchToLatestSequence.swift
//  
//
//  Created by Thibault Wittemberg on 04/01/2022.
//

public extension AsyncSequence where Element: AsyncSequence {
  /// Republishes elements sent by the most recently received async sequence.
  ///
  /// ```
  /// let sourceSequence = AsyncSequences.From([1, 2, 3])
  /// let mappedSequence = sourceSequence.map { element in ["a\(element)", "b\(element)"].async }
  /// let switchedSequence = mappedSequence.switchToLatest()
  ///
  /// for try await element in switchedSequence {
  ///     print(element)
  /// }
  ///
  /// // will print:
  /// a3, b3
  /// ```
  ///
  /// - Returns: The async sequence that republishes elements sent by the most recently received async sequence.
  func switchToLatest() -> AsyncSwitchToLatestSequence<Self> where Self.Element.Element: Sendable {
    AsyncSwitchToLatestSequence<Self>(self)
  }
}

public struct AsyncSwitchToLatestSequence<Base: AsyncSequence>: AsyncSequence
where Base.Element: AsyncSequence, Base: Sendable, Base.Element.Element: Sendable, Base.Element.AsyncIterator: Sendable {
  public typealias Element = Base.Element.Element
  public typealias AsyncIterator = Iterator

  let base: Base

  init(_ base: Base) {
    self.base = base
  }

  public func makeAsyncIterator() -> Iterator {
    Iterator(self.base)
  }

  public struct Iterator: AsyncIteratorProtocol {
    enum BaseState {
      case notStarted
      case idle
      case waitingForChildIterator(UnsafeContinuation<Task<ChildValue?, Never>?, Never>)
      case newChildIteratorAvailable(Result<Base.Element.AsyncIterator, Error>)
      case processingChildIterator(Result<Base.Element.AsyncIterator, Error>)
      case finished(Result<Base.Element.AsyncIterator, Error>?)
      case failed(Error)

      var isFinished: Bool {
        if case .finished = self {
          return true
        }
        return false
      }

      var isNewAvailableChildIterator: Bool {
        if case .newChildIteratorAvailable = self {
          return true
        }
        return false
      }

      var childIterator: Result<Base.Element.AsyncIterator, Error>? {
        switch self {
          case
              .newChildIteratorAvailable(let childIterator),
              .processingChildIterator(let childIterator):
            return childIterator
          case .finished(let childIterator):
            return childIterator
          case .failed(let error):
            return .failure(error)
          default:
            return nil
        }
      }
    }

    struct State {
      var childTask: Task<ChildValue?, Never>?
      var base: BaseState

      static var initial: State {
        State(childTask: nil, base: .notStarted)
      }
    }

    enum BaseDecision {
      case resumeNext(UnsafeContinuation<Task<ChildValue?, Never>?, Never>, Task<ChildValue?, Never>?)
      case cancelPreviousChildTask(Task<ChildValue?, Never>?)
    }

    enum NextDecision {
      case immediatelyResume(Task<ChildValue?, Never>)
      case suspend
    }

    enum PostElementDecision {
      case returnElement(Result<Element, Error>)
      case returnError(Result<Element, Error>)
      case returnFinish
      case pass
    }

    enum ChildValue: Sendable {
      case element(Base.Element.AsyncIterator?, Result<Element?, Error>)
      case cancelled
    }

    var baseTask: Task<Void, Never>?
    let base: Base
    let state: ManagedCriticalState<State>

    init(_ base: Base) {
      self.state = ManagedCriticalState(.initial)
      self.base = base
    }

    mutating func startBase() {
      let wasBaseAlreadyStarted = self.state.withCriticalRegion { state -> Bool in
        switch state.base {
          case .notStarted:
            state.base = .idle
            return false
          default:
            return true
        }
      }

      guard !wasBaseAlreadyStarted else { return }

      self.baseTask = Task { [base, state] in
        do {
          for try await child in base {
            let childIterator = child.makeAsyncIterator()
            let decision = state.withCriticalRegion { state -> BaseDecision in
              switch state.base {
                case .waitingForChildIterator(let continuation):
                  state.base = .processingChildIterator(.success(childIterator))
                  let childTask = Self.makeChildTask(childIterator: .success(childIterator))
                  state.childTask = childTask
                  return .resumeNext(continuation, childTask)
                default:
                  state.base = .newChildIteratorAvailable(.success(childIterator))
                  return .cancelPreviousChildTask(state.childTask)
              }
            }

            switch decision {
              case .cancelPreviousChildTask(let task):
                task?.cancel()
              case .resumeNext(let continuation, let childTask):
                continuation.resume(returning: childTask)
            }
          }

          let decision = state.withCriticalRegion { state -> BaseDecision in
            switch state.base {
              case .waitingForChildIterator(let continuation):
                state.base = .finished(nil)
                return .resumeNext(continuation, nil)
              default:
                state.base = .finished(state.base.childIterator)
                return .cancelPreviousChildTask(nil)
            }
          }

          switch decision {
            case .cancelPreviousChildTask:
              break
            case .resumeNext(let continuation, let childTask):
              continuation.resume(returning: childTask)
          }
        } catch {
          let decision = state.withCriticalRegion { state -> BaseDecision in
            switch state.base {
              case .waitingForChildIterator(let continuation):
                state.base = .failed(error)
                let childTask = Self.makeChildTask(childIterator: .failure(error))
                state.childTask = childTask
                return .resumeNext(continuation, childTask)
              default:
                state.base = .failed(error)
                return .cancelPreviousChildTask(state.childTask)
            }
          }

          switch decision {
            case .cancelPreviousChildTask(let task):
              task?.cancel()
            case .resumeNext(let continuation, let childTask):
              continuation.resume(returning: childTask)
          }
        }
      }
    }

    static func makeChildTask(childIterator: Result<Base.Element.AsyncIterator, Error>?) -> Task<ChildValue?, Never> {
      Task {
        do {
          try Task.checkCancellation()
          guard var iterator = try childIterator?.get() else { return nil }
          let element = try await iterator.next()
          try Task.checkCancellation()
          return .element(iterator, .success(element))
        } catch is CancellationError {
          return .cancelled
        } catch {
          return .element(nil, .failure(error))
        }
      }
    }

    public mutating func next() async rethrows -> Element? {
      guard !Task.isCancelled else { return nil }
      self.startBase()

      return try await withTaskCancellationHandler { [baseTask, state] in
        baseTask?.cancel()
        state.withCriticalRegion {
          $0.childTask?.cancel()
        }
      } operation: {
        while true {
          let childTask = await withUnsafeContinuation { [state] (continuation: UnsafeContinuation<Task<ChildValue?, Never>?, Never>) in
            let decision = state.withCriticalRegion { state -> NextDecision in
              switch state.base {
                case .newChildIteratorAvailable(let childIterator):
                  state.base = .processingChildIterator(childIterator)
                  let childTask = Self.makeChildTask(childIterator: childIterator)
                  state.childTask = childTask
                  return .immediatelyResume(childTask)
                case .processingChildIterator(let childIterator):
                  let childTask = Self.makeChildTask(childIterator: childIterator)
                  state.childTask = childTask
                  return .immediatelyResume(childTask)
                case .finished(let childIterator):
                  let childTask = Self.makeChildTask(childIterator: childIterator)
                  state.childTask = childTask
                  return .immediatelyResume(childTask)
                case .failed(let error):
                  let childTask = Self.makeChildTask(childIterator: .failure(error))
                  state.childTask = childTask
                  return .immediatelyResume(childTask)
                default:
                  state.base = .waitingForChildIterator(continuation)
                  return .suspend
              }
            }

            switch decision {
              case .suspend:
                break
              case .immediatelyResume(let childTask):
                continuation.resume(returning: childTask)
            }
          }

          let value = await childTask?.value

          let decision = state.withCriticalRegion { state -> PostElementDecision in
            if state.base.isNewAvailableChildIterator {
              return .pass
            } else {
              switch value {
                case .element(_, .success(nil)) where state.base.isFinished:
                  return .returnFinish
                case .element(_, .success(nil)) where !state.base.isFinished:
                  state.base = .idle
                  return .pass
                case .element(_, .failure(let error)):
                  state.base = .failed(error)
                  return .returnError(.failure(error))
                case .element(.some(let childIterator), .success(.some(let element))) where state.base.isFinished:
                  state.base = .finished(.success(childIterator))
                  return .returnElement(.success(element))
                case .element(.some(let childIterator), .success(let element)) where !state.base.isFinished:
                  state.base = .processingChildIterator(.success(childIterator))
                  return .returnElement(.success(element!))
                case .cancelled where state.base.childIterator != nil:
                  return .pass
                default:
                  return .returnFinish
              }
            }
          }

          switch decision {
            case .pass:
              continue
            case .returnFinish:
              return nil
            case .returnError(let error):
              self.baseTask?.cancel()
              return try error._rethrowGet()
            case .returnElement(let element):
              return try element._rethrowGet()
          }
        }
      }
    }
  }
}

extension AsyncSwitchToLatestSequence: Sendable where Base: Sendable {}
