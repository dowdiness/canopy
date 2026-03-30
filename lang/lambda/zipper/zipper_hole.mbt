///|
pub(all) struct HoleInfo {
  created_by : EditAction
  role : PositionRole
} derive(Show)

///|
pub(all) struct HoleRegistry {
  priv next_id : Ref[Int]
  priv holes : Map[@core.NodeId, HoleInfo]
}

///|
pub fn HoleRegistry::new() -> HoleRegistry {
  { next_id: Ref::new(0), holes: {} }
}

///|
pub fn HoleRegistry::fresh_hole_id(self : HoleRegistry) -> Int {
  let id = self.next_id.val
  self.next_id.val = id + 1
  id
}

///|
pub fn HoleRegistry::register(
  self : HoleRegistry,
  node_id : @core.NodeId,
  info : HoleInfo,
) -> Unit {
  self.holes[node_id] = info
}

///|
pub fn HoleRegistry::get(
  self : HoleRegistry,
  node_id : @core.NodeId,
) -> HoleInfo? {
  self.holes.get(node_id)
}

///|
pub fn HoleRegistry::prune(
  self : HoleRegistry,
  live_ids : @immut/hashset.HashSet[@core.NodeId],
) -> Unit {
  let stale : Array[@core.NodeId] = []
  for id in self.holes.keys() {
    if !live_ids.contains(id) {
      stale.push(id)
    }
  }
  for id in stale {
    self.holes.remove(id)
  }
}
