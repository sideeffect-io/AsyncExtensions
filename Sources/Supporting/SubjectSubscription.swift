// Iterator copies share a registration. Remove it when their last copy is released, or when
// iteration is cancelled. Subject unregistration is idempotent and protected by its state lock.
final class SubjectSubscription: Sendable {
  let unregister: @Sendable () -> Void

  init(unregister: @Sendable @escaping () -> Void) {
    self.unregister = unregister
  }

  deinit { unregister() }
}
