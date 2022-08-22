//
//  Zip3Runtime.swift
//  
//
//  Created by Thibault Wittemberg on 24/09/2022.
//

final class Zip3Runtime<Base1: AsyncSequence, Base2: AsyncSequence, Base3: AsyncSequence>: Sendable
where Base1: Sendable, Base1.Element: Sendable, Base2: Sendable, Base2.Element: Sendable, Base3: Sendable, Base3.Element: Sendable {
  typealias ZipStateMachine = Zip3StateMachine<Base1.Element, Base2.Element, Base3.Element>

  private let stateMachine = ManagedCriticalState(ZipStateMachine())

  init(_ base1: Base1, _ base2: Base2, _ base3: Base3) {
    self.stateMachine.withCriticalRegion { machine in
      machine.taskIsStarted(task: Task {
        await withTaskGroup(of: Void.self) { group in
          group.addTask {
            var base1Iterator = base1.makeAsyncIterator()

            do {
              while true {
                await withUnsafeContinuation { (continuation: UnsafeContinuation<Void, Never>) in
                  let output = self.stateMachine.withCriticalRegion { machine in
                    machine.newLoopFromBase1(suspendedBase: continuation)
                  }

                  self.handle(newLoopFromBaseOutput: output)
                }

                guard let element1 = try await base1Iterator.next() else {
                  break
                }

                let output = self.stateMachine.withCriticalRegion { machine in
                  machine.base1HasProducedElement(element: element1)
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

          group.addTask {
            var base2Iterator = base2.makeAsyncIterator()

            do {
              while true {
                await withUnsafeContinuation { (continuation: UnsafeContinuation<Void, Never>) in
                  let output = self.stateMachine.withCriticalRegion { machine in
                    machine.newLoopFromBase2(suspendedBase: continuation)
                  }

                  self.handle(newLoopFromBaseOutput: output)
                }

                guard let element2 = try await base2Iterator.next() else {
                  break
                }

                let output = self.stateMachine.withCriticalRegion { machine in
                  machine.base2HasProducedElement(element: element2)
                }

                self.handle(baseHasProducedElementOutput: output)
              }
            } catch {
              let output = self.stateMachine.withCriticalRegion { machine in
                machine.baseHasProducedFailure(error: error)
              }

              self.handle(baseHasProducedFailureOutput: output)
            }

            let output = self.stateMachine.withCriticalRegion { machine in
              machine.baseIsFinished()
            }

            self.handle(baseIsFinishedOutput: output)
          }

          group.addTask {
            var base3Iterator = base3.makeAsyncIterator()

            do {
              while true {
                await withUnsafeContinuation { (continuation: UnsafeContinuation<Void, Never>) in
                  let output = self.stateMachine.withCriticalRegion { machine in
                    machine.newLoopFromBase3(suspendedBase: continuation)
                  }

                  self.handle(newLoopFromBaseOutput: output)
                }

                guard let element3 = try await base3Iterator.next() else {
                  break
                }

                let output = self.stateMachine.withCriticalRegion { machine in
                  machine.base3HasProducedElement(element: element3)
                }

                self.handle(baseHasProducedElementOutput: output)
              }
            } catch {
              let output = self.stateMachine.withCriticalRegion { machine in
                machine.baseHasProducedFailure(error: error)
              }

              self.handle(baseHasProducedFailureOutput: output)
            }

            let output = self.stateMachine.withCriticalRegion { machine in
              machine.baseIsFinished()
            }

            self.handle(baseIsFinishedOutput: output)
          }
        }
      })
    }
  }

  private func handle(newLoopFromBaseOutput: ZipStateMachine.NewLoopFromBaseOutput) {
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

  private func handle(baseHasProducedElementOutput: ZipStateMachine.BaseHasProducedElementOutput) {
    switch baseHasProducedElementOutput {
      case .none:
        break

      case .resumeDemand(let suspendedDemand, let result1, let result2, let result3):
        suspendedDemand?.resume(returning: (result1, result2, result3))

      case .terminate(let task, let suspendedBases):
        suspendedBases?.forEach { $0.resume() }
        task?.cancel()
    }
  }

  private func handle(baseHasProducedFailureOutput: ZipStateMachine.BaseHasProducedFailureOutput) {
    switch baseHasProducedFailureOutput {
      case .resumeDemandAndTerminate(let task, let suspendedDemand, let suspendedBases, let result1, let result2, let result3):
        suspendedDemand?.resume(returning: (result1, result2, result3))
        suspendedBases.forEach { $0.resume() }
        task?.cancel()

      case .terminate(let task, let suspendedBases):
        suspendedBases?.forEach { $0.resume() }
        task?.cancel()
    }
  }

  private func handle(baseIsFinishedOutput: ZipStateMachine.BaseIsFinishedOutput) {
    switch baseIsFinishedOutput {
      case .terminate(let task, let suspendedBases, let suspendedDemands):
        suspendedBases?.forEach { $0.resume() }
        suspendedDemands?.forEach { $0?.resume(returning: nil) }
        task?.cancel()
    }
  }

  func next() async rethrows -> (Base1.Element, Base2.Element, Base3.Element)? {
    try await withTaskCancellationHandler {
      let output = self.stateMachine.withCriticalRegion { stateMachine in
        stateMachine.rootTaskIsCancelled()
      }

      self.handle(rootTaskIsCancelledOutput: output)
    } operation: {
      let results = await withUnsafeContinuation { (continuation: UnsafeContinuation<(Result<Base1.Element, Error>, Result<Base2.Element, Error>, Result<Base3.Element, Error>)?, Never>) in
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

      return try (results.0._rethrowGet(), results.1._rethrowGet(), results.2._rethrowGet())
    }
  }

  private func handle(rootTaskIsCancelledOutput: ZipStateMachine.RootTaskIsCancelledOutput) {
    switch rootTaskIsCancelledOutput {
      case .terminate(let task, let suspendedBases, let suspendedDemands):
        suspendedBases?.forEach { $0.resume() }
        suspendedDemands?.forEach { $0?.resume(returning: nil) }
        task?.cancel()
    }
  }

  private func handle(newDemandFromConsumerOutput: ZipStateMachine.NewDemandFromConsumerOutput) {
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

  private func handle(demandIsFulfilledOutput: ZipStateMachine.DemandIsFulfilledOutput) {
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
