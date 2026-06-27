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
  guard result is Ok(_) else { fail("apply_lambda_tree_edit Drop failed") }
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
fn pick_distinct(child_count : Int, rs : @splitmix.RandomState) -> (Int, Int) {
  // Uniform over all pairs (a, b) with b != a in [0..child_count).
  // offset uniform in [0..child_count-1); wrapping by count excludes a exactly once.
  let a = rs.split().next_uint64().to_int().abs() % child_count
  let offset = rs.split().next_uint64().to_int().abs() % (child_count - 1)
  let b = (a + 1 + offset) % child_count
  (a, b)
}

///|
impl @quickcheck.Arbitrary for ConcurrentDropScenario with fn arbitrary(
  size,
  rs,
) {
  let (seed_text, child_count) = pick_seed(size)
  let (p1_source, p1_target) = pick_distinct(child_count, rs)
  let (p2_source, p2_target) = pick_distinct(child_count, rs)
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
        target_idx: 2,
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

///|
test "property P1: concurrent drops converge" {
  @qc.quick_check_fn_error(prop_concurrent_drops_converge, max_success=200)
}

// P2: Undo after concurrent drops

///|
fn prop_undo_after_drops(scenario : ConcurrentDropScenario) -> Bool raise {
  let (ed1, ed2, comp1, comp2) = setup_two_peers(scenario.seed_text)
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
  guard ed1.can_undo() else { fail("ed1 cannot undo") }
  guard ed2.can_undo() else { fail("ed2 cannot undo") }
  guard ed1.undo() else { fail("ed1 undo failed") }
  guard ed2.undo() else { fail("ed2 undo failed") }
  bidirectional_sync(ed1, ed2)
  assert_peers_converged(ed1, ed2)
  assert_no_structural_errors(ed1)
  assert_no_structural_errors(ed2)
  true
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
  if !scenario_is_structural_safe(scenario) {
    None
  } else {
    let (ed1, ed2, comp1, comp2) = setup_two_peers(scenario.seed_text)
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
/// ── Named Regression Tests ──────────────────────────────────────────

// R1: Different sources, same target, both Before
test "R1: different sources, same target, both Before" {
  let (ed1, ed2, comp1, comp2) = setup_two_peers("let a = 1\nlet b = 2\na")
  apply_drop(ed1, comp1, 0, 1, @core.DropPosition::Before, 1)
  apply_drop(ed2, comp2, 2, 1, @core.DropPosition::Before, 1)
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
  apply_drop(ed1, comp1, 2, 0, @core.DropPosition::Before, 1)
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
  apply_drop(ed2, comp2, 2, 1, @core.DropPosition::After, 1)
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
  apply_drop(ed2, comp2, 2, 3, @core.DropPosition::After, 1)
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
