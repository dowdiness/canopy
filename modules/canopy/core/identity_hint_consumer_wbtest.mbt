// White-box contract for the core-owned identity-hint drain capability.
//
// Boundary matrix:
// - empty queue -> empty batch
// - multiple queued hints -> one ordered batch
// - a consumed batch -> absent from the next reconciliation pass
// - only the core memo shell can request a batch; adapters cannot mutate it

///|
test "IdentityHintConsumer drains one ordered batch at a time" {
  let pending : Ref[Array[IdentityTransform]] = Ref([
    IdentityTransform::Wrap(inner=NodeId::from_int(1)),
    IdentityTransform::Opaque,
  ])
  let consume_count = Ref(0)
  let consumer = IdentityHintConsumer::IdentityHintConsumer(fn() {
    consume_count.val = consume_count.val + 1
    let drained = pending.val.copy()
    pending.val.clear()
    drained
  })
  let first = consumer.take_pending()
  inspect(first.length(), content="2")
  inspect(first[0] is IdentityTransform::Wrap(inner=_), content="true")
  inspect(first[1] is IdentityTransform::Opaque, content="true")
  inspect(consumer.take_pending().is_empty(), content="true")
  inspect(consume_count.val, content="2")
}
