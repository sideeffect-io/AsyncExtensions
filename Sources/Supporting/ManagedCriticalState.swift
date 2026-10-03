import Synchronization

/// State guarded by a `Mutex`, with reference semantics so that iterators and state machines
/// can hold it by value and copy it.
struct ManagedCriticalState<State> {
  private final class Storage: @unchecked Sendable {
    let mutex: Mutex<State>

    init(_ initial: State) {
      mutex = Mutex(initial)
    }
  }

  private let storage: Storage

  init(_ initial: State) {
    storage = Storage(initial)
  }

  @discardableResult
  func withCriticalRegion<R>(_ critical: (inout State) throws -> R) rethrows -> R {
    try storage.mutex.withLock { state in try critical(&state) }
  }

  func apply(criticalState newState: State) {
    withCriticalRegion { $0 = newState }
  }

  var criticalState: State {
    withCriticalRegion { $0 }
  }
}

extension ManagedCriticalState: @unchecked Sendable where State: Sendable { }
