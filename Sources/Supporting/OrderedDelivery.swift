import DequeModule

/// Delivers subject events in the same order that their state updates are recorded.
/// The queue lock is released before a delivery resumes any consumer.
final class OrderedDelivery: @unchecked Sendable {
  private struct State {
    var pending: Deque<@Sendable () -> Void> = []
    var isDelivering = false
  }

  private let state = ManagedCriticalState(State())

  /// Queues a delivery and returns true when the caller should start draining.
  func enqueue(_ delivery: @escaping @Sendable () -> Void) -> Bool {
    self.state.withCriticalRegion { state in
      state.pending.append(delivery)
      guard !state.isDelivering else { return false }
      state.isDelivering = true
      return true
    }
  }

  /// Drains queued deliveries without holding the queue lock while they run.
  func drain() {
    while let delivery = self.state.withCriticalRegion({ state -> (@Sendable () -> Void)? in
      guard !state.pending.isEmpty else {
        state.isDelivering = false
        return nil
      }
      return state.pending.popFirst()
    }) {
      delivery()
    }
  }
}
