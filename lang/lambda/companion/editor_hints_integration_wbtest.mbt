// Integration test for the structural-edit identity hint channel.
// Verifies that a WrapInLambda op preserves the wrapped node's NodeId
// across the subsequent reparse (Level-1 grove foundation).

///|
/// Return the body expression node from a projection root.
/// For texts with let defs the structure is Module([def, ...], body) and we
/// need `children[defs.length()]`. For a bare expression (no let defs) the
/// projection root IS the expression node directly (no Module wrapper).
fn body_of_bare_expr(
  root : @core.ProjNode[@ast.Term],
) -> @core.ProjNode[@ast.Term]? {
  match root.kind {
    @ast.Term::Module(defs, _) => root.children.get(defs.length())
    _ => Some(root)
  }
}

///|
test "WrapInLambda: inner node NodeId preserved after reconcile with hint" {
  let (editor, companion) = new_lambda_editor("hint-test")
  editor.set_text("x")

  // 1. First parse: capture body expression NodeId
  let old_body_id = match editor.get_proj_node() {
    None => fail("expected proj node for 'x'")
    Some(root) =>
      match body_of_bare_expr(root) {
        None => fail("expected module body child")
        Some(body) => body.id()
      }
  }

  // 2. Apply WrapInLambda: text becomes something like `(f) => x`
  let wrap_op = @lambda_edits.TreeEditOp::WrapInLambda(
    node_id=old_body_id,
    var_name="f",
  )
  match apply_lambda_tree_edit(editor, companion, wrap_op, 1) {
    Err(_) => fail("WrapInLambda failed")
    Ok(_) => ()
  }

  // 3. Reparse: find the Lambda's body child
  // After WrapInLambda the tree is Module → Lam(Param, body).
  // Module.children[0] = Lam node (new ID)
  // Lam.children[last] should be the body (old_body_id preserved).
  let new_body_id : @core.NodeId? = match editor.get_proj_node() {
    None => fail("expected proj node after wrap")
    Some(root) =>
      match body_of_bare_expr(root) {
        None => fail("expected module body after wrap")
        Some(lam) =>
          // Lambda body is the LAST child of the lambda node.
          lam.children.last().map(fn(c) { c.id() })
      }
  }

  match new_body_id {
    None => fail("lambda has no children")
    Some(nid) => inspect(nid == old_body_id, content="true")
  }
}

///|
/// Non-vacuity control: without a structural hint, LCS assigns a fresh NodeId
/// to the inner node after wrapping, proving the hinted test above exercises
/// the hint channel and not plain LCS behaviour.
test "WrapInLambda control: LCS alone does NOT preserve inner NodeId" {
  let (editor, _companion) = new_lambda_editor("control-test")
  editor.set_text("x")

  // 1. First parse: capture body expression NodeId
  let old_body_id = match editor.get_proj_node() {
    None => fail("expected proj node for 'x'")
    Some(root) =>
      match body_of_bare_expr(root) {
        None => fail("expected body node")
        Some(body) => body.id()
      }
  }

  // 2. Raw text replace bypasses the hint channel — pending_transforms stays
  //    empty so no Opaque taint, and the reconcile runs with an empty hints
  //    map (pure LCS). Old root was Var(x), new root is Lam(Param, Var(x));
  //    they differ in kind so LCS assigns a fresh NodeId to the inner Var(x).
  editor.set_text("(f) => x")

  // 3. Reparse and navigate to Lam's body child.
  //    body_of_bare_expr returns the Lam node (bare expression root);
  //    its last child is the body Var(x).
  let new_body_id : @core.NodeId? = match editor.get_proj_node() {
    None => fail("expected proj node after set_text")
    Some(root) =>
      match body_of_bare_expr(root) {
        None => fail("expected lam node")
        Some(lam) => lam.children.last().map(fn(c) { c.id() })
      }
  }

  match new_body_id {
    None => fail("lambda has no children")
    // LCS gives a fresh id: NOT equal to old_body_id
    Some(nid) => inspect(nid == old_body_id, content="false")
  }
}
