# S6 — App-Layer Modularization: `examples/ideal/main/` (Design)

**Date:** 2026-07-11
**Scope:** `examples/ideal/main/` — de-duplication, action-overlay package
extraction, feature-scoped file renames, pure-computation `internal/`
packages.
**Status:** Proposed (pending user review)
**Builds on:**
[2026-06-18 ideal overlay architecture design](2026-06-18-ideal-overlay-architecture-design.md)
(approved; established the child-cell pattern this design extends into a
real package boundary — read that doc first, this one does not repeat it).
**Related:**
[architecture redesign proposal](../../plans/2026-06-11-architecture-redesign-proposal.md)
(S6 definition, line 239) ·
[structure-mode completion state](../../decisions/2026-07-11-structure-mode-completion-state.md)
(prerequisite, resolved)

---

## Problem

The redesign proposal's S6 justification ("ideal's 44-variant `Msg` /
360-line `update`") is stale. Re-measured: `Msg` is 34 variants
(`msg.mbt`), and `update_handlers.mbt` already has 7 named handler
functions (`handle_workspace`, `handle_structural`, `handle_outline`,
`handle_overlay`, `handle_file_io`, `handle_structure_mode`,
`handle_codemirror`), each matching its own `Msg` subset — there is no
single monolithic `update` to split.

The real, confirmed problem is navigability: `examples/ideal/main/` is 31
flat files in one package; file names don't reliably indicate which of
several bundled concerns live inside (`update_handlers.mbt` hides 7
handlers behind one generic name; `main.mbt` hides five unrelated
concerns — init, commands, intent-logging, root view — behind the most
generic name in the directory).

**MoonBit constraint that shapes every option below:** a subdirectory is
always a new package (confirmed: `main/ui/` has its own `moon.pkg`,
imported explicitly as `dowdiness/ideal-editor/main/ui`). There is no
"folder without a package" grouping mechanism. So "real directory
grouping" and "compiler-enforced package boundary" are the same choice,
not two options.

## Design test: what can become a real package/cell

A Rabbita `@rabbita.cell_with_emit` child (the pattern the 2026-06-18 doc
established for `action_overlay`) is only a valid extraction target when
**all three** hold:

1. **Exclusive data ownership** — state read/written only by one feature.
2. **Owns its own `view()`** — a cell renders an independent subtree; it
   cannot decorate rows owned by a parent-rendered list.
3. **Owns its transaction boundary** — the feature's mutations don't need
   to interleave with another feature's commit inside the same message.

Editor/`selected_node`/`highlight_set`/`nav_path`/`scope_map`/`workspace`/
`bottom_tab`/`sync_status` all fail (1) — read across 3+ features each.
Forcing them into packages would mean exposing `Model` fields `pub`
cross-package, which isolates nothing. They stay flat, renamed for
discoverability (Phase 3).

Two candidates were evaluated against the full three-axis test:

| Candidate | (1) Exclusive data | (2) Owns view | (3) Owns transaction | Verdict |
|---|---|---|---|---|
| Action overlay | Yes (`ActionOverlayHost`/`OverlayState`, already isolated) | Yes (floating panel, own `view_overlay`) | Yes (menu navigation is local; only the final commit reaches into `editor`) | **Already a cell — extract to a real package** |
| Outline drag-and-drop | Marginal — `drag_source` is *also* mirrored to a JS global (`window.__canopy_outline_drag_source`, `view_outline.mbt:69-83`), not exclusively `Model`-owned | **No** — decorates rows inside `view_outline.mbt`, no subtree of its own | No — `OutlineDrop` commits directly into the parent's CRDT transaction | **Not a cell.** Downgrade to grouping the three fields into a plain `DragState` struct. No package. |

---

## Phase 0 — De-duplication (behavior-preserving, do first)

Independent of any package work; shrinks what Phase 2 has to carry across
a boundary. Every helper below is a same-package extraction, no new
invariants.

**`commit_tree_edit(model, tree_op) -> (Cmd, Model)?`** — consolidates
the "apply a tree edit to the CRDT" ceremony (`apply_lambda_tree_edit` →
`push_intent` → `push_patch` → `refresh` w/ `next_timestamp` bump →
`sync_after_local_model_change`). **Four call sites, not two:**
`handle_structural`'s `OutlineStructuralEdit`, `handle_outline`'s
`OutlineDrop`, `apply_structural_edit_request` (`main.mbt:397-432`), and
`execute_action` (`action_overlay_exec.mbt`). `execute_action` diverges on
`Err`: it closes the overlay and routes the error into the child cell as
`SetError`, where the other three silently no-op. The helper must return
the `Result` (or take an `on_err` continuation) rather than swallowing it
— callers that want silent no-op pass a no-op continuation explicitly.

**`apply_text_edit(model, text) -> (String, Model)`** — the shared prefix
(`set_text_and_record` → `refresh` w/ timestamp bump → `get_text`) of
`LoadExample` and `FileLoaded`. These two are verbatim-identical today
(confirmed) — build `load_text(model, text) -> (Cmd, Model)` on top and
use it for both. **`CmDocChanged` does NOT fold into this** — its sync
tail has a real behavioral difference (echo-guard: only calls
`@cm.set_doc` if `actual_text != text`, to avoid a feedback loop with
CodeMirror's own local edit). **`Undo`/`Redo` do NOT fold in either** —
they skip the `next_timestamp` bump that every other site performs;
that's a deliberate difference (undo/redo isn't a new edit), not an
oversight, but it means they can't share `apply_text_edit`'s prefix as-is.

**`highlight_set_for(node_id, scope_map) -> HashSet[NodeId]`** — the
`parse_node_id` → `compute_highlight_set`-or-empty idiom, duplicated five
times: once inside `refresh()` itself (`main.mbt:246-256`), and once each
in `OutlineNodeClicked`, `OutlineNavigate`, `OutlineStructuralEdit`'s
tail, `StructureNodeSelected`. **Must take an explicit `reset_nav : Bool`
parameter for the selection-bundle update**, not merge silently — three
of four sites reset `nav_path : None`, but `OutlineNavigate` deliberately
does not, because `nav_path` is "cached navigation path between
consecutive arrow key presses, cleared on any non-navigation event"
(`model.mbt`'s own field comment). Losing this distinction in the merge
would break consecutive arrow-key navigation.

**Bug fix bundled into this phase (called out explicitly, not smuggled
per Move-Only Refactor Discipline):** `OutlineNavigate`'s unparseable-id
branch does `return None` (`update_handlers.mbt:209`), which falls
through every handler in the chain and hits `abort("unhandled message")`
in `main.mbt`. Every sibling selection site instead treats a parse
failure as empty-set/no-op. This is a live crash path, not a duplication
artifact. **Fix: change to `Some((none, model))`,** matching every
sibling. Land this as a one-line, explicitly-labeled fix inside the Phase
0 PR, not folded silently into the `highlight_set_for` extraction.

**Pre-work:** write characterization tests pinning current output for
each of the five call sites before extracting, so the refactor is
verified behavior-preserving except for the one named bug fix above.

## Phase 1 — Outline drag-and-drop: struct grouping only

`drag_source : @canopy_core.NodeId?`, `drop_target_id`, `drop_position`
become one `DragState` struct field on `Model` instead of three loose
fields. No cell, no package — this candidate failed the three-axis test
in the Design Test section. This phase is optional / can be folded into
Phase 3's renames if it's not worth a dedicated PR.

## Phase 2 — Action overlay: package extraction

Builds directly on the approved 2026-06-18 design. That doc already
separated child-owned UI state (`OverlayState`) from parent-owned
application context (`ActionOverlayHost`); this phase turns that already-
proven boundary into a real MoonBit package boundary.

**File cut** (narrower than initially proposed — verified against the
2026-06-18 doc's own file table, which shows `action_overlay_exec.mbt`
explicitly marked "no change... still receives context from its caller"):

| Child package (`action_overlay/`) | Stays in `main` (parent) |
|---|---|
| `action_overlay_flow.mbt` (`OverlayOutput`, `OverlayMsg`) — plus `OverlayState`/`OverlayMode`, which the plan-authoring pass found actually live in `model.mbt` today, not here as this table originally claimed; they move into this file | `action_overlay_exec.mbt` (`execute_action` — needs `editor`/`companion`/full context) |
| `action_overlay_flow_wiring.mbt` (`create_overlay_cell`, `overlay_effect_to_cmd`) | `action_overlay_update.mbt` (`handle_overlay_event`, `handle_overlay_output` — dispatch against `Model`) |
| `action_overlay_error.mbt` (`OverlayError`) | `action_overlay_runtime.mbt` (`ActionOverlayHost`, `ActionOverlayRuntime` — parent-owned host state) |
| `view_overlay` (currently misfiled in `view_actions.mbt` — must move into the package) | `action_overlay_state.mbt` (`open_action_overlay*` — context detection needs `Model`) |

**Required refactors (the boundary is bidirectional — child→parent was
found first, parent→child was missed initially):**

1. **Child → parent (blocking).** `create_overlay_cell`'s `parent_emit`
   param is typed `Emit[Msg]` — the parent's top-level message type — and
   `overlay_effect_to_cmd` directly constructs
   `Msg::ActionOverlayEffect(OverlayOutput::...)`. If `action_overlay`
   became its own package, this creates a circular package dependency
   (child needs parent's `Msg`; parent needs child's types). **Fix:**
   `parent_emit : Emit[OverlayOutput]`; the `OverlayOutput -> Msg`
   wrapping moves to the call site in `main`.
2. **Parent → child (missed in the first pass).** The parent also
   *constructs* child message values directly: `OverlayEvent::to_overlay_msg`
   (`action_overlay_update.mbt:2-7`) and `execute_action`'s
   `runtime.send(SetError(...))`/`ShowNamePrompt(...)`. For this to
   compile across a package boundary, `OverlayMsg`, `OverlayError`, and
   `OverlayState` need either `pub(all)` or explicit constructor
   functions exposed by the child package. Prefer narrow constructors
   over a blanket `pub(all)` unless the type is already a plain data
   record with no invariants to protect — this repo has been burned
   before by exposing mutable/invariant-bearing structs too broadly
   across a package boundary.
3. **Token mechanism: revised (deliberately, superseding the 2026-06-18
   doc's Non-Goal).** That doc ruled out "changing the token mechanism or
   `parent_emit` pattern" — a reasonable Non-Goal at the time, since
   nothing about that design required touching it. Package extraction
   changes that: keeping `token~` on `OverlayOutput`'s variants means the
   child package must receive a `token : Int` and thread it through
   purely for the parent's own stale-output bookkeeping, which is exactly
   the kind of parent-concern leakage the package boundary exists to
   prevent. **New shape:** strip `token~` from `OverlayOutput` entirely
   (`ExecuteAction(@lambda_edits.Action, choice~: String, name~: String)`,
   `CloseOverlay`) — the child never receives or knows about a token.
   `create_overlay_cell`'s caller (in `main`, at the `open_action_overlay*`
   call sites) builds the actual `Emit[OverlayOutput]` it hands to the
   child as an adapter closure that captures the current `token`, stamps
   it, and wraps into `Msg::ActionOverlayEffect` before calling the real
   parent `Emit[Msg]`. The stale-output guard invariant itself
   (`ActionOverlayHost.runtime.token` vs. the token on the received
   output) is unchanged — only *where* the token is attached moves, from
   child-constructed to parent-stamped. This is a stronger decoupling
   than the original in-place design, not just a stylistic swap: it
   directly serves this design's own goal (minimize what the child
   package needs to know about the parent), which is why it's adopted
   here despite revising an approved doc. The 2026-06-18 doc's Non-Goals
   list has been amended in place with a pointer to this section, so it
   isn't read as still-current in isolation.
4. **Test split.** `main_wbtest.mbt`'s overlay tests: host-side tests
   (token guard, `ActionOverlayHost` lifecycle) stay in `main`;
   `OverlayState`/state-machine tests move into the new package.

**Sequencing within this phase:** prove the emit-boundary inversion
*in-package* first (same files, same package, just the narrowed
signatures) — this validates the boundary compiles and behaves
identically before paying the ceremony cost of an actual `moon.pkg`
split. Only then move the files and add the package manifest.

## Phase 3 — Feature-scoped renames (mechanical, low-risk, any time after Phase 0)

Follows the existing `view_X.mbt` convention already established in this
directory.

- `update_handlers.mbt` → `update_workspace.mbt`, `update_structural.mbt`,
  `update_outline.mbt`, `update_file_io.mbt`, `update_structure_mode.mbt`,
  `update_codemirror.mbt`. (`update_overlay` — formerly `handle_overlay`
  — mostly dissolves into Phase 2's package boundary instead.)
- `view_bottom.mbt` → thin root (tab chrome + dispatch) +
  `view_bottom_graphviz.mbt`, `view_bottom_incr_graph.mbt`,
  `view_bottom_oplog.mbt`, `view_bottom_patch.mbt`,
  `view_bottom_problems.mbt`.
- `main.mbt` → `init.mbt` (`init_model`, `subscriptions`, `main`),
  `commands.mbt` (`cm_mount_cmd`, `sync_after_*`, `select_*_cmd`,
  `refresh`, `build_scope_map_from_editor`), `intent_log.mbt`
  (`push_intent*`, `push_patch`), `view_root.mbt` (`view_toolbar`,
  `view`, `view_peer_status`, `outline_panel_attrs`,
  `view_outline_resize_handle`), thin `update.mbt` (top-level dispatcher +
  `apply_structural_edit_request`).
- **`view_history.mbt` stays untouched.** Its name already matches its
  single content 1:1 — it isn't part of the discoverability problem.

## Phase 4 — `internal/` packages for pure computation

Only for logic that is genuinely `Model`-free (verified by signature, not
assumed):

- `internal/history_render/` ← `view_history.mbt`'s pipeline
  (`render_history(snap: CausalSnapshot, local_agent: String)`,
  `collect_history_data`, `chain_compress`, `emit_dot_string`,
  `node_attrs`, `palette_color`, `legend_html`, `escape_*`) — none of
  these take `Model`.
- `internal/graphviz_render/` ← `render_dot_to_svg(dot: String)`.

`render_graphviz_html(model)`/`render_incr_graph_html(model)`/
`render_history_html(model)` stay in `main` as thin adapters that extract
the narrow input (`model.editor.causal_snapshot()`, etc.) and call into
the `internal/` package.

---

## Sequencing

Phase 0 → Phase 2 (in-package boundary proof → package split) → Phase 1
and Phase 3/4 can land any time after Phase 0, independently, in any
order — they're mechanical and don't depend on Phase 2.

Given this now spans 4+ PRs, 6+ files, and one invariant-bearing seam
(the stale-output token guard, whose attachment point is being
relocated — see Phase 2 item 3), this is **Full band** per this repo's
own process calibration — the implementation plan itself should be
Codex-authored, with Codex validating both the emit-boundary inversion
and the token relocation specifically before implementation starts.

## Testing / verification

- Phase 0: characterization tests before refactor; `moon test` after each
  helper extraction; re-run `structure-mode-switch.spec.ts` and
  `structural-editing.spec.ts` (Playwright) since selection/highlight
  logic is touched.
- Phase 2: `moon check`/`moon test` after the in-package boundary proof
  and again after the package split; `git diff '*.mbti'` reviewed as an
  API change (new package = new public surface, however narrow).
- All phases: `moon check && moon test` for the workspace; no behavior
  change expected in Phases 1/3/4 (pure reorganization).

## Risks

- **Phase 0's `commit_tree_edit` `Err`-handling unification** could
  change observable behavior for the three sites that currently no-op
  silently, if not designed carefully (mitigated by requiring the helper
  to return/take a continuation rather than fixing behavior singly).
- **Phase 2's `pub(all)` exposure** of `OverlayMsg`/`OverlayError`/
  `OverlayState` widens the child package's public surface beyond what's
  strictly necessary if done as a blanket `pub(all)` rather than narrow
  constructors — worth a design pass at implementation time, not decided
  here.
- **`.mbti` churn** from the package split — run the existing API-diff
  check.

## Value framing

Renames (Phase 3) and de-duplication (Phase 0) directly address the
confirmed pain ("hard to edit / hard to find things" across the flat
31-file directory) and are low-risk. The action-overlay package split
(Phase 2) does **not** primarily serve that same pain — Phase 3 already
makes the overlay's files easy to find by name. Phase 2's honest
justification is hardening an already-proven, already-approved cell
boundary into a compiler-enforced one, continuing the 2026-06-18 design's
own trajectory. Drag-and-drop's downgrade to a plain struct (Phase 1)
reflects that it never actually qualified for package treatment once
checked against the three-axis test, not a scope cut.

## Non-goals

- Redesigning `Model` into per-feature owned slices (the underlying
  reason `handle_structural`/`handle_structure_mode`/`handle_codemirror`/
  `handle_workspace` can't become cells — out of scope, would need its
  own design if ever pursued).
- Forcing outline drag-and-drop into a cell (failed the three-axis test).
- Changing the *stale-output guard invariant itself* — the token still
  exists and is still checked exactly as before; only its attachment
  point moves (see Phase 2 item 3). The 2026-06-18 doc's broader
  `parent_emit` pattern is otherwise unchanged.
- Splitting `view_history.mbt` (already single-purpose).

## Open decisions for implementation time

- Exact package path for the extracted overlay: `examples/ideal/main/action_overlay/`
  as a sibling to `ui/`, vs. an `internal/` prefix. Both are visible only
  to `main` either way (no external consumers) — pick based on whether
  future reuse outside `examples/ideal` is ever plausible (unlikely,
  given the library-api-boundary ADR places all of `examples/*` in Tier
  3).
- Whether `pub(all)` or narrow constructors are used for
  `OverlayMsg`/`OverlayError`/`OverlayState` at the Phase 2 boundary.
