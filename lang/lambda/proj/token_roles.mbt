// Token-span role keys: the contract between `populate_token_spans` (which
// records the spans) and its consumers (`@scope.binder_span`, rename, semantic
// projection) that read them back. Every producer and consumer routes through
// these helpers rather than bare string literals — a drifting literal would
// silently turn a span lookup into `None` with no compile-time or test signal.

///|
/// Role key for a lambda parameter's name token (stored on the `Lam` node).
pub const PARAM_ROLE : String = "param"

///|
/// Role key for a `LetDef` node's binder name token.
pub const LET_DEF_NAME_ROLE : String = "name"

///|
/// Role key for a typed `fn` binding's keyword token (stored on the `LetDef`).
pub const FN_BINDING_KEYWORD_ROLE : String = "fn:keyword"

///|
/// Role key for a typed `fn` binding's full parameter-list span, including
/// type annotations and surrounding parentheses (stored on the `LetDef`).
pub const FN_BINDING_PARAM_LIST_ROLE : String = "fn:param-list"

///|
/// Role key for the first parameter name token of a non-empty typed `fn`
/// binding parameter list (stored on the `LetDef`). Absence means the `fn`
/// has an empty `()` parameter list.
pub const FN_BINDING_PARAM_NAME_ROLE : String = "fn:param-name"

///|
/// Role key for a typed `fn` binding's brace-delimited body span (stored on the
/// `LetDef`).
pub const FN_BINDING_BODY_ROLE : String = "fn:body"

///|
/// Role key for module def `def_index`'s name token (stored on the Module node).
/// Compatibility fallback while callers migrate to `LET_DEF_NAME_ROLE` on the
/// first-class LetDef node.
pub fn module_name_role(def_index : Int) -> String {
  "name:" + def_index.to_string()
}
