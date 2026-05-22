// Shared-runtime safety probe — P0a gate #1.
//
// Workspace-mode hypothesis (docs/research/2026-05-22-spec-aware-workspace.md
// Appendix B P0a #1 + Appendix C #1): two editors might share a single
// `@incr.Runtime` so cross-editor reactive dependencies (workspace dep-graph
// MemoMap reading both editors' projection memos, etc.) can join one graph.
//
// Today the public editor surface does NOT expose a shared-runtime ctor —
// `new_lambda_editor` / `new_markdown_editor` (lang/lambda/companion/lambda_editor.mbt:90,
// lang/markdown/companion/markdown_companion.mbt:7) hardcode a fresh runtime
// inside their `make_parser` closure. The shared-runtime path is reachable
// only via `@loom.new_parser(src, grammar, runtime=shared_rt)`
// (loom/loom/src/factories.mbt:230-236) or by calling
// `@editor.SyncEditor::new_generic` with a custom closure that forwards a
// shared runtime. That mismatch IS a probe finding — the §P0b slice
// would need to add a runtime-taking editor ctor.
//
// Codex pre-impl review 2026-05-23 (5 load-bearing findings, all reflected
// in the test design below):
//   (a) per-cell liveness via `Runtime::cell_info` returning None — NOT
//       aggregate cell count; disposed slots don't shrink storage arrays
//       (loom/incr/cells/runtime.mbt:300-314, introspection.mbt:86-119).
//   (b) Two-of-the-same-grammar for §B/§C — confounder-free; mixing Lambda
//       + Markdown adds type-plumbing surface that obscures the runtime
//       behavior question. (Probe uses two JSON parsers — same property,
//       avoids adding a Lambda grammar import to the probe pkg.)
//   (c) `parser.source()` as the cross-editor observable — minimal-noise
//       Memo[String] surface; `cached_proj_node` pulls in a much larger
//       projection-tree subgraph that mudgs the GC verdict (parser.mbt:133-136).
//   (d) `Runtime::gc()` is synchronous mark+sweep (loom/incr/cells/internal/kernel/gc.mbt:113-128)
//       but drains pending broadcast events afterward (runtime.mbt:564-568)
//       — call gc() TWICE to reach steady state.
//   (5) `gc_role = Root` cells (Effects) are implicit pins. Production
//       canopy creates ZERO push effects in the editor/parser/projection
//       stack (verified by grep 2026-05-23 — only @incr Scope helpers + a
//       tcfx scope in ffi/lambda/lifecycle.mbt:25 use them). Memos are
//       `gc_role = Interior` (memo_data.mbt:46-48) → not implicit roots.
//       Consequence: a shared runtime gc() with NO explicit roots collects
//       EVERY Memo, including the surviving editor's. The probe must
//       observe at least one surviving Memo via `Memo::observe` (observer.mbt:64-79)
//       to attribute the collect to "editor A specifically", not "gc wiped
//       everything Interior."
//
// Three sections:
//   §A — `set_on_change` is a single-occupancy slot (runtime.mbt:449-460);
//        second registrar silently clobbers the first.
//   §B — gc() collects unrooted Memos; surviving editor needs an Observer
//        to root its reactive surface in a shared runtime.
//   §C — A cross-editor Memo reading both parsers' source() — does it
//        survive after one editor is dropped + gc'd, given the cross-Memo
//        is rooted by Observer but its dep is gone?
//
// Decision exit: characterize what discipline editors need to follow to
// coexist on a shared runtime safely, OR conclude that per-editor runtimes
// + bridge signal is the principled near-term path (research report §3
// recommendation update).

///|
fn json_parser_on(
  rt : @incr.Runtime,
  source : String,
) -> @loom.Parser[@_json_lang.JsonValue] {
  @loom.new_parser(source, @_json_lang.json_grammar, runtime=rt)
}

///|
// ============================================================
// §A — Runtime::set_on_change single-slot contention
//
// Two parsers on a shared runtime; two callbacks registered in order
// (fA, then fB). One revision bump via parser_a.set_source. Observable:
// does fA still fire (multi-listener semantics) or has it been overwritten
// (single-slot semantics)?
//
// Trigger choice: `parser.set_source(new)` discards incremental state and
// publishes one snapshot inside `rt.batch` (parser.mbt:108) — one revision
// bump → on_change fires once. (apply_edit does the same; set_source is
// simpler because no Edit fields are needed.) Per Codex finding, the
// trigger must NOT be nested inside another rt.batch — calling
// set_source from test top-level is correct.
// ============================================================

///|
test "P0a gate #1 §A — set_on_change is single-slot; second registrar clobbers first" {
  let shared_rt = @incr.Runtime::new()
  let parser_a = json_parser_on(shared_rt, "[1]")
  let parser_b = json_parser_on(shared_rt, "[2]")
  ignore(parser_b)
  let count_a : Ref[Int] = { val: 0 }
  let count_b : Ref[Int] = { val: 0 }
  shared_rt.set_on_change(fn() { count_a.val = count_a.val + 1 })
  shared_rt.set_on_change(fn() { count_b.val = count_b.val + 1 })

  // One revision bump.
  parser_a.set_source("[11]")

  // Verdict: single-slot semantics observed.
  //   fA was overwritten before parser_a's bump → never fired.
  //   fB owns the slot → fired once for the commit.
  inspect(count_a.val, content="0")
  inspect(count_b.val, content="1")
  shared_rt.clear_on_change()
}

///|
/// Sanity control: a single registered callback fires exactly once per
/// revision bump. If §A's count_b were 0, this control would tell us
/// "the slot is wired correctly when uncontended" vs. "on_change is broken
/// against parser.set_source." Keeps §A's verdict attributable.
test "P0a gate #1 §A control — single registered callback fires once per bump" {
  let shared_rt = @incr.Runtime::new()
  let parser_a = json_parser_on(shared_rt, "[1]")
  let count : Ref[Int] = { val: 0 }
  shared_rt.set_on_change(fn() { count.val = count.val + 1 })
  parser_a.set_source("[11]")
  inspect(count.val, content="1")
  shared_rt.clear_on_change()
}

///|
// ============================================================
// §B — gc() collects unrooted Memos; observer-rooted Memos survive.
//
// Holding a MoonBit parser binding does NOT pin its Runtime-side cells —
// gc_roots are explicit (`add_gc_root`, exposed via `Memo::observe`)
// plus implicit (gc_role = Root cells, i.e. Effects). Production canopy
// creates zero Effects in the editor/parser stack, and Memos are
// `gc_role = Interior` (memo_data.mbt:46-48). So a shared-runtime
// `gc()` with NO explicit roots wipes every Memo, including the
// surviving editor's.
//
// To attribute the collect to "parser A specifically" we root parser
// B's source view through Observer (observer.mbt:64-79).
//
// Trick — calling rt.gc() requires `phase is Idle`. set_source ran
// inside rt.batch internally; the batch closes before set_source
// returns. So by the time we reach gc(), the runtime is idle. We still
// call gc() TWICE per Codex finding (d): the first call may queue
// broadcast events that the second call drains.
// ============================================================

///|
test "P0a gate #1 §B — gc collects unrooted Memos; observer-rooted Memos survive" {
  let shared_rt = @incr.Runtime::new()
  let parser_a = json_parser_on(shared_rt, "[1]")
  let parser_b = json_parser_on(shared_rt, "[2]")

  // Force initial reads so both source views have populated cell data.
  ignore(parser_a.source())
  ignore(parser_b.source())
  let id_a : @incr.CellId = parser_a.source().id()
  let id_b : @incr.CellId = parser_b.source().id()

  // Sanity: both source views exist before gc.
  inspect(shared_rt.cell_info(id_a) is Some(_), content="true")
  inspect(shared_rt.cell_info(id_b) is Some(_), content="true")

  // Root parser B's source view through an Observer; leave parser A
  // unobserved.
  let observer_b = parser_b.source().observe()

  // gc() twice (Codex finding (d) — second call drains any post-mark
  // broadcast queue).
  shared_rt.gc()
  shared_rt.gc()

  // Verdict: parser A's source was collected; parser B's survived.
  inspect(shared_rt.cell_info(id_a) is None, content="true")
  inspect(shared_rt.cell_info(id_b) is Some(_), content="true")
  observer_b.dispose()
}

///|
/// Negative control for §B: with NO observer registered, gc() collects
/// BOTH editors' source views. Distinguishes "gc wiped everything Interior"
/// (expected on a shared runtime with no explicit roots) from "gc only
/// removed parser A" (which would require an attributable explanation
/// the test does not provide).
test "P0a gate #1 §B control — gc with no observers collects ALL Memos" {
  let shared_rt = @incr.Runtime::new()
  let parser_a = json_parser_on(shared_rt, "[1]")
  let parser_b = json_parser_on(shared_rt, "[2]")
  let id_a : @incr.CellId = parser_a.source().id()
  let id_b : @incr.CellId = parser_b.source().id()
  inspect(shared_rt.cell_info(id_a) is Some(_), content="true")
  inspect(shared_rt.cell_info(id_b) is Some(_), content="true")
  shared_rt.gc()
  shared_rt.gc()
  inspect(shared_rt.cell_info(id_a) is None, content="true")
  inspect(shared_rt.cell_info(id_b) is None, content="true")
}

///|
// ============================================================
// §C — Cross-editor Memo: rooted transitively pins both inputs.
//
// A workspace dependency-graph MemoMap or workspace-scoped Memo that
// reads multiple editors' Memos joins them into one reachability cone:
// rooting the cross-Memo (via observer or further downstream reachable
// roots) keeps both editors' input Memos alive via gc_dependencies BFS
// (kernel/gc.mbt:63-87). This is the "self-rooting" property workspace
// surfaces would rely on.
//
// Codex recommended `parser.source().get().length()` over
// `cached_proj_node` for minimum noise (finding (c)). The cross Memo
// here reads both source().get().length()s.
// ============================================================

///|
test "P0a gate #1 §C — rooting a cross-editor Memo transitively pins both inputs" {
  let shared_rt = @incr.Runtime::new()
  let parser_a = json_parser_on(shared_rt, "[1]")
  let parser_b = json_parser_on(shared_rt, "[2]")
  let id_a : @incr.CellId = parser_a.source().id()
  let id_b : @incr.CellId = parser_b.source().id()
  let cross : @incr.Memo[Int] = @incr.Memo::new(shared_rt, fn() {
    parser_a.source().get().length() + parser_b.source().get().length()
  })
  // Force first computation via rt.read (outside-the-graph read) so
  // cross's dependency list is populated before observe/gc.
  let initial : Int = shared_rt.read(cross)
  inspect(initial, content="6")
  let id_cross : @incr.CellId = cross.id()
  let cross_observer = cross.observe()
  shared_rt.gc()
  shared_rt.gc()
  // cross is rooted → alive.
  inspect(shared_rt.cell_info(id_cross) is Some(_), content="true")
  // Inputs reachable through cross's gc_dependencies → alive.
  inspect(shared_rt.cell_info(id_a) is Some(_), content="true")
  inspect(shared_rt.cell_info(id_b) is Some(_), content="true")
  // Live cross can still be read after gc.
  parser_a.set_source("[11]")
  inspect(shared_rt.read(cross), content="7")
  cross_observer.dispose()
}

///|
/// Negative control for §C: cross-editor Memo NOT observed → gc collects
/// it AND, since cross was the only thing keeping the source views
/// reachable through gc_dependencies, both source views collected too.
test "P0a gate #1 §C control — unrooted cross-Memo + inputs all collected" {
  let shared_rt = @incr.Runtime::new()
  let parser_a = json_parser_on(shared_rt, "[1]")
  let parser_b = json_parser_on(shared_rt, "[2]")
  let id_a : @incr.CellId = parser_a.source().id()
  let id_b : @incr.CellId = parser_b.source().id()
  let cross : @incr.Memo[Int] = @incr.Memo::new(shared_rt, fn() {
    parser_a.source().get().length() + parser_b.source().get().length()
  })
  let _ = shared_rt.read(cross)
  let id_cross : @incr.CellId = cross.id()
  shared_rt.gc()
  shared_rt.gc()
  inspect(shared_rt.cell_info(id_cross) is None, content="true")
  inspect(shared_rt.cell_info(id_a) is None, content="true")
  inspect(shared_rt.cell_info(id_b) is None, content="true")
}
