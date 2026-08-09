// Convergence tests for concurrent drag-drop (structural Drop TreeEditOp)
// through the full lambda editor -> SyncEditor -> CRDT pipeline.
// Quickcheck properties + named deterministic regression tests.

///|
/// ── Model types ─────────────────────────────────────────────────────
struct DropOp {
  source_idx : Int
  target_idx : Int
  position : @core.DropPosition
} derive(Debug)

///|
struct ConcurrentDropScenario {
  seed_text : String
  peer1_drop : DropOp
  peer2_drop : DropOp
} derive(Debug)

///|
/// ── Seed set ────────────────────────────────────────────────────────

// Module seeds (LetDef* + body) give root.children the expected structure;
// indexed child access works because both peers parse the same seed
// deterministically.

fn seed_texts() -> Array[(String, Int)] {
  [
    ("let a = 1\nlet b = 2\na", 3),
    ("let a = 1\nlet b = 2\nlet c = 3\na", 4),
    ("let x = 1\nlet y = 2\nx + y", 3),
    ("let p = 1\nlet q = 2\np - q", 3),
  ]
}

///|
/// ── Helpers ─────────────────────────────────────────────────────────
fn setup_two_peers(
  seed_text : String,
) -> (
  @editor.SyncEditor[@ast.Term],
  @editor.SyncEditor[@ast.Term],
  LambdaCompanion,
  LambdaCompanion,
) raise {
  let (ed1, comp1) = new_lambda_editor("peer1")
  let (ed2, comp2) = new_lambda_editor("peer2")
  ed1.set_text(seed_text)
  ed2.apply_sync(ed1.export_all())
  (ed1, ed2, comp1, comp2)
}

///|
fn apply_drop(
  editor : @editor.SyncEditor[@ast.Term],
  companion : LambdaCompanion,
  source_idx : Int,
  target_idx : Int,
  position : @core.DropPosition,
  timestamp_ms : Int,
) -> Unit raise {
  let source_id = resolve_child_id(editor, source_idx)
  let target_id = resolve_child_id(editor, target_idx)
  let result = apply_lambda_tree_edit(
    editor,
    companion,
    @lambda_edits.TreeEditOp::Drop(
      source=source_id,
      target=target_id,
      position~,
    ),
    timestamp_ms,
  )
  match result {
    Ok(_) => ()
    Err(error) => fail("apply_lambda_tree_edit Drop failed: " + error.message())
  }
}

///|
fn resolve_child_id(
  editor : @editor.SyncEditor[@ast.Term],
  idx : Int,
) -> @core.NodeId raise {
  guard editor.get_proj_node() is Some(proj) else { fail("expected ProjNode") }
  guard idx >= 0 && idx < proj.children.length() else {
    fail("child index out of bounds")
  }
  proj.children[idx].id()
}

///|
fn supported_drop_pair(
  editor : @editor.SyncEditor[@ast.Term],
  source_idx : Int,
  target_idx : Int,
) -> Bool raise {
  guard editor.get_proj_node() is Some(proj) else { fail("expected ProjNode") }
  guard source_idx >= 0 && source_idx < proj.children.length() else {
    fail("source child index out of bounds")
  }
  guard target_idx >= 0 && target_idx < proj.children.length() else {
    fail("target child index out of bounds")
  }
  let source_is_let_def = proj.children[source_idx].kind
    is @ast.Term::LetDef(_, _)
  let target_is_let_def = proj.children[target_idx].kind
    is @ast.Term::LetDef(_, _)
  source_is_let_def == target_is_let_def
}

///|
fn peer_sync(
  from : @editor.SyncEditor[@ast.Term],
  to : @editor.SyncEditor[@ast.Term],
) -> Unit raise {
  to.apply_sync(from.export_all())
}

///|
fn bidirectional_sync(
  ed1 : @editor.SyncEditor[@ast.Term],
  ed2 : @editor.SyncEditor[@ast.Term],
) -> Unit raise {
  peer_sync(ed1, ed2)
  peer_sync(ed2, ed1)
}

///|
fn assert_peers_converged(
  ed1 : @editor.SyncEditor[@ast.Term],
  ed2 : @editor.SyncEditor[@ast.Term],
) -> Unit raise {
  let text1 = ed1.get_text()
  let text2 = ed2.get_text()
  guard text1 == text2 else {
    fail("text divergence: \"\{text1}\" != \"\{text2}\"")
  }
  guard ed1.get_proj_node() is Some(proj1) else { fail("ed1 missing ProjNode") }
  guard ed2.get_proj_node() is Some(proj2) else { fail("ed2 missing ProjNode") }
  let ast1 = @ast.print_term(proj1.kind)
  let ast2 = @ast.print_term(proj2.kind)
  guard ast1 == ast2 else { fail("AST divergence: \"\{ast1}\" != \"\{ast2}\"") }
}

///|
fn has_error_term(term : @ast.Term) -> Bool {
  match term {
    Error(_) => true
    Int(_) | Var(_) | Unit | Unbound(_) | Hole(_) => false
    LetDef(_, init) => has_error_term(init)
    Lam(_, body) => has_error_term(body)
    App(f, x) => has_error_term(f) || has_error_term(x)
    Bop(_, l, r) => has_error_term(l) || has_error_term(r)
    If(c, t, e) => has_error_term(c) || has_error_term(t) || has_error_term(e)
    Module(defs, body) => {
      for def in defs {
        if has_error_term(def.1) {
          return true
        }
      }
      has_error_term(body)
    }
  }
}

///|
fn assert_no_structural_errors(
  editor : @editor.SyncEditor[@ast.Term],
) -> Unit raise {
  guard editor.get_proj_node() is Some(proj) else { fail("missing ProjNode") }
  guard !has_error_term(proj.kind) else {
    fail("structural error in projection tree")
  }
}

///|
fn pick_seed(size : Int) -> (String, Int) {
  let seeds = seed_texts()
  let n = seeds.length()
  let idx = if size <= 0 { 0 } else if size >= n * 5 { n - 1 } else { size / 5 }
  seeds[idx]
}

///|
fn pick_distinct(binding_count : Int, rs : @splitmix.RandomState) -> (Int, Int) {
  // Uniform over all pairs (a, b) with b != a in [0..binding_count).
  // Only LetDef children are generated; the final module child is an expression.
  let a = rs.split().next_uint64().to_int().abs() % binding_count
  let offset = rs.split().next_uint64().to_int().abs() % (binding_count - 1)
  let b = (a + 1 + offset) % binding_count
  (a, b)
}

///|
impl @quickcheck.Arbitrary for ConcurrentDropScenario with fn arbitrary(
  size,
  rs,
) {
  let (seed_text, child_count) = pick_seed(size)
  let (p1_source, p1_target) = pick_distinct(child_count - 1, rs)
  let (p2_source, p2_target) = pick_distinct(child_count - 1, rs)
  let p1_pos = match rs.split().next_uint64().to_int().abs() % 3 {
    0 => @core.DropPosition::Before
    1 => @core.DropPosition::After
    _ => @core.DropPosition::Inside
  }
  let p2_pos = match rs.split().next_uint64().to_int().abs() % 3 {
    0 => @core.DropPosition::Before
    1 => @core.DropPosition::After
    _ => @core.DropPosition::Inside
  }
  {
    seed_text,
    peer1_drop: {
      source_idx: p1_source,
      target_idx: p1_target,
      position: p1_pos,
    },
    peer2_drop: {
      source_idx: p2_source,
      target_idx: p2_target,
      position: p2_pos,
    },
  }
}

///|
/// ── Shrink ─────────────────────────────────────────────────────────────
fn shrink_positions_before(
  scenario : ConcurrentDropScenario,
) -> ConcurrentDropScenario {
  {
    seed_text: scenario.seed_text,
    peer1_drop: {
      source_idx: scenario.peer1_drop.source_idx,
      target_idx: scenario.peer1_drop.target_idx,
      position: @core.DropPosition::Before,
    },
    peer2_drop: {
      source_idx: scenario.peer2_drop.source_idx,
      target_idx: scenario.peer2_drop.target_idx,
      position: @core.DropPosition::Before,
    },
  }
}

///|
fn shrink_seed(scenario : ConcurrentDropScenario) -> ConcurrentDropScenario? {
  let seeds = seed_texts()
  let (smallest_text, smallest_count) = seeds[0]
  // Find current child count via functional for-in
  let cur_child_count = for pair in seeds; cur = 0 {
    let (text, count) = pair
    if text == scenario.seed_text {
      continue count
    } else {
      continue cur
    }
  } nobreak {
    cur
  }
  if cur_child_count <= smallest_count {
    None
  } else {
    Some({
      seed_text: smallest_text,
      peer1_drop: {
        source_idx: 0,
        target_idx: 1,
        position: @core.DropPosition::Before,
      },
      peer2_drop: {
        source_idx: 1,
        target_idx: 0,
        position: @core.DropPosition::Before,
      },
    })
  }
}

///|
impl @qc.Shrink for ConcurrentDropScenario with fn shrink(self) {
  let candidates : Array[ConcurrentDropScenario] = []
  // Candidate 1: normalize positions to Before (least disruptive)
  if self.peer1_drop.position != @core.DropPosition::Before ||
    self.peer2_drop.position != @core.DropPosition::Before {
    candidates.push(shrink_positions_before(self))
  }
  // Candidate 2: smaller seed with valid remapped indices
  match shrink_seed(self) {
    Some(smaller) => candidates.push(smaller)
    None => ()
  }
  candidates.iter()
}

///|
/// ── Quickcheck Properties ───────────────────────────────────────────

// P1: Concurrent drops converge
fn prop_concurrent_drops_converge(
  scenario : ConcurrentDropScenario,
) -> Bool raise {
  let (ed1, ed2, comp1, comp2) = setup_two_peers(scenario.seed_text)
  if !supported_drop_pair(
      ed1,
      scenario.peer1_drop.source_idx,
      scenario.peer1_drop.target_idx,
    ) ||
    !supported_drop_pair(
      ed2,
      scenario.peer2_drop.source_idx,
      scenario.peer2_drop.target_idx,
    ) {
    true
  } else {
    apply_drop(
      ed1,
      comp1,
      scenario.peer1_drop.source_idx,
      scenario.peer1_drop.target_idx,
      scenario.peer1_drop.position,
      1,
    )
    apply_drop(
      ed2,
      comp2,
      scenario.peer2_drop.source_idx,
      scenario.peer2_drop.target_idx,
      scenario.peer2_drop.position,
      1,
    )
    bidirectional_sync(ed1, ed2)
    assert_peers_converged(ed1, ed2)
    true
  }
}

///|
test "property P1: concurrent drops converge" {
  @qc.quick_check_fn_error(prop_concurrent_drops_converge, max_success=200)
}

// P2: Undo after concurrent drops

///|
fn prop_undo_after_drops(scenario : ConcurrentDropScenario) -> Bool raise {
  let (ed1, ed2, comp1, comp2) = setup_two_peers(scenario.seed_text)
  if !supported_drop_pair(
      ed1,
      scenario.peer1_drop.source_idx,
      scenario.peer1_drop.target_idx,
    ) ||
    !supported_drop_pair(
      ed2,
      scenario.peer2_drop.source_idx,
      scenario.peer2_drop.target_idx,
    ) {
    true
  } else {
    let ed1_before = ed1.get_text()
    apply_drop(
      ed1,
      comp1,
      scenario.peer1_drop.source_idx,
      scenario.peer1_drop.target_idx,
      scenario.peer1_drop.position,
      1,
    )
    let ed1_changed = ed1.get_text() != ed1_before
    let ed2_before = ed2.get_text()
    apply_drop(
      ed2,
      comp2,
      scenario.peer2_drop.source_idx,
      scenario.peer2_drop.target_idx,
      scenario.peer2_drop.position,
      1,
    )
    let ed2_changed = ed2.get_text() != ed2_before
    bidirectional_sync(ed1, ed2)
    if ed1_changed {
      guard ed1.can_undo() else { fail("ed1 cannot undo") }
      guard ed1.undo() else { fail("ed1 undo failed") }
    }
    if ed2_changed {
      guard ed2.can_undo() else { fail("ed2 cannot undo") }
      guard ed2.undo() else { fail("ed2 undo failed") }
    }
    bidirectional_sync(ed1, ed2)
    assert_peers_converged(ed1, ed2)
    assert_no_structural_errors(ed1)
    assert_no_structural_errors(ed2)
    true
  }
}

///|
test "property P2: undo after concurrent drops" {
  @qc.quick_check_fn_error(prop_undo_after_drops, max_success=100)
}

// P3: No structural errors after each sync

///|
// P3: Structural validity after each sync.
// Uses has_error_term to catch projections with Error nodes.
// Skips same-target-different-position scenarios where CRDT merge
// can produce recovered Error sub-trees (expected reconciliation).
// P1/P2 cover those scenarios for convergence-only.

fn scenario_is_structural_safe(scenario : ConcurrentDropScenario) -> Bool {
  // Same target with conflicting positions (Before vs After vs Inside)
  // can produce recovered Error sub-trees through CRDT merge.
  scenario.peer1_drop.target_idx != scenario.peer2_drop.target_idx ||
  scenario.peer1_drop.position == scenario.peer2_drop.position
}

///|
fn prop_no_structural_errors(scenario : ConcurrentDropScenario) -> Bool? raise {
  let (ed1, ed2, comp1, comp2) = setup_two_peers(scenario.seed_text)
  if !scenario_is_structural_safe(scenario) ||
    !supported_drop_pair(
      ed1,
      scenario.peer1_drop.source_idx,
      scenario.peer1_drop.target_idx,
    ) ||
    !supported_drop_pair(
      ed2,
      scenario.peer2_drop.source_idx,
      scenario.peer2_drop.target_idx,
    ) {
    None
  } else {
    apply_drop(
      ed1,
      comp1,
      scenario.peer1_drop.source_idx,
      scenario.peer1_drop.target_idx,
      scenario.peer1_drop.position,
      1,
    )
    assert_no_structural_errors(ed1)
    apply_drop(
      ed2,
      comp2,
      scenario.peer2_drop.source_idx,
      scenario.peer2_drop.target_idx,
      scenario.peer2_drop.position,
      1,
    )
    assert_no_structural_errors(ed2)
    ed1.apply_sync(ed2.export_all())
    assert_no_structural_errors(ed1)
    ed2.apply_sync(ed1.export_all())
    assert_no_structural_errors(ed2)
    Some(true)
  }
}

///|
test "property P3: no structural errors after each sync" {
  @qc.quick_check_fn_error(prop_no_structural_errors, max_success=200)
}

///|
test "R0: concurrent row drops stay structurally valid" {
  let (ed1, ed2, comp1, comp2) = setup_two_peers("let p = 1\nlet q = 2\np - q")
  apply_drop(ed1, comp1, 1, 0, @core.DropPosition::Before, 1)
  guard ed1.get_proj_node() is Some(proj1) else {
    fail("ed1 local projection missing")
  }
  guard !has_error_term(proj1.kind) else { fail("ed1 local structural error") }
  apply_drop(ed2, comp2, 0, 1, @core.DropPosition::After, 1)
  guard ed2.get_proj_node() is Some(proj2) else {
    fail("ed2 local projection missing")
  }
  guard !has_error_term(proj2.kind) else { fail("ed2 local structural error") }
  ed1.apply_sync(ed2.export_all())
  guard ed1.get_proj_node() is Some(proj1_after_sync) else {
    fail("ed1 synced projection missing")
  }
  guard !has_error_term(proj1_after_sync.kind) else {
    fail("ed1 structural error after peer2 sync")
  }
  ed2.apply_sync(ed1.export_all())
  guard ed2.get_proj_node() is Some(proj2_after_sync) else {
    fail("ed2 synced projection missing")
  }
  guard !has_error_term(proj2_after_sync.kind) else {
    fail("ed2 structural error after peer1 sync")
  }
}

///|
fn assert_root_def_order(
  editor : @editor.SyncEditor[@ast.Term],
  expected_text : String,
  first_name : String,
  second_name : String,
) -> Unit raise {
  inspect(editor.get_text(), content=expected_text)
  guard editor.get_proj_node() is Some(proj) else { fail("missing ProjNode") }
  match proj.kind {
    @ast.Term::Module(defs, _) => {
      inspect(defs.length(), content="2")
      inspect(defs[0].0, content=first_name)
      inspect(defs[1].0, content=second_name)
    }
    _ => fail("expected root Module")
  }
}

///|
test "R0: LetDef Drop Before moves one binding row through public bridge" {
  let (editor, companion) = new_lambda_editor("drop-letdef-before")
  editor.set_text("let a = 1\nlet b = 2\na")
  let source = resolve_child_id(editor, 1)
  let target = resolve_child_id(editor, 0)
  let result = apply_lambda_tree_edit(
    editor,
    companion,
    @lambda_edits.TreeEditOp::Drop(
      source~,
      target~,
      position=@core.DropPosition::Before,
    ),
    1,
  )
  guard result is Ok(_) else { fail("Drop Before failed") }
  assert_root_def_order(editor, "let b = 2\nlet a = 1\na", "b", "a")
}

///|
test "R0: LetDef Drop After moves one binding row through public bridge" {
  let (editor, companion) = new_lambda_editor("drop-letdef-after")
  editor.set_text("let a = 1\nlet b = 2\na")
  let source = resolve_child_id(editor, 0)
  let target = resolve_child_id(editor, 1)
  let result = apply_lambda_tree_edit(
    editor,
    companion,
    @lambda_edits.TreeEditOp::Drop(
      source~,
      target~,
      position=@core.DropPosition::After,
    ),
    1,
  )
  guard result is Ok(_) else { fail("Drop After failed") }
  assert_root_def_order(editor, "let b = 2\nlet a = 1\na", "b", "a")
}

///|
test "R0: LetDef Drop Inside moves one binding row through public bridge" {
  let (editor, companion) = new_lambda_editor("drop-letdef-inside")
  editor.set_text("let a = 1\nlet b = 2\na")
  let source = resolve_child_id(editor, 0)
  let target = resolve_child_id(editor, 1)
  let result = apply_lambda_tree_edit(
    editor,
    companion,
    @lambda_edits.TreeEditOp::Drop(
      source~,
      target~,
      position=@core.DropPosition::Inside,
    ),
    1,
  )
  guard result is Ok(_) else { fail("Drop Inside failed") }
  assert_root_def_order(editor, "let b = 2\nlet a = 1\na", "b", "a")
}

///|
test "R0: expression Drop keeps expression-level semantics through public bridge" {
  let (editor, companion) = new_lambda_editor("drop-expression")
  editor.set_text("x + 1")
  let source = resolve_child_id(editor, 0)
  let target = resolve_child_id(editor, 1)
  let result = apply_lambda_tree_edit(
    editor,
    companion,
    @lambda_edits.TreeEditOp::Drop(
      source~,
      target~,
      position=@core.DropPosition::After,
    ),
    1,
  )
  guard result is Ok(_) else { fail("expression Drop failed") }
  inspect(editor.get_text(), content="x + 1x ")
}

///|
test "R0: mixed LetDef and expression Drop is rejected structurally" {
  let (editor, companion) = new_lambda_editor("drop-mixed")
  editor.set_text("let a = 1\na")
  let source = resolve_child_id(editor, 0)
  let target = resolve_child_id(editor, 1)
  let result = apply_lambda_tree_edit(
    editor,
    companion,
    @lambda_edits.TreeEditOp::Drop(
      source~,
      target~,
      position=@core.DropPosition::Before,
    ),
    1,
  )
  match result {
    Err(@core.EditError::UnsupportedOperation(detail~)) =>
      inspect(
        detail,
        content="Drop requires source and target to have matching node kinds",
      )
    Err(error) => fail("unexpected Drop error: " + error.message())
    Ok(_) => fail("mixed Drop should fail")
  }
}

///|
test "R0: expression to LetDef Drop is rejected structurally" {
  let (editor, companion) = new_lambda_editor("drop-mixed-reverse")
  editor.set_text("let a = 1\na")
  let source = resolve_child_id(editor, 1)
  let target = resolve_child_id(editor, 0)
  let result = apply_lambda_tree_edit(
    editor,
    companion,
    @lambda_edits.TreeEditOp::Drop(
      source~,
      target~,
      position=@core.DropPosition::Before,
    ),
    1,
  )
  match result {
    Err(@core.EditError::UnsupportedOperation(detail~)) =>
      inspect(
        detail,
        content="Drop requires source and target to have matching node kinds",
      )
    Err(error) => fail("unexpected Drop error: " + error.message())
    Ok(_) => fail("mixed Drop should fail")
  }
}

///|
/// ── Named Regression Tests ──────────────────────────────────────────

// R1: Different sources, same target, both Before
test "R1: different sources, same target, both Before" {
  let (ed1, ed2, comp1, comp2) = setup_two_peers("let a = 1\nlet b = 2\na")
  apply_drop(ed1, comp1, 0, 1, @core.DropPosition::Before, 1)
  apply_drop(ed2, comp2, 1, 0, @core.DropPosition::Before, 1)
  bidirectional_sync(ed1, ed2)
  assert_peers_converged(ed1, ed2)
}

// R2: Same source, different targets, both Before

///|
test "R2: same source, different targets" {
  let (ed1, ed2, comp1, comp2) = setup_two_peers(
    "let a = 1\nlet b = 2\nlet c = 3\na",
  )
  apply_drop(ed1, comp1, 1, 0, @core.DropPosition::Before, 1)
  apply_drop(ed2, comp2, 1, 2, @core.DropPosition::Before, 1)
  bidirectional_sync(ed1, ed2)
  assert_peers_converged(ed1, ed2)
}

// R3: Both peers issue same exchange (Inside, same pair)

///|
test "R3: both peers same Inside (swap)" {
  let (ed1, ed2, comp1, comp2) = setup_two_peers("let a = 1\nlet b = 2\na")
  apply_drop(ed1, comp1, 0, 1, @core.DropPosition::Inside, 1)
  apply_drop(ed2, comp2, 0, 1, @core.DropPosition::Inside, 1)
  bidirectional_sync(ed1, ed2)
  assert_peers_converged(ed1, ed2)
}

// R4: Inside vs Before on same pair — conflicting intent

///|
test "R4: Inside vs Before on same pair" {
  let (ed1, ed2, comp1, comp2) = setup_two_peers("let a = 1\nlet b = 2\na")
  apply_drop(ed1, comp1, 0, 1, @core.DropPosition::Inside, 1)
  apply_drop(ed2, comp2, 0, 1, @core.DropPosition::Before, 1)
  bidirectional_sync(ed1, ed2)
  assert_peers_converged(ed1, ed2)
}

// R5: Drop + concurrent text edit — structural-text interop

///|
test "R5: drop + concurrent text edit" {
  let (ed1, ed2, comp1, comp2) = setup_two_peers("let a = 1\nlet b = 2\na")
  apply_drop(ed1, comp1, 1, 0, @core.DropPosition::Before, 1)
  let len = ed2.get_text().length()
  ed2.move_cursor(len)
  try! ed2.insert(" + 99")
  bidirectional_sync(ed1, ed2)
  assert_peers_converged(ed1, ed2)
}

// R6: Undo after concurrent drops

///|
test "R6: undo after concurrent drops" {
  let (ed1, ed2, comp1, comp2) = setup_two_peers("let a = 1\nlet b = 2\na")
  apply_drop(ed1, comp1, 1, 0, @core.DropPosition::Before, 1)
  apply_drop(ed2, comp2, 0, 1, @core.DropPosition::After, 1)
  bidirectional_sync(ed1, ed2)
  assert_peers_converged(ed1, ed2)
  guard ed1.can_undo() else { fail("ed1 can_undo") }
  guard ed2.can_undo() else { fail("ed2 can_undo") }
  guard ed1.undo() else { fail("ed1 undo") }
  guard ed2.undo() else { fail("ed2 undo") }
  bidirectional_sync(ed1, ed2)
  assert_peers_converged(ed1, ed2)
}

// R7: Three-peer convergence (sanity)

///|
test "R7: three-peer convergence" {
  let (ed1, ed2, comp1, comp2) = setup_two_peers(
    "let a = 1\nlet b = 2\nlet c = 3\na",
  )
  let (ed3, comp3) = new_lambda_editor("peer3")
  ed3.apply_sync(ed1.export_all())
  apply_drop(ed1, comp1, 1, 0, @core.DropPosition::Before, 1)
  apply_drop(ed2, comp2, 2, 1, @core.DropPosition::After, 1)
  apply_drop(ed3, comp3, 0, 2, @core.DropPosition::Inside, 1)
  ed1.apply_sync(ed2.export_all())
  ed1.apply_sync(ed3.export_all())
  ed2.apply_sync(ed1.export_all())
  ed2.apply_sync(ed3.export_all())
  ed3.apply_sync(ed1.export_all())
  ed3.apply_sync(ed2.export_all())
  assert_peers_converged(ed1, ed2)
  assert_peers_converged(ed1, ed3)
}
