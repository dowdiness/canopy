// Lambda editor FFI — lifecycle, text I/O, handle registry

// Handle-based editor registry (supports multiple concurrent editors)

///|
priv struct LambdaHandle {
  editor : @editor.SyncEditor[@ast.Term]
  companion : @lang_lambda.LambdaCompanion
  typecheck : TypecheckBundle
}

///|
/// Typecheck pipeline memos; `scope` disposal only — the underlying
/// `Runtime` is owned by the editor's `Parser`.
priv struct TypecheckBundle {
  scope : @cells.Scope
  output : @cells.Memo[@typecheck.ModuleTypeResult]
}

///|
fn new_typecheck_bundle(
  rt : @cells.Runtime,
  syntax_tree : @cells.Memo[@seam.SyntaxNode?],
) -> TypecheckBundle {
  let scope = @cells.Scope::new(rt)
  let typed_term_memo : @cells.Memo[@typecheck.TypedTerm] = scope.memo(
    fn() {
      // `None` = lex error; must stay non-aborting so later edits recover.
      match syntax_tree.get() {
        Some(syntax) => @typecheck.convert_from_cst(syntax)
        None => @typecheck.TypedTerm::Error("parse")
      }
    },
    label="lambda-typed-term",
  )
  let output = @typecheck.build_typecheck_pipeline(rt, scope, typed_term_memo)
  { scope, output }
}

///|
let lambda_handles : Map[Int, LambdaHandle] = Map::new()

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
