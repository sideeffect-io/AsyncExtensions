//
//  ZipRuntime.swift
//  
//
//  Created by Thibault Wittemberg on 24/09/2022.
//

final class ZipRuntime<Base: AsyncSequence>: Sendable
where Base: Sendable, Base.Element: Sendable {
  typealias StateMachine = ZipStateMachine<Base.Element>
  
  private let stateMachine: ManagedCriticalState<StateMachine>
  private let indexes = ManagedCriticalState(0)

  init(_ bases: [Base]) {
    self.stateMachine = ManagedCriticalState(StateMachine(numberOfBases: bases.count))

    self.stateMachine.withCriticalRegion { machine in
      machine.taskIsStarted(task: Task {
        await withTaskGroup(of: Void.self) { group in
          for base in bases {
            let index = self.indexes.withCriticalRegion { indexes -> Int in
              defer { indexes += 1 }
              return indexes
            }

            group.addTask {
              var baseIterator = base.makeAsyncIterator()

              do {
                while true {
                  await withUnsafeContinuation { (continuation: UnsafeContinuation<Void, Never>) in
                    let output = self.stateMachine.withCriticalRegion { machine in
                      machine.newLoopFromBase(index: index, suspendedBase: continuation)
                    }

                    self.handle(newLoopFromBaseOutput: output)
                  }

                  guard let element = try await baseIterator.next() else {
                    break
                  }

                  let output = self.stateMachine.withCriticalRegion { machine in
                    machine.baseHasProducedElement(index: index, element: element)
                  }

                  self.handle(baseHasProducedElementOutput: output)
                }
              } catch {
                let output = self.stateMachine.withCriticalRegion { machine in
                  machine.baseHasProducedFailure(error: error)
                }

                self.handle(baseHasProducedFailureOutput: output)
              }

              let output = self.stateMachine.withCriticalRegion { stateMachine in
                stateMachine.baseIsFinished()
              }

              self.handle(baseIsFinishedOutput: output)
            }
          }
        }
      })
    }
  }

  private func handle(newLoopFromBaseOutput: StateMachine.NewLoopFromBaseOutput) {
    switch newLoopFromBaseOutput {
      case .none:
        break

      case .resumeBases(let suspendedBases):
        suspendedBases.forEach { $0.resume() }

      case .terminate(let task, let suspendedBase, let suspendedDemand):
        suspendedBase.resume()
        suspendedDemand?.resume(returning: nil)
        task?.cancel()
    }
  }

  private func handle(baseHasProducedElementOutput: StateMachine.BaseHasProducedElementOutput) {
    switch baseHasProducedElementOutput {
      case .none:
        break

      case .resumeDemand(let suspendedDemand, let results):
        suspendedDemand?.resume(returning: results)

      case .terminate(let task, let suspendedBases):
        suspendedBases?.forEach { $0.resume() }
        task?.cancel()
    }
  }

  private func handle(baseHasProducedFailureOutput: StateMachine.BaseHasProducedFailureOutput) {
    switch baseHasProducedFailureOutput {
      case .resumeDemandAndTerminate(let task, let suspendedDemand, let suspendedBases, let results):
        suspendedDemand?.resume(returning: results)
        suspendedBases.forEach { $0.resume() }
        task?.cancel()

      case .terminate(let task, let suspendedBases):
        suspendedBases?.forEach { $0.resume() }
        task?.cancel()
    }
  }

  private func handle(baseIsFinishedOutput: StateMachine.BaseIsFinishedOutput) {
    switch baseIsFinishedOutput {
      case .terminate(let task, let suspendedBases, let suspendedDemands):
        suspendedBases?.forEach { $0.resume() }
        suspendedDemands?.forEach { $0?.resume(returning: nil) }
        task?.cancel()
    }
  }

  func next() async rethrows -> [Base.Element]? {
    try await withTaskCancellationHandler {
      let output = self.stateMachine.withCriticalRegion { stateMachine in
        stateMachine.rootTaskIsCancelled()
      }

      self.handle(rootTaskIsCancelledOutput: output)
    } operation: {
      let results = await withUnsafeContinuation { (continuation: UnsafeContinuation<[Int: Result<Base.Element, Error>]?, Never>) in
        let output = self.stateMachine.withCriticalRegion { stateMachine in
          stateMachine.newDemandFromConsumer(suspendedDemand: continuation)
        }

        self.handle(newDemandFromConsumerOutput: output)
      }

      guard let results = results else {
        return nil
      }

      let output = self.stateMachine.withCriticalRegion { stateMachine in
        stateMachine.demandIsFulfilled()
      }

      self.handle(demandIsFulfilledOutput: output)

      return try results.sorted { $0.key < $1.key }.map { try $0.value._rethrowGet() }
    }
  }

  private func handle(rootTaskIsCancelledOutput: StateMachine.RootTaskIsCancelledOutput) {
    switch rootTaskIsCancelledOutput {
      case .terminate(let task, let suspendedBases, let suspendedDemands):
        suspendedBases?.forEach { $0.resume() }
        suspendedDemands?.forEach { $0?.resume(returning: nil) }
        task?.cancel()
    }
  }

  private func handle(newDemandFromConsumerOutput: StateMachine.NewDemandFromConsumerOutput) {
    switch newDemandFromConsumerOutput {
      case .none:
        break

      case .resumeBases(let suspendedBases):
        suspendedBases.forEach { $0.resume() }

      case .terminate(let task, let suspendedBases, let suspendedDemands):
        suspendedBases?.forEach { $0.resume() }
        suspendedDemands?.forEach { $0?.resume(returning: nil) }
        task?.cancel()
    }
  }

  private func handle(demandIsFulfilledOutput: StateMachine.DemandIsFulfilledOutput) {
    switch demandIsFulfilledOutput {
      case .none:
        break

      case .terminate(let task, let suspendedBases, let suspendedDemands):
        suspendedBases?.forEach { $0.resume() }
        suspendedDemands?.forEach { $0.resume(returning: nil) }
        task?.cancel()
    }
  }
}
