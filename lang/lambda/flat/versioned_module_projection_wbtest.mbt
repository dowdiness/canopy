///|
test "VersionedModuleProjection Eq compares only changed_at" {
  let r0 = @incr.Revision::initial()
  let r1 = r0.next()
  // Two values with DIFFERENT `proj` payloads but identical changed_at must be
  // equal — this is the load-bearing invariant for backdating.
  let with_none = VersionedModuleProjection::{ proj: None, changed_at: r0 }
  let with_some = VersionedModuleProjection::{
    proj: Some(@lambda_proj.ModuleProjection::empty()),
    changed_at: r0,
  }
  assert_true(with_none == with_some)
  // Two values with identical proj but DIFFERENT changed_at must be unequal.
  let c = VersionedModuleProjection::{ proj: None, changed_at: r1 }
  assert_true(with_none != c)
}
