///| Operation-layer counterpart to `algebra_merge_wbtest.mbt`.
///
/// The text-CRDT probe established the baseline: concurrent Rename x MoveParam
/// converges on `fn send(messagekind, msg)` — a parseable program with two
/// unbound variables. This file tests the paper's remedy using Canopy's
/// SHIPPED operation layer (`@edits.TreeEditOp` + `compute_text_edit`, which
/// resolves targets through the scope graph and enforces capture checks),
/// not a toy written for the occasion.
///
/// Pinned predictions (written before first run):
///   1. Replaying Rename as an operation on the post-move state yields the
///      intended merge, free variables 0.
///   2. Rename and SwapChildren applied as operations commute: both orders
///      produce the same intended text.
///   3. The same pair pushed through the text CRDT does not.
///   4. The operation layer REFUSES a capture-inducing rename that the text
///      layer would happily apply.

///|
/// Parse `text` and assemble the EditContext the shipped lowering needs.
fn build_ctx(text : String) -> @edits.EditContext[@ast.Term] raise {
  let (cst, _) = @lambda.parse_cst(text)
  let syntax = @seam.SyntaxNode::from_cst(cst)
  let proj = @lambda_proj.to_proj_node(syntax, Ref(0))
  let source_map = @core.SourceMap::from_ast(proj)
  @lambda_proj.populate_token_spans(source_map, syntax, proj)
  let registry : Map[@core.NodeId, @core.ProjNode[@ast.Term]] = Map([])
  @core.collect_registry(proj, registry)
  {
    source_text: text,
    source_map,
    registry,
    definition_index: @lambda_proj.DefinitionIndex::from_proj_node(proj),
  }
}

///|
/// Locate the Lam node binding `param`. Operations target semantic entities;
/// after a text-level change the entity is re-located structurally (the probe
/// stand-in for projection identity tracking).
fn find_lam_param(
  ctx : @edits.EditContext[@ast.Term],
  param : String,
) -> @core.NodeId raise {
  for id, node in ctx.registry {
    match node.kind {
      @ast.Term::Lam(p, _) => if p == param { return id }
      _ => ()
    }
  }
  fail("no lambda binding '" + param + "'")
}

///|
/// Locate the unique Bop node.
fn find_bop(ctx : @edits.EditContext[@ast.Term]) -> @core.NodeId raise {
  for id, node in ctx.registry {
    match node.kind {
      @ast.Term::Bop(_, _, _) => return id
      _ => ()
    }
  }
  fail("no Bop node")
}

///|
/// Lower `op` through the shipped pipeline and apply the resulting span
/// edits (reverse document order, same as the editor shell).
fn apply_op(
  text : String,
  op : @edits.TreeEditOp,
  ctx : @edits.EditContext[@ast.Term],
) -> String raise {
  guard @edits.compute_text_edit(op, ctx) is Some((edits, _)) else {
    fail("operation produced no edits")
  }
  let sorted = edits.copy()
  sorted.sort_by((a, b) => b.start.compare(a.start))
  let mut result = text
  for e in sorted {
    result = result[:e.start].to_owned() +
      e.inserted +
      result[e.start + e.delete_len:].to_owned()
  }
  result
}

///|
/// `Rename(binder of `old` -> new)` as a fresh lowering against `text`.
fn op_rename(text : String, old : String, new : String) -> String raise {
  let ctx = build_ctx(text)
  let lam = find_lam_param(ctx, old)
  apply_op(text, @edits.TreeEditOp::Rename(node_id=lam, new_name=new), ctx)
}

///|
/// `SwapChildren` on the unique Bop as a fresh lowering against `text`.
fn op_swap_operands(text : String) -> String raise {
  let ctx = build_ctx(text)
  let bop = find_bop(ctx)
  apply_op(text, @edits.TreeEditOp::SwapChildren(node_id=bop), ctx)
}

///|
/// PREDICTION 1 — bob's post-move text (identical under both MoveParam
/// lowerings measured in the CRDT probe) plus alice's Rename replayed as an
/// operation must equal the intended merge that the text CRDT missed.
test "operation replay heals the rename x move merge" {
  let moved =
    #|fn send(kind, msg) { msg + kind }
    #|send 1 2
  let healed = op_rename(moved, "msg", "message")
  let report =
    $|healed text:
    $|\{healed}
    $|matches intended semantic merge: \{healed == INTENDED_RENAME_X_MOVE}
    $|free variables: \{free_vars(healed)}
    $|(text-CRDT baseline for the same pair: free variables 2)
  inspect(
    report,
    content=(
      #|healed text:
      #|fn send(kind, message) { message + kind }
      #|send 1 2
      #|matches intended semantic merge: true
      #|free variables: 0
      #|(text-CRDT baseline for the same pair: free variables 2)
    ),
  )
}

///|
/// Base for the two-operation commutativity pair. Both directions exist as
/// shipped operations, so this is the paper's Fig. 4 in executable form.
const SMALL : String = "(x, y) => x + y"

///|
/// What Rename(x->a) and SwapChildren must jointly produce in either order.
const SMALL_INTENDED : String = "(a, y) => y + a"

///|
/// PREDICTION 2 — operation composition is symmetric for this pair.
test "operation-layer commutativity: rename x swap-operands" {
  let path_a = op_swap_operands(op_rename(SMALL, "x", "a"))
  let path_b = op_rename(op_swap_operands(SMALL), "x", "a")
  // The exact-text comparison exposed a trivia defect in the shipped
  // SwapChildren lowering (it drops the space after `=>`), so the report
  // separates semantic agreement from whitespace fidelity.
  let normalize = (s : String) => s.replace_all(old=" ", new="")
  let report =
    $|rename-then-swap: \{path_a}
    $|swap-then-rename: \{path_b}
    $|paths agree: \{path_a == path_b}
    $|matches intended exactly: \{path_a == SMALL_INTENDED}
    $|matches intended up to whitespace: \{normalize(path_a) == normalize(SMALL_INTENDED)}
    $|free variables: \{free_vars(path_a)}
  inspect(
    report,
    content=(
      #|rename-then-swap: (a, y) =>y + a
      #|swap-then-rename: (a, y) =>y + a
      #|paths agree: true
      #|matches intended exactly: false
      #|matches intended up to whitespace: true
      #|free variables: 0
    ),
  )
}

///|
/// PREDICTION 3 — the same operation pair through the text CRDT. Offsets in
/// `(x, y) => x + y`: param x = 1-2, body `x + y` = 10-15, body x = 10-11.
test "text CRDT on the same pair does not commute semantically" {
  let alice = @text.TextState::new("alice")
  let bob = @text.TextState::new("bob")
  alice.insert(@text.Pos::at(0), SMALL)
  let _ = bob.sync().apply(alice.sync().export_all())
  // alice: Rename(x -> a), declaration + use site, right-to-left
  alice.replace_range(@text.Range::from_ints(10, 11), "a")
  alice.replace_range(@text.Range::from_ints(1, 2), "a")
  // bob: SwapChildren lowered as the region rewrite `x + y` -> `y + x`
  bob.replace_range(@text.Range::from_ints(10, 15), "y + x")
  merge(alice, bob, alice_first=true)
  let report =
    $|converged: \{alice.text() == bob.text()}
    $|merged text: \{alice.text()}
    $|matches intended: \{alice.text() == SMALL_INTENDED}
    $|free variables: \{free_vars(alice.text())}
  inspect(
    report,
    content=(
      #|converged: true
      #|merged text: (a, y) => ay + x
      #|matches intended: false
      #|free variables: 2
    ),
  )
}

///|
/// PREDICTION 4 — the operation layer refuses `Rename(x -> y)` because `y`
/// is bound in the body: the "verified" half of the claim. The text layer
/// applies the same change without complaint.
test "capture check refuses what the text layer accepts" {
  let ctx = build_ctx(SMALL)
  let lam = find_lam_param(ctx, "x")
  let verdict = try {
    let _ = @edits.compute_text_edit(
      @edits.TreeEditOp::Rename(node_id=lam, new_name="y"),
      ctx,
    )
    "accepted"
  } catch {
    @core.EditError::CaptureViolation(detail~) => "refused: " + detail
    e => "refused (other): " + e.message()
  }
  let text_layer = {
    let doc = @text.TextState::new("alice")
    doc.insert(@text.Pos::at(0), SMALL)
    doc.replace_range(@text.Range::from_ints(10, 11), "y")
    doc.replace_range(@text.Range::from_ints(1, 2), "y")
    doc.text()
  }
  let report =
    $|operation layer: \{verdict}
    $|text layer result: \{text_layer}
    $|text layer free variables: \{free_vars(text_layer)}
  inspect(
    report,
    content=(
      #|operation layer: refused: Cannot rename: 'y' is bound by an inner scope at a usage site
      #|text layer result: (y, y) => y + y
      #|text layer free variables: 0
    ),
  )
}
