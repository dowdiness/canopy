# S6 — App-Layer Modularization: `examples/ideal/main/` (Design)

**Date:** 2026-07-11
**Scope:** `examples/ideal/main/` — de-duplication, action-overlay package
extraction, feature-scoped file renames, pure-computation `internal/`
packages. The migration may update the minimal supporting package manifests
and boundary adapters (`js_ffi`, `lib/dom-boundary`, `lib/menu/menu`) required
to compile, target, and test the extracted package; no unrelated behavior is
in scope.
**Status:** Design approved for migration; supporting boundary scope amendment
requires review.
**Builds on:**
[2026-06-18 ideal overlay architecture design](2026-06-18-ideal-overlay-architecture-design.md)
(approved; its ownership and behavior decisions remain authoritative, while
this design supersedes its legacy child-Cell representation — read that doc
first, this one does not repeat its behavioral rationale).
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

## Phase 2 — Action overlay: effect-free component package

The overlay remains a separately named feature boundary, but it is no longer
an independent Rabbita `Cell` or nested runtime. The current Rabbita pin has
removed `Cell::view`, so retaining the old child-cell representation is not a
valid migration target. The overlay is instead divided into a deterministic
state/effect core, a framework-facing view adapter, and the parent shell:

1. The root app is created with `@rabbita.create_state_with_init`. Its init
   callback returns the initial `Model` and the existing CodeMirror mount
   command. The root view is `model.map(model => view(emit, model))`.
2. `Model` owns an optional overlay state slice and the parent-owned action
   context/token. It does not store `Cell`, `Val`, `Emit`, or `Cmd` values.
   `Model` remains the existing application-shell state boundary: its mutable
   editor, FFI handles, and incremental observer are not reclassified as
   functional-core values by this migration.
3. The extracted `action_overlay/` package has two layers:
   - **Deterministic core:** `OverlayState`, overlay modes/messages/effects,
     state constructors, placement calculations, and the transition
     `(OverlayMsg, OverlayState) -> (OverlayEffect, OverlayState)`. The core
     performs no editor, DOM, command, or effect-executor side effects. It
     currently reuses `@menu.Model`/`@menu.Msg`, so the package retains a
     transitive Rabbita/cmd/html dependency. S6 guarantees effect-free,
     deterministic transitions and native-testable behavior, not a
     framework-independent dependency graph. Splitting `@menu` into a pure
     state/message layer is a separate follow-up design.
   - **Framework-facing view adapter:** `view_overlay` and its rendering/event
     helpers. It may use `@rabbita`, `@html`, `Emit[OverlayMsg]`, and
     `@menu` rendering APIs to translate core state into HTML and user events
     into overlay messages. It does not execute `OverlayEffect`.
4. The root `update` maps browser events to top-level messages, invokes the
   deterministic overlay transition when the overlay is active, and
   interprets the returned effect. Editor/CRDT commits remain in `main`,
   where the full `Model` and action context are available. Commands are
   returned from `update`; none are stored in the model.
5. The parent stamps the current overlay token when it creates an
   `ActionOverlayEffect` wrapper. `handle_overlay_output` rejects stale
   output when the wrapper token does not match the active context.

### File cut

| Child package (`action_overlay/`) | Stays in `main` (parent) |
|---|---|
| **Deterministic core:** `action_overlay_flow.mbt` (`OverlayOutput`, `OverlayState`, `OverlayMode`, `OverlayMsg`, `OverlayEffect`), `action_overlay_state.mbt` (state constructors and transition), and `action_overlay_error.mbt` | `action_overlay_exec.mbt` (`execute_action` — needs editor/companion/full context) |
| **Framework-facing view adapter:** `view_overlay` (currently in `view_actions.mbt`) | `action_overlay_update.mbt` (top-level message routing and effect interpretation) |
|  | `action_overlay_runtime.mbt` (deleted after host data is folded into `Model`) and `action_overlay_flow_wiring.mbt` (deleted; no child Cell/Emit adapter remains) |

### Boundary requirements

1. The child package must not import the parent package or its `Msg` type.
   Parent wrapping of overlay effects happens at the top-level dispatch site.
2. Prefer narrow constructors and accessors over blanket `pub(all)` for
   `OverlayState`, `OverlayMsg`, and `OverlayError`. The package exposes only
   values needed by the parent dispatcher and blackbox tests.
3. `OverlayOutput` carries no token. The parent defines the stamped wrapper
   `ActionOverlayEffect(token : Int, output : OverlayOutput)` in `main` (the
   `Msg::ActionOverlayEffect` variant carries both values). The parent captures
   the active token when it schedules the effect command, and stamps it exactly
   once at that boundary. `handle_overlay_output` validates the wrapper token;
   no child package type or constructor knows about the token.
4. Deterministic core transition tests move with the package and must not
   invoke the Rabbita view/runtime or effect executor. View adapter tests cover
   rendered state and event wiring. Parent tests retain host lifecycle, token
   rejection, action execution, and command interpretation coverage.

This phase is deliberately an effect-free state/effect migration rather than a
second reactive runtime. It preserves the approved child-owned UI boundary
while avoiding imperative cross-component wiring that a nested `Val` would
require. The deterministic core still has the transitive `@menu` dependency
described above; it is not a framework-independent package.

## Phase 2 sequencing

1. Replace the root `cell_with_emit` call with
   `create_state_with_init`, preserving the initial CodeMirror command and
   subscriptions.
2. Add characterization tests for overlay transitions and parent token
   rejection before changing the host representation.
3. Invert the overlay boundary in the existing package: remove child
   `parent_emit`, token threading, and runtime-held Cell values; return
   effect values instead.
4. Move the deterministic core files and framework-facing view adapter into
   `action_overlay/`, add its manifest, and expose only the required
   constructors/accessors.
5. Delete the obsolete runtime/wiring files and update parent call sites.
6. Run `moon check` and `moon test` after the root migration, in-package
   boundary proof, and package split; inspect generated `.mbti` changes after
   the split.

This replaces the earlier in-place child-cell sequencing. The old
`create_overlay_cell`/`overlay_effect_to_cmd` boundary is not an intermediate
target because it depends on the removed `Cell::view` API.
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

## Resolved implementation decisions

- Extract the overlay as `examples/ideal/main/action_overlay/`, a sibling
  package to `ui/`. It is a feature package, not an `internal/` computation
  package, because it owns the overlay view and state machine.
- Use narrow constructors/accessors for `OverlayMsg`, `OverlayError`, and
  `OverlayState`. Do not widen the package with blanket `pub(all)` unless a
  compiler error demonstrates that a specific public constructor is required.
- Integrate overlay state into the root state graph. Do not create a nested
  `Val` with late-bound `Emit` references; the root model is the single
  reactive owner and `Val::map` supplies the overlay subtree.

## Open decisions for implementation time

- Exact naming of the parent-owned host fields after `ActionOverlayRuntime`
  removal. The implementation must retain context and token semantics while
  removing Cell/Emit/Cmd storage; choose names that match the existing `Model`
  vocabulary after reading all call sites.
- Whether the pure overlay error representation needs a public constructor or
  can remain parent-created through one narrow `set_error` function.
