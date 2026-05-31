// Level-B incremental ↔ full differential through the REAL @incr memo stack
// (docs/TODO.md §20, code-review follow-up to PR #407).
//
// WHAT THIS PINS (and how it differs from the Level-A differential)
// The Level-A differential (`scope_incremental_differential_wbtest.mbt`) calls
// `to_flat_proj_incremental` DIRECTLY and rebuilds a FRESH SourceMap/registry
// (`from_ast`) each step — it never drives the production `@incr` memo stack.
// This file drives the actual `build_lambda_projection_memos` cells off a live
// `@loom.Parser`, applies an edit SEQUENCE via `parser.apply_edit`, reads the
// `registry_memo` + `source_map_memo` each step, and asserts the
// incrementally-maintained scope resolution agrees with a fresh FULL rebuild —
// thereby covering the memo's incremental PATCH paths that Level-A bypasses:
//   - the `changed_def_indices_ref` side-channel (projection_memo.mbt:26),
//   - the two-phase remove/add registry patch (projection_memo.mbt:177-215),
//   - the source-map `remove_subtree`/`patch_subtree`/`rebuild_ranges` patch
//     (projection_memo.mbt:251-293),
//   - the revision-skew "skipped → full rebuild" fallback
//     (projection_memo.mbt:170, 244).
//
// NON-VACUITY (feedback_differential_test_non_vacuity_every_path)
// A full-vs-full agreement test would pass even if the patch paths never fired.
// We prove the patch path actually ran on the asserted steps by IDENTITY: the
// patch branch mutates `prev_*_ref` IN PLACE and returns the SAME heap object,
// whereas a full rebuild allocates a FRESH object. So
// `physical_equal(before, after) == true` ⇒ the in-place patch branch fired (not
// a full rebuild). We rule out the other vacuity mode — a no-op that never
// recomputes — by making the edit RESOLUTION-VISIBLE (it turns a literal into a
// Var whose binding changes), so the differential against a fresh full parse of
// the new source can only pass if the memo actually recomputed. The skew test
// asserts the COMPLEMENT (`physical_equal == false`) on a step the fallback
// forces to a full rebuild, so both arms of the patch/rebuild branch are pinned.
//
// SCOPE / NON-GOALS
// Edits are ASCII-only (no λ), so a byte offset equals a UTF-16 code unit equals
// a char index and the minimal-diff `Edit` is unambiguous. Empty-source steps
// are out of scope (all sequences stay non-empty); a None projection on a
// non-empty source is treated as a hard failure, not a skipped comparison. Like
// Level-A this cannot catch a bug shared by both pipelines inside `@scope.build`;
// the frozen oracle in `scope_equivalence_wbtest.mbt` covers that blind spot.

///|
/// A live memo stack: a real `@loom.Parser` + the four production projection
/// memos, plus a `Scope`/`Watch` GC anchor (incr convention for long-lived
/// Deriveds). The anchor reads both terminal memos inside a tracked closure so a
/// single `Watch` roots the whole chain; because `@incr` is pull-based the anchor
/// is never evaluated unless read, so it does not perturb the per-memo read
/// cadence the skew test depends on (the skew test below verifies this — were the
/// Watch eager, that test's `physical_equal == false` assertion would fail).
struct LevelBStack {
  parser : @loom.Parser[@ast.Term]
  proj_memo : @incr.Derived[@lambda_flat.VersionedFlatProj]
  cached_proj_node : @incr.Derived[@core.ProjNode[@ast.Term]?]
  registry_memo : @incr.Derived[Map[@core.NodeId, @core.ProjNode[@ast.Term]]]
  source_map_memo : @incr.Derived[@core.SourceMap]
  scope : @incr.Scope
}

///|
fn LevelBStack::LevelBStack(source : String) -> LevelBStack {
  let parser = @loom.new_parser(source, @parser.lambda_grammar)
  let (proj_memo, cached_proj_node, registry_memo, source_map_memo) = @lambda_flat.build_lambda_projection_memos(
    parser,
  )
  let rt = parser.runtime()
  let scope = @incr.Scope::new(rt)
  // GC anchor: a Unit Derived depending on BOTH terminal memos, rooted by a
  // persistent Watch the Scope owns. Tracked-closure reads use `get_or_abort`.
  let anchor = scope.derived(
    fn() {
      ignore(registry_memo.get_or_abort())
      ignore(source_map_memo.get_or_abort())
    },
    label="level_b_anchor",
  )
  ignore(scope.add_watch(anchor.watch()))
  { parser, proj_memo, cached_proj_node, registry_memo, source_map_memo, scope }
}

///|
fn LevelBStack::dispose(self : LevelBStack) -> Unit {
  self.scope.dispose()
}

///|
/// Advance the parser by the minimal single-region edit turning `old` into `new`.
fn LevelBStack::apply(self : LevelBStack, old : String, new : String) -> Unit {
  self.parser.apply_edit(lb_minimal_edit(old, new), new)
}

///|
/// Minimal single-region replacement turning `old` into `new`, via common prefix
/// + common suffix. Offsets are UTF-16 code units (`code_unit_at` / `length`);
/// callers pass ASCII only, where code unit == byte == char, so the coordinates
/// handed to `apply_edit` are unambiguous.
fn lb_minimal_edit(old : String, new : String) -> @loomcore.Edit {
  let ol = old.length()
  let nl = new.length()
  let cap = if ol < nl { ol } else { nl }
  let mut p = 0
  while p < cap && old.code_unit_at(p) == new.code_unit_at(p) {
    p = p + 1
  }
  let mut s = 0
  while s < cap - p &&
        old.code_unit_at(ol - 1 - s) == new.code_unit_at(nl - 1 - s) {
    s = s + 1
  }
  @loomcore.Edit::new(p, ol - p - s, nl - p - s)
}

///|
/// Read the live memo stack and assert its incrementally-maintained scope
/// resolution agrees with a FRESH full rebuild of the same current source.
///
/// Reads BOTH `registry_memo` AND `source_map_memo` every call (Codex design
/// review): each memo tracks its own `*_last_revision_ref`, so reading only one
/// would let the other fall behind and take its revision-skew full-rebuild
/// fallback — correct, but it would silently stop exercising the patch path this
/// file targets. Comparison reuses the cross-pipeline PBT's pipeline-independent
/// leaves (`collect_var_refs`, `assert_same_var_refs`, `assert_lam_ranges_unique`,
/// `def_init_ranges`, `normalize_decl`, `@scope.binder_span`), so node-id values
/// are never compared raw.
fn assert_level_b_agrees(
  stack : LevelBStack,
  src : String,
  context : String,
) -> Unit raise {
  // Guard (Codex Q5): a wrong minimal-diff `Edit` would let `apply_edit` produce
  // a syntax tree that disagrees with a fresh parse of `src`, silently corrupting
  // the "full side" baseline and hiding a real divergence. Pin that the parser's
  // own current source equals the source we full-rebuild against.
  guard stack.parser.source().read_or_abort() == src else {
    fail(
      "[\{context}] parser source desynced from expected: minimal-diff Edit is wrong",
    )
  }
  // Memo side (the @incr stack under test). Read all four cells; read BOTH
  // downstream memos so neither skips a revision.
  let fp_opt = stack.proj_memo.read_or_abort().proj
  let root_opt = stack.cached_proj_node.read_or_abort()
  let reg_i = stack.registry_memo.read_or_abort()
  let sm_i = stack.source_map_memo.read_or_abort()
  guard fp_opt is Some(fp) && root_opt is Some(root) else {
    fail("[\{context}] memo projection is None on non-empty source: \{src}")
  }
  let g_i = @scope.build(fp, reg_i, sm_i)
  let ranges_i = def_init_ranges(root)
  // Full side: a fresh production rebuild of the same current source (the oracle
  // already used by the cross-pipeline PBT).
  let (proj_f, reg_f, g_f, sm_f) = production_graph_of(src)
  let ranges_f = def_init_ranges(proj_f)
  assert_resolution_agrees(
    ResolutionSide(
      graph=g_i,
      registry=reg_i,
      source_map=sm_i,
      ranges=ranges_i,
      value_label="memo",
      binder_label="memo",
    ),
    ResolutionSide(
      graph=g_f,
      registry=reg_f,
      source_map=sm_f,
      ranges=ranges_f,
      value_label="full",
      binder_label="full",
    ),
    context_prefix="[\{context}] ",
    binder_span_disagreement="binder span disagrees across memo/full",
  )
}

///|
/// Drive a non-empty edit sequence through the memo stack, asserting agreement
/// after every step (reading BOTH memos each step), and RETURN a per-step
/// patch/rebuild drive-log so the caller can `inspect` it.
///
/// Non-vacuity (feedback_differential_test_non_vacuity_every_path): a full-vs-full
/// agreement test passes even if the memo silently regressed to always-patch or
/// always-rebuild. These structural sequences exist to exercise the `_ => full
/// rebuild` arm, but agreement alone never proves which arm fired. The drive-log
/// records, per step, whether each memo kept object identity (`P` = the in-place
/// patch branch ran) or allocated fresh (`R` = full rebuild) — classification by
/// the same `physical_equal` identity the explicit patch/skew tests use.
/// Snapshotting it pins the arm actually taken at every step, so a regression that
/// flips a patch to a rebuild (or vice versa) changes the snapshot and fails the
/// test. Reads stay in lockstep (both memos every step), so no accidental revision
/// skew creeps in and the only rebuilds recorded are structural
/// (changed_def_indices = None).
fn lb_run_sequence(sources : Array[String]) -> String raise {
  guard sources.length() >= 1 else { fail("lb_run_sequence needs >=1 source") }
  let stack = LevelBStack(sources[0])
  assert_level_b_agrees(stack, sources[0], "init:\{sources[0]}")
  let mut log = ""
  for i in 1..<sources.length() {
    // Both memos are up-to-date here (the previous step read both), so these reads
    // return cached values and keep the two revisions in lockstep.
    let reg_before = stack.registry_memo.read_or_abort()
    let sm_before = stack.source_map_memo.read_or_abort()
    stack.apply(sources[i - 1], sources[i])
    let reg_after = stack.registry_memo.read_or_abort()
    let sm_after = stack.source_map_memo.read_or_abort()
    let r = if physical_equal(reg_before, reg_after) { "P" } else { "R" }
    let s = if physical_equal(sm_before, sm_after) { "P" } else { "R" }
    log = log + "reg\{r}/sm\{s} "
    assert_level_b_agrees(stack, sources[i], "edit\{i}:\{sources[i]}")
  }
  stack.dispose()
  log
}

// ---------------------------------------------------------------------------
// Core test 1 — non-vacuity: a structure-preserving def-init edit drives BOTH
// the registry and source-map IN-PLACE patch paths (identity preserved), and the
// resolution-visible change proves the memo actually recomputed.
// ---------------------------------------------------------------------------

///|
test "level-B: resolution-visible def-init edit patches registry+source_map in place" {
  let s0 = "let x = 1\nlet y = 2\nx"
  let stack = LevelBStack(s0)
  // Step 0: read BOTH memos (full rebuild on first parse; establishes the shared
  // object both `prev_*_ref` slots hold and the revision baseline).
  let reg0 = stack.registry_memo.read_or_abort()
  let sm0 = stack.source_map_memo.read_or_abort()
  assert_level_b_agrees(stack, s0, "init")
  // Edit def 1's init `2` -> `x` (one code unit, same length). def count (2) and
  // final_expr (`x`) are unchanged, so `to_flat_proj_incremental` reports
  // changed_def_indices = Some([1]) (def-init changes push the def index — pinned
  // by the Level-A non-vacuity test) and BOTH downstream memos take the IN-PLACE
  // patch branch. The new init `x` is a Var binding to def 0, so the differential
  // below would fail on a stale (non-recomputed) memo.
  let s1 = "let x = 1\nlet y = x\nx"
  stack.apply(s0, s1)
  let reg1 = stack.registry_memo.read_or_abort()
  let sm1 = stack.source_map_memo.read_or_abort()
  // (1) PATCH not full-rebuild: the patch branch mutates and returns the SAME
  // object; a full rebuild would allocate a fresh one. Identity ⇒ patch fired.
  inspect(physical_equal(reg0, reg1), content="true")
  inspect(physical_equal(sm0, sm1), content="true")
  // (2) Recompute happened (not a silent no-op): agreement with a fresh full
  // rebuild of `s1` requires the new y-init Var `x` to be present and resolve to
  // def 0; a stale memo (lacking it) would fail `assert_same_var_refs`.
  assert_level_b_agrees(stack, s1, "after-resolution-visible-patch")
  stack.dispose()
}

// ---------------------------------------------------------------------------
// Core test 2 — revision-skew fallback: reading only source_map after one edit
// leaves the registry's last_revision behind, so on the next edit the registry is
// FORCED to a full rebuild (fresh object), not a patch.
// ---------------------------------------------------------------------------

///|
test "level-B: revision skew forces registry full-rebuild (skipped fallback)" {
  let s0 = "let a = 1\nlet b = 2\nb"
  let stack = LevelBStack(s0)
  // Step 0: read BOTH → registry.last_revision == source_map.last_revision ==
  // proj_revision == 1.
  let reg0 = stack.registry_memo.read_or_abort()
  ignore(stack.source_map_memo.read_or_abort())
  assert_level_b_agrees(stack, s0, "init")
  // Edit A (def 1 init 2 -> 3): read ONLY source_map afterwards. proj_revision
  // advances to 2 and source_map patches to 2; the registry stays at revision 1.
  let sA = "let a = 1\nlet b = 3\nb"
  stack.apply(s0, sA)
  ignore(stack.source_map_memo.read_or_abort())
  // Edit B (def 1 init 3 -> 4): now read the registry. proj_revision advances to
  // 3, but registry.last_revision is still 1, so skipped = (3 != 1 + 1) = true
  // and the registry takes the full-rebuild fallback → a FRESH object.
  let sB = "let a = 1\nlet b = 4\nb"
  stack.apply(sA, sB)
  let regB = stack.registry_memo.read_or_abort()
  // Skew detected ⇒ registry was force-rebuilt, NOT patched ⇒ identity broken.
  // (This also confirms the GC-anchor Watch is pull-based: an eager Watch would
  // have kept the registry current after edit A, making this a patch instead.)
  inspect(physical_equal(reg0, regB), content="false")
  // Correctness is preserved despite the fallback: resolution still agrees with a
  // fresh full rebuild of the current source.
  assert_level_b_agrees(stack, sB, "after-skew-rebuild")
  stack.dispose()
}

// ---------------------------------------------------------------------------
// Patch-chain — every step is a same-length def-init edit, so the patch branch
// fires on BOTH memos at EVERY step (identity held from step 0). Per
// feedback_differential_test_non_vacuity_every_path, the patch driver is asserted
// on every path, not just one fixture.
// ---------------------------------------------------------------------------

///|
test "level-B: def-init patch chain keeps registry+source_map identity every step" {
  let s0 = "let a = 1\nlet b = 2\na"
  let stack = LevelBStack(s0)
  let reg0 = stack.registry_memo.read_or_abort()
  let sm0 = stack.source_map_memo.read_or_abort()
  assert_level_b_agrees(stack, s0, "s0")
  // Each edit is a single same-length code-unit replacement of one def's init,
  // preserving def count (2) and the final_expr (`a`); the last reaches into
  // resolution (b's init becomes Var `a` → def 0). Every step ⇒ changed=[i] ⇒
  // in-place patch on both memos.
  let steps = [
    "let a = 1\nlet b = 3\na", "let a = 4\nlet b = 3\na", "let a = 4\nlet b = a\na",
  ]
  let mut prev = s0
  for s in steps {
    stack.apply(prev, s)
    let reg = stack.registry_memo.read_or_abort()
    let sm = stack.source_map_memo.read_or_abort()
    inspect(physical_equal(reg0, reg), content="true")
    inspect(physical_equal(sm0, sm), content="true")
    assert_level_b_agrees(stack, s, "patch:\{s}")
    prev = s
  }
  stack.dispose()
}

// ---------------------------------------------------------------------------
// Structural sequences — def insert/delete (a def-count change drives the
// full-rebuild `_ =>` arm) plus earlier-def growth and a binder rename (def count
// unchanged, so the in-place patch arm fires even though offsets shift). The
// per-step drive-log snapshot in each test records the arm actually taken (R vs
// P), so the patch/rebuild mix is pinned by observation, not assumed — a
// regression that flips an arm changes the snapshot.
// ---------------------------------------------------------------------------

///|
test "level-B: insert and delete defs agree through the memo stack" {
  // Drive-log snapshot pins which memo arm fired each step (P=patch, R=rebuild);
  // def-count changes force the structural full-rebuild arm this sequence targets.
  inspect(
    lb_run_sequence([
      "let x = 0\nx", "let x = 0\nlet y = 1\nx", "let x = 0\nlet y = 1\nlet z = 2\n(x z)",
      "let x = 0\nlet z = 2\n(x z)", "let z = 2\nz",
    ]),
    content=(
      #|regR/smR regR/smR regR/smR regR/smR 
    ),
  )
}

///|
test "level-B: growing an earlier def shifts later defs (memo stack agrees)" {
  inspect(
    lb_run_sequence([
      "let a = 0\nlet b = 1\n(a + b)", "let a = (0 + 0)\nlet b = 1\n(a + b)", "let a = ((0 + 0) + 0)\nlet b = 1\n(a + b)",
    ]),
    content=(
      #|regP/smP regP/smP 
    ),
  )
}

///|
test "level-B: rename a binder flips shadowing through the memo stack" {
  inspect(
    lb_run_sequence([
      "let x = 1\nlet x = 2\nx", "let x = 1\nlet w = 2\nx", "let x = 1\nlet x = 2\nx",
    ]),
    content=(
      #|regP/smP regP/smP 
    ),
  )
}
