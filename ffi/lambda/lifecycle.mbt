// Lambda editor FFI — lifecycle, text I/O, handle registry

// Handle-based editor registry (supports multiple concurrent editors)

///|
priv struct LambdaHandle {
  editor : @editor.SyncEditor[@ast.Term]
  companion : @lang_lambda.LambdaCompanion
  typecheck : TypecheckBundle
}

///|
/// Typecheck pipeline cells; `scope` disposal only — the underlying
/// `Runtime` is owned by the editor's `Parser`.
///
/// `observer` is both the read path and the GC anchor: Scope membership
/// alone does not register the underlying Derived's cell as a `gc_root`,
/// so without a persistent Observer the entire typecheck cone would be
/// eligible for sweep on any future `Runtime::gc()`. Mirrors loom-side
/// `TypecheckAttachment` in `examples/lambda/src/typed_parser.mbt`.
priv struct TypecheckBundle {
  scope : @cells.Scope
  observer : @cells.Observer[@typecheck.ModuleTypeResult]
}

///|
fn new_typecheck_bundle(
  rt : @cells.Runtime,
  syntax_tree : @cells.Derived[@seam.SyntaxNode],
) -> TypecheckBundle {
  let scope = @cells.Scope::new(rt)
  let typed_term_memo : @cells.Memo[@typecheck.TypedTerm] = scope.memo(
    fn() { @typecheck.convert_from_cst(syntax_tree.get_or_abort()) },
    label="lambda-typed-term",
  )
  let output = @typecheck.build_typecheck_pipeline(rt, scope, typed_term_memo)
  let observer = scope.add_observer(output.observe())
  // Prime the closure so `gc_dependencies` is populated before any gc cycle
  // could run — Observer alone is insufficient until the Memo has computed
  // once (see `feedback-incr-gc-anchor-needs-priming`).
  //
  // Side effect: this makes `create_editor` the failure boundary for any
  // typecheck panic, not `get_diagnostics_json`. Currently benign because a
  // freshly-created editor has an empty document and the pipeline is total
  // over empty input; if downstream stages ever become fallible here,
  // create_editor aborts instead of the FFI consumer receiving an empty
  // diagnostics result.
  let _prime = observer.get()
  { scope, observer }
}

///|
let lambda_handles : Map[Int, LambdaHandle] = Map::default()

///|
let next_handle : Ref[Int] = { val: 1 }

///|
let last_created_handle : Ref[Int?] = { val: None }

///|
/// Get the most recently created editor for legacy MoonBit consumers.
pub fn get_sync_editor() -> @editor.SyncEditor[@ast.Term]? {
  match last_created_handle.val {
    Some(handle) =>
      match lambda_handles.get(handle) {
        Some(h) => Some(h.editor)
        None => None
      }
    None => None
  }
}

///|
/// Get the companion for the most recently created lambda editor.
pub fn get_lambda_companion() -> @lang_lambda.LambdaCompanion? {
  match last_created_handle.val {
    Some(handle) =>
      match lambda_handles.get(handle) {
        Some(h) => Some(h.companion)
        None => None
      }
    None => None
  }
}

///|
/// Create a new SyncEditor instance.
/// Returns a unique handle for this editor.
pub fn create_editor(agent_id : String) -> Int {
  let handle = next_handle.val
  next_handle.val = handle + 1
  let (editor, companion) = @lang_lambda.new_lambda_editor(agent_id)
  lambda_handles[handle] = {
    editor,
    companion,
    typecheck: new_typecheck_bundle(
      editor.parser_runtime(),
      editor.parser_syntax_tree(),
    ),
  }
  last_created_handle.val = Some(handle)
  handle
}

///|
/// Destroy an editor instance and free its resources.
pub fn destroy_editor(handle : Int) -> Unit {
  match lambda_handles.get(handle) {
    Some(h) => h.typecheck.scope.dispose()
    None => ()
  }
  lambda_handles.remove(handle)
  view_states.remove(handle)
  pretty_view_states.remove(handle)
  if last_created_handle.val == Some(handle) {
    last_created_handle.val = None
  }
}

///|
/// Get current text content
pub fn get_text(handle : Int) -> String {
  match lambda_handles.get(handle) {
    Some(h) => h.editor.get_text()
    None => ""
  }
}

///|
/// Set text content directly (replaces entire document)
pub fn set_text(handle : Int, new_text : String) -> Unit {
  match lambda_handles.get(handle) {
    Some(h) => h.editor.set_text(new_text)
    None => ()
  }
}
