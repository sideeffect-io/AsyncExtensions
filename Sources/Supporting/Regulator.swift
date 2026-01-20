//
//  Regulator.swift
//  
//
//  Created by Thibault Wittemberg on 08/09/2022.
//

enum RegulatedElement<Element>: @unchecked Sendable {
  case termination
  case element(result: Result<Element, Error>)
}

final class Regulator<Base: AsyncSequence>: @unchecked Sendable {
  enum State {
    case idle
    case suspended(UnsafeContinuation<Bool, Never>)
    case active
    case finished
  }

  let base: Base
  let state: ManagedCriticalState<State>
  let onNextRegulatedElement: @Sendable (RegulatedElement<Base.Element>) -> Void

  init(
    _ base: Base,
    onNextRegulatedElement: @Sendable @escaping (RegulatedElement<Base.Element>) -> Void
  ) {
    self.base = base
    self.state = ManagedCriticalState(.idle)
    self.onNextRegulatedElement = onNextRegulatedElement
  }

  func unsuspendAndExitOnCancel() {
    let continuation = state.withCriticalRegion { state -> UnsafeContinuation<Bool, Never>? in
      switch state {
        case .suspended(let continuation):
          state = .finished
          return continuation
        default:
          state = .finished
          return nil
      }
    }

    continuation?.resume(returning: true)
  }

  func iterate() async {
    await withTaskCancellationHandler {
      var mutableBase = base.makeAsyncIterator()

      do {
      baseLoop: while true {
        let shouldExit = await withUnsafeContinuation { (continuation: UnsafeContinuation<Bool, Never>) in
          let decision = self.state.withCriticalRegion { state -> (UnsafeContinuation<Bool, Never>?, Bool) in
            switch state {
              case .idle:
                state = .suspended(continuation)
                return (nil, false)
              case .suspended(let continuation):
                assertionFailure("Inconsistent state, the base is already suspended")
                return (continuation, true)
              case .active:
                return (continuation, false)
              case .finished:
                return (continuation, true)
            }
          }

          decision.0?.resume(returning: decision.1)
        }

        if shouldExit {
          // end the loop ... no more values from this base
          break baseLoop
        }

        let element = try await mutableBase.next()

        let regulatedElement = self.state.withCriticalRegion { state -> RegulatedElement<Base.Element> in
          switch element {
            case .some(let element):
              state = .idle
              return .element(result: .success(element))
            case .none:
              state = .finished
              return .termination
          }
        }

        self.onNextRegulatedElement(regulatedElement)
      }
      } catch {
        self.state.withCriticalRegion { state in
          state = .finished
        }
        self.onNextRegulatedElement(.element(result: .failure(error)))
      }
    } onCancel: {
      self.unsuspendAndExitOnCancel()
    }
  }

  @Sendable
  func requestNextRegulatedElement() {
    let continuation = self.state.withCriticalRegion { state -> UnsafeContinuation<Bool, Never>? in
      switch state {
        case .suspended(let continuation):
          state = .active
          return continuation
        case .idle:
          state = .active
          return nil
        case .active, .finished:
          return nil
      }
    }

    continuation?.resume(returning: false)
  }
}
