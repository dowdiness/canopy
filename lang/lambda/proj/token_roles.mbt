// Token-span role keys: the contract between `populate_token_spans` (which
// records the spans) and its consumers (`@scope.binder_span`, rename, semantic
// projection) that read them back. Every producer and consumer routes through
// these helpers rather than bare string literals — a drifting literal would
// silently turn a span lookup into `None` with no compile-time or test signal.

///|
/// Role key for a lambda parameter's name token (stored on the `Lam` node).
pub const PARAM_ROLE : String = "param"

///|
/// Role key for module def `def_index`'s name token (stored on the Module node).
pub fn module_name_role(def_index : Int) -> String {
  "name:" + def_index.to_string()
}
