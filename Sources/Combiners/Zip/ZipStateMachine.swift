//
//  ZipStateMachine.swift
//  
//
//  Created by Thibault Wittemberg on 24/09/2022.
//

struct ZipStateMachine<Element>: Sendable
where Element: Sendable {
  private enum State {
    case initial
    case started(task: Task<Void, Never>)
    case awaitingDemandFromConsumer(
      task: Task<Void, Never>?,
      suspendedBases: [UnsafeContinuation<Void, Never>]
    )
    case awaitingBaseResults(
      task: Task<Void, Never>?,
      results: [Int: Result<Element, Error>]?,
      suspendedBases: [UnsafeContinuation<Void, Never>],
      suspendedDemand: UnsafeContinuation<[Int: Result<Element, Error>]?, Never>?
    )
    case finished
  }

  private var state: State = .initial

  let numberOfBases: Int

  init(numberOfBases: Int) {
    self.numberOfBases = numberOfBases
  }

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
      suspendedDemands: [UnsafeContinuation<[Int: Result<Element, Error>]?, Never>?]?
    )
  }

  mutating func newDemandFromConsumer(
    suspendedDemand: UnsafeContinuation<[Int: Result<Element, Error>]?, Never>
  ) -> NewDemandFromConsumerOutput {
    switch self.state {
      case .initial:
        assertionFailure("Inconsistent state, the task is not started")
        self.state = .finished
        return .terminate(task: nil, suspendedBases: nil, suspendedDemands: [suspendedDemand])

      case .started(let task):
        self.state = .awaitingBaseResults(task: task, results: nil, suspendedBases: [], suspendedDemand: suspendedDemand)
        return .none

      case .awaitingDemandFromConsumer(let task, let suspendedBases):
        self.state = .awaitingBaseResults(task: task, results: nil, suspendedBases: [], suspendedDemand: suspendedDemand)
        return .resumeBases(suspendedBases: suspendedBases)

      case .awaitingBaseResults(let task, _, let suspendedBases, let oldSuspendedDemand):
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
      suspendedDemand: UnsafeContinuation<[Int: Result<Element, Error>]?, Never>?
    )
  }

  mutating func newLoopFromBase(index: Int, suspendedBase: UnsafeContinuation<Void, Never>) -> NewLoopFromBaseOutput {
    switch self.state {
      case .initial:
        assertionFailure("Inconsistent state, the task is not started")
        self.state = .finished
        return .terminate(task: nil, suspendedBase: suspendedBase, suspendedDemand: nil)

      case .started(let task):
        self.state = .awaitingDemandFromConsumer(task: task, suspendedBases: [suspendedBase])
        return .none

      case .awaitingDemandFromConsumer(let task, var suspendedBases):
        assert(
          suspendedBases.count < self.numberOfBases,
          "There cannot be more than \(self.numberOfBases) suspended base at the same time"
        )
        suspendedBases.append(suspendedBase)
        self.state = .awaitingDemandFromConsumer(task: task, suspendedBases: suspendedBases)
        return .none

      case .awaitingBaseResults(let task, let results, var suspendedBases, let suspendedDemand):
        assert(
          suspendedBases.count < self.numberOfBases,
          "There cannot be more than \(self.numberOfBases) suspended base at the same time"
        )
        if results?[index] != nil {
          suspendedBases.append(suspendedBase)
          self.state = .awaitingBaseResults(
            task: task,
            results: results,
            suspendedBases: suspendedBases,
            suspendedDemand: suspendedDemand
          )
          return .none
        } else {
          self.state = .awaitingBaseResults(
            task: task,
            results: results,
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
      suspendedDemand: UnsafeContinuation<[Int: Result<Element, Error>]?, Never>?,
      results: [Int: Result<Element, Error>]
    )
    case terminate(
      task: Task<Void, Never>?,
      suspendedBases: [UnsafeContinuation<Void, Never>]?
    )
  }

  mutating func baseHasProducedElement(index: Int, element: Element) -> BaseHasProducedElementOutput {
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

      case .awaitingBaseResults(let task, let results, let suspendedBases, let suspendedDemand):
        assert(results?[index] == nil, "Inconsistent state, a base can only produce an element when the previous one has been consumed")
        var mutableResults: [Int: Result<Element, Error>]
        if let results = results {
          mutableResults = results
        } else {
          mutableResults = [:]
        }
        mutableResults[index] = .success(element)
        if mutableResults.count == self.numberOfBases {
          self.state = .awaitingBaseResults(task: task, results: mutableResults, suspendedBases: suspendedBases, suspendedDemand: nil)
          return .resumeDemand(suspendedDemand: suspendedDemand, results: mutableResults)
        } else {
          self.state = .awaitingBaseResults(task: task, results: mutableResults, suspendedBases: suspendedBases, suspendedDemand: suspendedDemand)
          return .none
        }

      case .finished:
        return .terminate(task: nil, suspendedBases: nil)
    }
  }

  enum BaseHasProducedFailureOutput {
    case resumeDemandAndTerminate(
      task: Task<Void, Never>?,
      suspendedDemand: UnsafeContinuation<[Int: Result<Element, Error>]?, Never>?,
      suspendedBases: [UnsafeContinuation<Void, Never>],
      results: [Int: Result<Element, Error>]
    )
    case terminate(
      task: Task<Void, Never>?,
      suspendedBases: [UnsafeContinuation<Void, Never>]?
    )
  }

  mutating func baseHasProducedFailure(error: any Error) -> BaseHasProducedFailureOutput {
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

      case .awaitingBaseResults(let task, _, let suspendedBases, let suspendedDemand):
        self.state = .finished
        return .resumeDemandAndTerminate(
          task: task,
          suspendedDemand: suspendedDemand,
          suspendedBases: suspendedBases,
          results: [0: .failure(error)]
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
      suspendedDemands: [UnsafeContinuation<[Int: Result<Element, Error>]?, Never>]?
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

      case .awaitingBaseResults(let task, let results, let suspendedBases, let suspendedDemand):
        assert(suspendedDemand == nil, "Inconsistent state, there cannot be a suspended demand when ackowledging the demand")
        assert(results?.count == self.numberOfBases, "Inconsistent state, all results are not yet available to be acknowledged")
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
      suspendedDemands: [UnsafeContinuation<[Int: Result<Element, Error>]?, Never>?]?
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

      case .awaitingBaseResults(let task, _, let suspendedBases, let suspendedDemand):
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
      suspendedDemands: [UnsafeContinuation<[Int: Result<Element, Error>]?, Never>?]?
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

      case .awaitingBaseResults(let task, _, let suspendedBases, let suspendedDemand):
        self.state = .finished
        return .terminate(task: task, suspendedBases: suspendedBases, suspendedDemands: [suspendedDemand])

      case .finished:
        return .terminate(task: nil, suspendedBases: nil, suspendedDemands: nil)
    }
  }
}
