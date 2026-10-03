import DequeModule

/// FIFO work protected by the owning subject's state lock.
/// Enqueue alongside state updates and subscriber snapshots. Only the caller that
/// changes `isDraining` from false to true may drain, after releasing that lock.
// swift-collections 1.0.3 does not declare Deque's Sendable conformance. This
// value contains only a value-semantic deque of Sendable closures and a Bool;
// all mutations are protected by the subject lock. Remove unchecked when the
// pinned dependency supplies Deque's conditional Sendable conformance.
struct SubjectDeliveryQueue: @unchecked Sendable {
  private var pending: Deque<@Sendable () -> Void> = []
  private var isDraining = false

  mutating func enqueue(_ delivery: @escaping @Sendable () -> Void) -> Bool {
    self.pending.append(delivery)
    guard !self.isDraining else { return false }
    self.isDraining = true
    return true
  }

  /// Take work under the subject lock; execute the returned closure outside it.
  /// Checking for an empty queue and releasing drainer ownership must be atomic
  /// with enqueue so a concurrent sender cannot leave work stranded.
  mutating func next() -> (@Sendable () -> Void)? {
    guard let delivery = self.pending.popFirst() else {
      self.isDraining = false
      return nil
    }
    return delivery
  }
}
