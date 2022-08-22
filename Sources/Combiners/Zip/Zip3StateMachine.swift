//
//  Zip3StateMachine.swift
//  
//
//  Created by Thibault Wittemberg on 24/09/2022.
//

struct Zip3StateMachine<Element1, Element2, Element3>: Sendable
where Element1: Sendable, Element2: Sendable, Element3: Sendable {
  private enum State {
    case initial
    case started(task: Task<Void, Never>)
    case awaitingDemandFromConsumer(
      task: Task<Void, Never>?,
      suspendedBases: [UnsafeContinuation<Void, Never>]
    )
    case awaitingBaseResults(
      task: Task<Void, Never>?,
      result1: Result<Element1, Error>?,
      result2: Result<Element2, Error>?,
      result3: Result<Element3, Error>?,
      suspendedBases: [UnsafeContinuation<Void, Never>],
      suspendedDemand: UnsafeContinuation<(Result<Element1, Error>, Result<Element2, Error>, Result<Element3, Error>)?, Never>?
    )
    case finished
  }

  private var state: State = .initial

  mutating func taskIsStarted(task: Task<Void, Never>) {
    switch self.state {
      case .initial:
        self.state = .started(task: task)

      default:
        assertionFailure("Inconsistent state, the task cannot start while the state is other than initial")
    }
  }

  enum NewDemandFromConsumerOutput {
    case none
    case resumeBases(suspendedBases: [UnsafeContinuation<Void, Never>])
    case terminate(
      task: Task<Void, Never>?,
      suspendedBases: [UnsafeContinuation<Void, Never>]?,
      suspendedDemands: [UnsafeContinuation<(Result<Element1, Error>, Result<Element2, Error>, Result<Element3, Error>)?, Never>?]?
    )
  }

  mutating func newDemandFromConsumer(
    suspendedDemand: UnsafeContinuation<(Result<Element1, Error>, Result<Element2, Error>, Result<Element3, Error>)?, Never>
  ) -> NewDemandFromConsumerOutput {
    switch self.state {
      case .initial:
        assertionFailure("Inconsistent state, the task is not started")
        self.state = .finished
        return .terminate(task: nil, suspendedBases: nil, suspendedDemands: [suspendedDemand])

      case .started(let task):
        self.state = .awaitingBaseResults(
          task: task,
          result1: nil,
          result2: nil,
          result3: nil,
          suspendedBases: [],
          suspendedDemand: suspendedDemand
        )
        return .none

      case .awaitingDemandFromConsumer(let task, let suspendedBases):
        self.state = .awaitingBaseResults(
          task: task,
          result1: nil,
          result2: nil,
          result3: nil,
          suspendedBases: [],
          suspendedDemand: suspendedDemand
        )
        return .resumeBases(suspendedBases: suspendedBases)

      case .awaitingBaseResults(let task, _, _, _, let suspendedBases, let oldSuspendedDemand):
        assertionFailure("Inconsistent state, a demand is already suspended")
        self.state = .finished
        return .terminate(task: task, suspendedBases: suspendedBases, suspendedDemands: [oldSuspendedDemand, suspendedDemand])

      case .finished:
        return .terminate(task: nil, suspendedBases: nil, suspendedDemands: [suspendedDemand])
    }
  }

  enum NewLoopFromBaseOutput {
    case none
    case resumeBases(suspendedBases: [UnsafeContinuation<Void, Never>])
    case terminate(
      task: Task<Void, Never>?,
      suspendedBase: UnsafeContinuation<Void, Never>,
      suspendedDemand: UnsafeContinuation<(Result<Element1, Error>, Result<Element2, Error>, Result<Element3, Error>)?, Never>?
    )
  }

  mutating func newLoopFromBase1(suspendedBase: UnsafeContinuation<Void, Never>) -> NewLoopFromBaseOutput {
    switch self.state {
      case .initial:
        assertionFailure("Inconsistent state, the task is not started")
        self.state = .finished
        return .terminate(task: nil, suspendedBase: suspendedBase, suspendedDemand: nil)

      case .started(let task):
        self.state = .awaitingDemandFromConsumer(task: task, suspendedBases: [suspendedBase])
        return .none

      case .awaitingDemandFromConsumer(let task, var suspendedBases):
        assert(suspendedBases.count < 3, "There cannot be more than 3 suspended base at the same time")
        suspendedBases.append(suspendedBase)
        self.state = .awaitingDemandFromConsumer(task: task, suspendedBases: suspendedBases)
        return .none

      case .awaitingBaseResults(let task, let result1, let result2, let result3, var suspendedBases, let suspendedDemand):
        assert(suspendedBases.count < 3, "There cannot be more than 3 suspended bases at the same time")
        if result1 != nil {
          suspendedBases.append(suspendedBase)
          self.state = .awaitingBaseResults(
            task: task,
            result1: result1,
            result2: result2,
            result3: result3,
            suspendedBases: suspendedBases,
            suspendedDemand: suspendedDemand
          )
          return .none
        } else {
          self.state = .awaitingBaseResults(
            task: task,
            result1: result1,
            result2: result2,
            result3: result3,
            suspendedBases: suspendedBases,
            suspendedDemand: suspendedDemand
          )
          return .resumeBases(suspendedBases: [suspendedBase])
        }

      case .finished:
        return .terminate(task: nil, suspendedBase: suspendedBase, suspendedDemand: nil)
    }
  }

  mutating func newLoopFromBase2(suspendedBase: UnsafeContinuation<Void, Never>) -> NewLoopFromBaseOutput {
    switch state {
      case .initial:
        assertionFailure("Inconsistent state, the task is not started")
        self.state = .finished
        return .terminate(task: nil, suspendedBase: suspendedBase, suspendedDemand: nil)

      case .started(let task):
        self.state = .awaitingDemandFromConsumer(task: task, suspendedBases: [suspendedBase])
        return .none

      case .awaitingDemandFromConsumer(let task, var suspendedBases):
        assert(suspendedBases.count < 3, "There cannot be more than 3 suspended base at the same time")
        suspendedBases.append(suspendedBase)
        self.state = .awaitingDemandFromConsumer(task: task, suspendedBases: suspendedBases)
        return .none

      case .awaitingBaseResults(let task, let result1, let result2, let result3, var suspendedBases, let suspendedDemand):
        assert(suspendedBases.count < 3, "There cannot be more than 3 suspended bases at the same time")
        if result2 != nil {
          suspendedBases.append(suspendedBase)
          self.state = .awaitingBaseResults(
            task: task,
            result1: result1,
            result2: result2,
            result3: result3,
            suspendedBases: suspendedBases,
            suspendedDemand: suspendedDemand
          )
          return .none
        } else {
          self.state = .awaitingBaseResults(
            task: task,
            result1: result1,
            result2: result2,
            result3: result3,
            suspendedBases: suspendedBases,
            suspendedDemand: suspendedDemand
          )
          return .resumeBases(suspendedBases: [suspendedBase])
        }

      case .finished:
        return .terminate(task: nil, suspendedBase: suspendedBase, suspendedDemand: nil)
    }
  }

  mutating func newLoopFromBase3(suspendedBase: UnsafeContinuation<Void, Never>) -> NewLoopFromBaseOutput {
    switch state {
      case .initial:
        assertionFailure("Inconsistent state, the task is not started")
        self.state = .finished
        return .terminate(task: nil, suspendedBase: suspendedBase, suspendedDemand: nil)

      case .started(let task):
        self.state = .awaitingDemandFromConsumer(task: task, suspendedBases: [suspendedBase])
        return .none

      case .awaitingDemandFromConsumer(let task, var suspendedBases):
        assert(suspendedBases.count < 3, "There cannot be more than 3 suspended base at the same time")
        suspendedBases.append(suspendedBase)
        self.state = .awaitingDemandFromConsumer(task: task, suspendedBases: suspendedBases)
        return .none

      case .awaitingBaseResults(let task, let result1, let result2, let result3, var suspendedBases, let suspendedDemand):
        assert(suspendedBases.count < 3, "There cannot be more than 3 suspended bases at the same time")
        if result3 != nil {
          suspendedBases.append(suspendedBase)
          self.state = .awaitingBaseResults(
            task: task,
            result1: result1,
            result2: result2,
            result3: result3,
            suspendedBases: suspendedBases,
            suspendedDemand: suspendedDemand
          )
          return .none
        } else {
          self.state = .awaitingBaseResults(
            task: task,
            result1: result1,
            result2: result2,
            result3: result3,
            suspendedBases: suspendedBases,
            suspendedDemand: suspendedDemand
          )
          return .resumeBases(suspendedBases: [suspendedBase])
        }

      case .finished:
        return .terminate(task: nil, suspendedBase: suspendedBase, suspendedDemand: nil)
    }
  }

  enum BaseHasProducedElementOutput {
    case none
    case resumeDemand(
      suspendedDemand: UnsafeContinuation<(Result<Element1, Error>, Result<Element2, Error>, Result<Element3, Error>)?, Never>?,
      result1: Result<Element1, Error>,
      result2: Result<Element2, Error>,
      result3: Result<Element3, Error>
    )
    case terminate(
      task: Task<Void, Never>?,
      suspendedBases: [UnsafeContinuation<Void, Never>]?
    )
  }

  mutating func base1HasProducedElement(element: Element1) -> BaseHasProducedElementOutput {
    switch self.state {
      case .initial:
        assertionFailure("Inconsistent state, the task is not started")
        self.state = .finished
        return .terminate(task: nil, suspendedBases: nil)

      case .started(let task):
        assertionFailure("Inconsistent state, a base can only produce an element when the consumer is awaiting for it")
        self.state = .finished
        return .terminate(task: task, suspendedBases: nil)

      case .awaitingDemandFromConsumer(let task, let suspendedBases):
        assertionFailure("Inconsistent state, a base can only produce an element when the consumer is awaiting for it")
        self.state = .finished
        return .terminate(task: task, suspendedBases: suspendedBases)

      case .awaitingBaseResults(let task, _, let result2, let result3, let suspendedBases, let suspendedDemand):
        if let result2 = result2, let result3 = result3 {
          self.state = .awaitingBaseResults(
            task: task,
            result1: .success(element),
            result2: result2,
            result3: result3,
            suspendedBases: suspendedBases,
            suspendedDemand: nil
          )
          return .resumeDemand(suspendedDemand: suspendedDemand, result1: .success(element), result2: result2, result3: result3)
        } else {
          self.state = .awaitingBaseResults(
            task: task,
            result1: .success(element),
            result2: result2,
            result3: result3,
            suspendedBases: suspendedBases,
            suspendedDemand: suspendedDemand
          )
          return .none
        }

      case .finished:
        return .terminate(task: nil, suspendedBases: nil)
    }
  }

  enum BaseHasProducedFailureOutput {
    case resumeDemandAndTerminate(
      task: Task<Void, Never>?,
      suspendedDemand: UnsafeContinuation<(Result<Element1, Error>, Result<Element2, Error>, Result<Element3, Error>)?, Never>?,
      suspendedBases: [UnsafeContinuation<Void, Never>],
      result1: Result<Element1, Error>,
      result2: Result<Element2, Error>,
      result3: Result<Element3, Error>
    )
    case terminate(
      task: Task<Void, Never>?,
      suspendedBases: [UnsafeContinuation<Void, Never>]?
    )
  }

  mutating func base2HasProducedElement(element: Element2) -> BaseHasProducedElementOutput {
    switch self.state {
      case .initial:
        assertionFailure("Inconsistent state, the task is not started")
        self.state = .finished
        return .terminate(task: nil, suspendedBases: nil)

      case .started(let task):
        assertionFailure("Inconsistent state, a base can only produce an element when the consumer is awaiting for it")
        self.state = .finished
        return .terminate(task: task, suspendedBases: nil)

      case .awaitingDemandFromConsumer(let task, let suspendedBases):
        assertionFailure("Inconsistent state, a base can only produce an element when the consumer is awaiting for it")
        self.state = .finished
        return .terminate(task: task, suspendedBases: suspendedBases)

      case .awaitingBaseResults(let task, let result1, _, let result3, let suspendedBases, let suspendedDemand):
        if let result1 = result1, let result3 = result3 {
          self.state = .awaitingBaseResults(
            task: task,
            result1: result1,
            result2: .success(element),
            result3: result3,
            suspendedBases: suspendedBases,
            suspendedDemand: nil
          )
          return .resumeDemand(suspendedDemand: suspendedDemand, result1: result1, result2: .success(element), result3: result3)
        } else {
          self.state = .awaitingBaseResults(
            task: task,
            result1: result1,
            result2: .success(element),
            result3: result3,
            suspendedBases: suspendedBases,
            suspendedDemand: suspendedDemand
          )
          return .none
        }

      case .finished:
        return .terminate(task: nil, suspendedBases: nil)
    }
  }

  mutating func base3HasProducedElement(element: Element3) -> BaseHasProducedElementOutput {
    switch self.state {
      case .initial:
        assertionFailure("Inconsistent state, the task is not started")
        self.state = .finished
        return .terminate(task: nil, suspendedBases: nil)

      case .started(let task):
        assertionFailure("Inconsistent state, a base can only produce an element when the consumer is awaiting for it")
        self.state = .finished
        return .terminate(task: task, suspendedBases: nil)

      case .awaitingDemandFromConsumer(let task, let suspendedBases):
        assertionFailure("Inconsistent state, a base can only produce an element when the consumer is awaiting for it")
        self.state = .finished
        return .terminate(task: task, suspendedBases: suspendedBases)

      case .awaitingBaseResults(let task, let result1, let result2, _, let suspendedBases, let suspendedDemand):
        if let result1 = result1, let result2 = result2 {
          self.state = .awaitingBaseResults(
            task: task,
            result1: result1,
            result2: result2,
            result3: .success(element),
            suspendedBases: suspendedBases,
            suspendedDemand: nil
          )
          return .resumeDemand(suspendedDemand: suspendedDemand, result1: result1, result2: result2, result3: .success(element))
        } else {
          self.state = .awaitingBaseResults(
            task: task,
            result1: result1,
            result2: result2,
            result3: .success(element),
            suspendedBases: suspendedBases,
            suspendedDemand: suspendedDemand
          )
          return .none
        }

      case .finished:
        return .terminate(task: nil, suspendedBases: nil)
    }
  }

  mutating func baseHasProducedFailure(error: Error) -> BaseHasProducedFailureOutput {
    switch self.state {
      case .initial:
        assertionFailure("Inconsistent state, the task is not started")
        self.state = .finished
        return .terminate(task: nil, suspendedBases: nil)

      case .started(let task):
        assertionFailure("Inconsistent state, a base can only produce an element when the consumer is awaiting for it")
        self.state = .finished
        return .terminate(task: task, suspendedBases: nil)

      case .awaitingDemandFromConsumer(let task, let suspendedBases):
        assertionFailure("Inconsistent state, a base can only produce an element when the consumer is awaiting for it")
        self.state = .finished
        return .terminate(task: task, suspendedBases: suspendedBases)

      case .awaitingBaseResults(let task, _, _, _, let suspendedBases, let suspendedDemand):
        self.state = .finished
        return .resumeDemandAndTerminate(
          task: task,
          suspendedDemand: suspendedDemand,
          suspendedBases: suspendedBases,
          result1: .failure(error),
          result2: .failure(error),
          result3: .failure(error)
        )

      case .finished:
        return .terminate(task: nil, suspendedBases: nil)
    }
  }

  enum DemandIsFulfilledOutput {
    case none
    case terminate(
      task: Task<Void, Never>?,
      suspendedBases: [UnsafeContinuation<Void, Never>]?,
      suspendedDemands: [UnsafeContinuation<(Result<Element1, Error>, Result<Element2, Error>)?, Never>]?
    )
  }

  mutating func demandIsFulfilled() -> DemandIsFulfilledOutput {
    switch self.state {
      case .initial:
        assertionFailure("Inconsistent state, the task is not started")
        self.state = .finished
        return .terminate(task: nil, suspendedBases: nil, suspendedDemands: nil)

      case .started(let task):
        assertionFailure("Inconsistent state, results are not yet available to be acknowledged")
        self.state = .finished
        return .terminate(task: task, suspendedBases: nil, suspendedDemands: nil)

      case .awaitingDemandFromConsumer(let task, let suspendedBases):
        assertionFailure("Inconsistent state, results are not yet available to be acknowledged")
        self.state = .finished
        return .terminate(task: task, suspendedBases: suspendedBases, suspendedDemands: nil)

      case .awaitingBaseResults(let task, let result1, let result2, let result3, let suspendedBases, let suspendedDemand):
        assert(suspendedDemand == nil, "Inconsistent state, there cannot be a suspended demand when ackowledging the demand")
        assert(
          result1 != nil && result2 != nil && result3 != nil,
          "Inconsistent state, all results are not yet available to be acknowledged"
        )
        self.state = .awaitingDemandFromConsumer(task: task, suspendedBases: suspendedBases)
        return .none

      case .finished:
        return .terminate(task: nil, suspendedBases: nil, suspendedDemands: nil)
    }
  }

  enum RootTaskIsCancelledOutput {
    case terminate(
      task: Task<Void, Never>?,
      suspendedBases: [UnsafeContinuation<Void, Never>]?,
      suspendedDemands: [UnsafeContinuation<(Result<Element1, Error>, Result<Element2, Error>, Result<Element3, Error>)?, Never>?]?
    )
  }

  mutating func rootTaskIsCancelled() -> RootTaskIsCancelledOutput {
    switch self.state {
      case .initial:
        assertionFailure("Inconsistent state, the task is not started")
        self.state = .finished
        return .terminate(task: nil, suspendedBases: nil, suspendedDemands: nil)

      case .started(let task):
        self.state = .finished
        return .terminate(task: task, suspendedBases: nil, suspendedDemands: nil)

      case .awaitingDemandFromConsumer(let task, let suspendedBases):
        self.state = .finished
        return .terminate(task: task, suspendedBases: suspendedBases, suspendedDemands: nil)

      case .awaitingBaseResults(let task, _, _, _, let suspendedBases, let suspendedDemand):
        self.state = .finished
        return .terminate(task: task, suspendedBases: suspendedBases, suspendedDemands: [suspendedDemand])

      case .finished:
        return .terminate(task: nil, suspendedBases: nil, suspendedDemands: nil)
    }
  }

  enum BaseIsFinishedOutput {
    case terminate(
      task: Task<Void, Never>?,
      suspendedBases: [UnsafeContinuation<Void, Never>]?,
      suspendedDemands: [UnsafeContinuation<(Result<Element1, Error>, Result<Element2, Error>, Result<Element3, Error>)?, Never>?]?
    )
  }

  mutating func baseIsFinished() -> BaseIsFinishedOutput {
    switch self.state {
      case .initial:
        assertionFailure("Inconsistent state, the task is not started")
        self.state = .finished
        return .terminate(task: nil, suspendedBases: nil, suspendedDemands: nil)

      case .started(let task):
        self.state = .finished
        return .terminate(task: task, suspendedBases: nil, suspendedDemands: nil)

      case .awaitingDemandFromConsumer(let task, let suspendedBases):
        self.state = .finished
        return .terminate(task: task, suspendedBases: suspendedBases, suspendedDemands: nil)

      case .awaitingBaseResults(let task, _, _, _, let suspendedBases, let suspendedDemand):
        self.state = .finished
        return .terminate(task: task, suspendedBases: suspendedBases, suspendedDemands: [suspendedDemand])

      case .finished:
        return .terminate(task: nil, suspendedBases: nil, suspendedDemands: nil)
    }
  }
}
