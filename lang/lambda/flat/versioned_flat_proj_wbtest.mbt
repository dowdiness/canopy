///|
test "VersionedFlatProj Eq compares only changed_at" {
  let r0 = @incr.Revision::initial()
  let r1 = r0.next()
  // Two values with different `proj` payloads but identical changed_at are equal.
  let a = VersionedFlatProj::{ proj: None, changed_at: r0 }
  let b = VersionedFlatProj::{ proj: None, changed_at: r0 }
  assert_true(a == b)
  let c = VersionedFlatProj::{ proj: None, changed_at: r1 }
  assert_true(a != c)
}
