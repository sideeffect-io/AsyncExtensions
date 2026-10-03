//
//  MergeStateMachine.swift
//  
//
//  Created by Thibault Wittemberg on 08/09/2022.
//

import DequeModule

struct MergeStateMachine<Element>: Sendable {
  enum BufferState {
    case idle
    case queued(Deque<RegulatedElement<Element>>)
    case awaiting(UnsafeContinuation<RegulatedElement<Element>, Never>)
    case closed
  }

  struct State {
    var buffer: BufferState
    var basesToTerminate: Int
  }

  struct OnNextDecision {
    let continuation: UnsafeContinuation<RegulatedElement<Element>, Never>
    let regulatedElement: RegulatedElement<Element>
  }

  let requestNextRegulatedElements: @Sendable () -> Void
  let state: ManagedCriticalState<State>
  let task: Task<Void, Never>

  init<Base: AsyncSequence>(
    _ bases: [Base]
  ) where Base.Element == Element {
    self.state = ManagedCriticalState(State(buffer: .idle, basesToTerminate: bases.count))

    var regulators = [Regulator<Base>]()

    for base in bases {
      let regulator = Regulator<Base>(base, onNextRegulatedElement: { [state] in Self.onNextRegulatedElement($0, state: state) }
      )
      regulators.append(regulator)
    }

    let immutableRegulators = regulators
    self.requestNextRegulatedElements = {
      for regulator in immutableRegulators {
        regulator.requestNextRegulatedElement()
      }
    }

    self.task = Task {
      await withTaskGroup(of: Void.self) { group in
        for regulators in immutableRegulators {
          group.addTask {
            await regulators.iterate()
          }
        }
      }
    }
  }

  @Sendable
  static func onNextRegulatedElement(_ element: RegulatedElement<Element>, state: ManagedCriticalState<State>) {
    let decision = state.withCriticalRegion { state -> OnNextDecision? in
      switch (state.buffer, element) {
        case (.idle, .element):
          state.buffer = .queued([element])
          return nil
        case (.queued(var elements), .element):
          elements.append(element)
          state.buffer = .queued(elements)
          return nil
        case (.awaiting(let continuation), .element(.success)):
          state.buffer = .idle
          return OnNextDecision(continuation: continuation, regulatedElement: element)
        case (.awaiting(let continuation), .element(.failure)):
          state.buffer = .closed
          return OnNextDecision(continuation: continuation, regulatedElement: element)

        case (.idle, .termination):
          state.basesToTerminate -= 1
          if state.basesToTerminate == 0 {
            state.buffer = .closed
          } else {
            state.buffer = .idle
          }
          return nil

        case (.queued(var elements), .termination):
          state.basesToTerminate -= 1
          if state.basesToTerminate == 0 {
            elements.append(.termination)
            state.buffer = .queued(elements)
          }
          return nil

        case (.awaiting(let continuation), .termination):
          state.basesToTerminate -= 1
          if state.basesToTerminate == 0 {
            state.buffer = .closed
            return OnNextDecision(continuation: continuation, regulatedElement: .termination)
          } else {
            state.buffer = .awaiting(continuation)
            return nil
          }

        case (.closed, _):
          return nil
      }
    }

    if let decision = decision {
      decision.continuation.resume(returning: decision.regulatedElement)
    }
  }

  @Sendable
  func unsuspendAndClearOnCancel() {
    let continuation = self.state.withCriticalRegion { state -> UnsafeContinuation<RegulatedElement<Element>, Never>? in
      switch state.buffer {
        case .awaiting(let continuation):
          state.basesToTerminate = 0
          state.buffer = .closed
          return continuation
        default:
          state.basesToTerminate = 0
          state.buffer = .closed
          return nil
      }
    }

    continuation?.resume(returning: .termination)
    self.task.cancel()
  }

  func next() async -> RegulatedElement<Element> {
    await withTaskCancellationHandler {
      self.requestNextRegulatedElements()

      let regulatedElement = await withUnsafeContinuation { (continuation: UnsafeContinuation<RegulatedElement<Element>, Never>) in
        let decision = self.state.withCriticalRegion { state -> OnNextDecision? in
          switch state.buffer {
            case .queued(var elements):
              guard let regulatedElement = elements.popFirst() else {
                assertionFailure("The buffer cannot by empty, it should be idle in this case")
                return OnNextDecision(continuation: continuation, regulatedElement: .termination)
              }
              switch regulatedElement {
                case .termination:
                  state.buffer = .closed
                  return OnNextDecision(continuation: continuation, regulatedElement: .termination)
                case .element(.success):
                  if elements.isEmpty {
                    state.buffer = .idle
                  } else {
                    state.buffer = .queued(elements)
                  }
                  return OnNextDecision(continuation: continuation, regulatedElement: regulatedElement)
                case .element(.failure):
                  state.buffer = .closed
                  return OnNextDecision(continuation: continuation, regulatedElement: regulatedElement)
              }
            case .idle:
              state.buffer = .awaiting(continuation)
              return nil
            case .awaiting:
              assertionFailure("The next function cannot be called concurrently")
              return OnNextDecision(continuation: continuation, regulatedElement: .termination)
            case .closed:
              return OnNextDecision(continuation: continuation, regulatedElement: .termination)
          }
        }

        if let decision = decision {
          decision.continuation.resume(returning: decision.regulatedElement)
        }
      }

      if case .element(.failure) = regulatedElement {
        self.task.cancel()
      }

      return regulatedElement
    } onCancel: {
      self.unsuspendAndClearOnCancel()
    }
  }
}
