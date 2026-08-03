///|
let next_jsx_source_identity : Ref[Int] = { val: 0 }

///|
fn allocate_jsx_source_id() -> @loomcore.SourceId {
  let identity = next_jsx_source_identity.val
  next_jsx_source_identity.val = identity + 1
  @loomcore.SourceId("canopy-jsx-ffi:" + identity.to_string())
}
