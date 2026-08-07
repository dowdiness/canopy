///|
/// Opaque consume-only capability for the framework-owned identity-hint queue.
///
/// `SyncEditor` constructs this handle over its private queue and gives it to
/// projection builders. Adapters can pass it to the core projection-memo shell
/// but cannot drain, push, pop, taint, replace, or retain the editor's mutable
/// queue.
pub struct IdentityHintConsumer {
  priv take_pending_impl : () -> Array[IdentityTransform]
}

///|
/// Construct a consume-only identity-hint capability.
///
/// This is infrastructure wiring for framework-owned queues. Language adapters
/// receive the resulting handle from `SyncEditor::new_with_builder`; they do
/// not construct or inject the editor's channel themselves.
pub fn IdentityHintConsumer::IdentityHintConsumer(
  take_pending : () -> Array[IdentityTransform],
) -> IdentityHintConsumer {
  { take_pending_impl: take_pending }
}

///|
/// Drain the ordered hints queued for the next reconciliation pass.
/// Kept package-private so only the core projection-memo shell can consume the
/// capability; language adapters cannot retain and drain it out of band.
fn IdentityHintConsumer::take_pending(
  self : IdentityHintConsumer,
) -> Array[IdentityTransform] {
  (self.take_pending_impl)()
}
