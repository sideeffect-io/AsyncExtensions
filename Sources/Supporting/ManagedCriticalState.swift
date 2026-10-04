import Synchronization

// Copies of iterators and callbacks must keep sharing the same protected state.
final class ManagedCriticalState<State> {
  private let state: Mutex<State>

  init(_ initial: State) {
    self.state = Mutex(initial)
  }

  @discardableResult
  func withCriticalRegion<R>(
    _ critical: (inout State) throws -> R
  ) rethrows -> R {
    try self.state.withLock { state in
      try critical(&state)
    }
  }

  func apply(criticalState newState: State) {
    self.withCriticalRegion { actual in
      actual = newState
    }
  }

  var criticalState: State {
    self.withCriticalRegion { $0 }
  }
}

extension ManagedCriticalState: Sendable where State: Sendable { }
