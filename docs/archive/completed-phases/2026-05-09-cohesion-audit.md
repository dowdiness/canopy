# Cohesion Audit & Consolidation Plan — 2026-05-09

Phase 2 plan for the cohesion audit. Phase 1 diagnosis approved 16 file
consolidations. This document specifies each as one independent commit.

## Hard constraints (carry over from task brief)

- `.mbti` files do not grow; shrinking is fine.
- Every commit independently passes `moon check && moon test`.
- No new abstractions, renames, or signature changes — file boundaries only.
- One operation per commit.
- Stop and ask if any merge wants to grow into a redesign or change `.mbti`.

## Per-commit verification loop (applies to every operation)

After making the file edits and before committing each operation, run this
sequence in order. If any step fails, stop and resolve before the next
commit:

1. `moon check` — fix any compile errors.
2. `moon ide find-references` on each previously-`pub` symbol now living in
   the merged file. If no external callers, downgrade visibility (only when
   the visibility change does not require a `.mbti` change to a public
   surface — see constraint above).
3. `moon test` — run the package's tests.
4. `moon info` — regenerate `.mbti`.
5. `git diff -- '*.mbti'` — must be **empty**. If non-empty, the merge
   accidentally exposed or hid a public symbol; investigate the root cause.
   Do not suppress.
6. `moon fmt` — format.
7. `git diff --stat` — verify only the expected files changed.
8. Commit with the format from the bottom of this doc.

**Why this matters:** Earlier drafts of the plan only ran the `.mbti` check
explicitly for M4. The `.mbti` invariant is a hard constraint for every
commit, so it lives here at the top of the loop, not in any single
operation's spec.

## Execution order

Independent operations grouped by package. Within a package, operations are
ordered to avoid touching the same target file twice. A `moon check && moon
test` runs after each commit.

| # | Package          | Op  | Source(s)                                                                                       | Target                                  | LOC |
|---|------------------|-----|--------------------------------------------------------------------------------------------------|-----------------------------------------|-----|
| 1 | core             | M1  | `proj_node_json.mbt` (14)                                                                       | `proj_node.mbt`                         | 89→103 |
| 2 | core             | M2  | `source_map_json.mbt` (25)                                                                      | `source_map.mbt`                        | 322→347 |
| 3 | core             | M3  | `generic_tree_op.mbt` (36)                                                                      | `types.mbt`                             | 59→95 |
| 4 | echo             | M5  | `term_freq.mbt` (14)                                                                            | `sparse_vec.mbt`                        | 73→87 |
| 5 | lib/btree        | M9  | `traits.mbt` (2)                                                                                | `types.mbt`                             | 26→28 |
| 6 | lib/btree        | Q8  | `navigate.mbt` (6)                                                                              | `walker_descend.mbt`                    | 438→444 |
| 7 | lang/lambda/eval | Q4  | `optimize.mbt` (15)                                                                             | `eval_memo.mbt`                         | 306→321 |
| 8 | lang/lambda/edits| Q5  | `types.mbt` (27)                                                                                | `actions.mbt`                           | 326→347 |
| 9 | lang/json/proj   | Q3a | `json_memo.mbt` (19)                                                                            | `proj_node.mbt`                         | 214→233 |
| 10| lang/markdown/proj | Q3b | `markdown_memo.mbt` (18)                                                                      | `proj_node.mbt`                         | 122→140 |
| 11| lang/markdown/companion | M6 | `markdown_editor.mbt` (14) + `markdown_edit_bridge.mbt` (22)                              | `markdown_companion.mbt` (new name)     | 0→36 |
| 12| lang/json/companion | M7 | `json_editor.mbt` (16) + `json_edit_bridge.mbt` (24)                                          | `json_companion.mbt` (new name)         | 0→40 |
| 13| ffi/markdown     | M8  | `view.mbt` (23) + `lifecycle.mbt` (49) + `edit.mbt` (53)                                       | `markdown_ffi.mbt` (new name)           | 0→125 |
| 14| ffi/json         | Q6  | `diagnostics.mbt` (34) + `view.mbt` (39) + `lifecycle.mbt` (44)                                 | `json_ffi.mbt` (new name)               | 0→117 |
| 15| editor           | Q2  | `edit_bridge.mbt` (20)                                                                          | `sync_editor_parser.mbt`                | 134→154 |
| 16| editor           | M4  | `sync_editor_history.mbt` (42) + `sync_editor_pretty.mbt` (39) + `sync_editor_span_edit.mbt` (35) + `sync_editor_sync.mbt` (60) + `projection_memo.mbt` (58) | `sync_editor.mbt` | 286→520 |

Total: 21 production `.mbt` files removed. No package directories deleted.

---

## Per-operation specifications

For each merge: target file, source order, visibility downgrades possible,
imports that become redundant, name collision risks.

---

### 1. M1 — `core/proj_node_json.mbt` → `proj_node.mbt`

**Target:** `core/proj_node.mbt` (89→103L)

**Source order in merged file:**
1. (existing) imports / `using` declarations
2. (existing) `pub struct ProjNode[T]`, `pub impl[T : Debug] Show for ProjNode[T]`
3. (existing) `pub fn[T] ProjNode`, `ProjNode::id`
4. (existing) `pub fn next_proj_node_id`, `collect_registry`, `get_node_in_tree`, `assign_fresh_ids`
5. **(new)** `pub impl[T : ToJson] ToJson for ProjNode[T]` — moved from `proj_node_json.mbt`

**Visibility downgrades:** None. The ToJson impl is already package-public.

**Imports that become redundant:** None — `proj_node.mbt` already imports the
same types.

**Collision risks:** None. The two files have no overlapping symbols.

**.mbti impact:** Stable. `pub impl[T : ToJson] ToJson for ProjNode[T]` is
already in `core/pkg.generated.mbti`.

---

### 2. M2 — `core/source_map_json.mbt` → `source_map.mbt`

**Target:** `core/source_map.mbt` (322→347L)

**Source order:**
1. (existing) imports
2. (existing) `pub struct SourceMap`, all `SourceMap::*` methods
3. **(new)** `pub impl ToJson for SourceMap` — moved from `source_map_json.mbt`

**Visibility downgrades:** None.

**Imports that become redundant:** None.

**Collision risks:** None.

**.mbti impact:** Stable.

---

### 3. M3 — `core/generic_tree_op.mbt` → `types.mbt`

**Target:** `core/types.mbt` (59→95L)

**Source order:**
1. (existing) imports
2. (existing) `pub struct NodeId`, `NodeId::from_int`, Show/ToJson impls
3. (existing) `pub(all) struct SpanEdit` + Show
4. (existing) `pub(all) enum FocusHint` + Show
5. (existing) `pub(all) enum DropPosition`
6. **(new)** `pub(all) enum GenericTreeOp` + Show — moved from `generic_tree_op.mbt`

**Visibility downgrades:** None — all are publicly visible types per .mbti.

**Imports that become redundant:** None — both files use the same `@debug` import.

**Collision risks:** None.

**.mbti impact:** Stable. All five types remain public.

**Comment adjustment:** Top-of-file comment in `types.mbt` ("Active runtime
types for projection editing") covers the merged content. Remove the
"language-agnostic" comment from `generic_tree_op.mbt` since it's now
expressed by being co-located with the other tree-edit primitives.

---

### 4. M5 — `echo/term_freq.mbt` → `sparse_vec.mbt`

**Target:** `echo/sparse_vec.mbt` (73→87L)

**Source order:**
1. **(new)** `priv struct TermFreq` + `term_freq` fn — moved from `term_freq.mbt`
2. (existing) `priv struct SparseVec`, `SparseVec::zero`
3. (existing) `to_sparse_vec` (uses TermFreq from above)
4. (existing) `cosine_similarity`, `top_n_by_score`

**Visibility downgrades possible after merge:**
- `term_freq` fn becomes file-private (already `fn`, no `pub`). No change
  needed; package-internal already.
- Status quo: `corpus.mbt` and `echo_wbtest.mbt` reference both — visibility
  is already package-internal. No downgrade necessary.

**Imports that become redundant:** None.

**Collision risks:** None — different struct names.

**.mbti impact:** Stable (both are `priv`).

---

### 5. M9 — `lib/btree/traits.mbt` → `types.mbt`

**Target:** `lib/btree/types.mbt` (26→28L)

**Source order:**
1. (existing) `const DEFAULT_MIN_DEGREE`
2. (existing) `pub(all) enum BTreeNode[T]`
3. (existing) `pub(all) struct BTree[T]`
4. **(new)** `pub(open) trait BTreeElem` — moved from `traits.mbt`
5. (existing) `pub(all) struct FindResult[T]` + Show

**Visibility downgrades:** None.

**Imports that become redundant:** None — both are zero-import files.

**Collision risks:** None.

**.mbti impact:** Stable.

---

### 6. Q8 — `lib/btree/navigate.mbt` → `walker_descend.mbt`

**Target:** `lib/btree/walker_descend.mbt` (438→444L)

**Source order:**
1. (existing) all `descend(...)` and walker descend logic
2. **(new)** `fn[T] BTreeNode::navigate` — moved from `navigate.mbt`

**Visibility downgrades:** Currently private (`fn[T] BTreeNode::navigate` —
no `pub`). Stays private after move. Verify with `moon ide find-references`
— already private, no external callers possible.

**Imports that become redundant:** None — both files use the same in-package
helpers (`descend`, `prepare_noop`, `find_slot`).

**Collision risks:** None.

**.mbti impact:** Stable (private fn).

---

### 7. Q4 — `lang/lambda/eval/optimize.mbt` → `eval_memo.mbt`

**Target:** `lang/lambda/eval/eval_memo.mbt` (306→321L)

**Source order:**
1. (existing) imports
2. (existing) `EvalResult` + memo cells
3. (existing) `eval_term`, `build_eval_memo`, `inject_eval_annotations`
4. **(new)** `pub fn optimize_term` — moved from `optimize.mbt`

**Visibility downgrades possible after merge:**
- `moon ide find-references optimize_term` returned only the definition site
  — function appears unused outside its own definition. **NOTE:** keep as
  `pub` per the consolidation-not-redesign rule. Flag this as a follow-up
  cleanup question for the user after Phase 3.

**Imports that become redundant:** Verify `@lambda_opt` is already imported
by `eval_memo.mbt` after merge. If not, add.

**Collision risks:** None.

**.mbti impact:** Stable.

---

### 8. Q5 — `lang/lambda/edits/types.mbt` → `actions.mbt`

**Target:** `lang/lambda/edits/actions.mbt` (326→~353L)

**Source content of `types.mbt` (27L):** Five `using` declarations plus one
`pub using @core { type DropPosition, type FocusHint }` re-export.

**CRITICAL — `using` is package-scoped in MoonBit, not file-scoped.**
The five `using` declarations in `types.mbt` are the ONLY `using` decls
across the entire `lang/lambda/edits` package, and `actions.mbt` /
`text_edit.mbt` / `tree_lens.mbt` / `scope.mbt` all use unqualified `NodeId`,
`ProjNode`, `SourceMap`, `FlatProj`, `Renderable` — they rely on the
package-wide bindings exposed by `types.mbt`. Dropping them would break
`moon check` immediately.

**Source order in merged `actions.mbt`:**
1. (existing) `actions.mbt` imports
2. **(new — all six `using` decls preserved verbatim, moved together):**
   - `using @core { type NodeId }`
   - `using @core { type ProjNode }`
   - `using @core { type SourceMap }`
   - `using @lambda_proj { type FlatProj, rebuild_kind, to_proj_node, parse_to_proj_node, populate_token_spans }`
   - `using @loomcore { trait Renderable }`
   - `pub using @core { type DropPosition, type FocusHint }`
3. (existing) `pub(all) enum ActionGroup`, `pub(all) struct Action`, etc.

**Visibility downgrades:** None possible — `pub using` is the public re-export
and the rest are already package-private bindings.

**Imports that become redundant:** None.

**Collision risks:** Verify `actions.mbt` doesn't already define
`DropPosition` or `FocusHint` locally (Quick check: it imports `@core`
already; the re-export should sit fine alongside.) Also verify no other
file in the package introduces a conflicting `using` declaration after
the move.

**.mbti impact:** Stable. The `pub using` re-export currently appears in
`lang/lambda/edits/pkg.generated.mbti:100,104`; moving its definition site
within the same package does not change the package interface. The
non-public `using` decls do not appear in `.mbti`.

**Verification step specific to Q5:** After deletion, run `moon check` —
it must succeed. If it fails on unqualified `NodeId`/`ProjNode`/etc. uses
in any package file, the move missed at least one `using` decl. Fix in
the same commit.

---

### 9. Q3a — `lang/json/proj/json_memo.mbt` → `proj_node.mbt`

**Target:** `lang/json/proj/proj_node.mbt` (214→233L)

**Source order:**
1. (existing) imports — already include `@core`, `@incr`, `@loom`, `@json`
2. (existing) `syntax_to_proj_node` + helpers
3. **(new)** `pub fn build_json_projection_memos` — moved from `json_memo.mbt`

**Visibility downgrades:** None — function is publicly callable from
`@json_proj.build_json_projection_memos` per .mbti.

**Imports that become redundant:** Confirm `@core`, `@incr`, `@loom`, `@json`
are all in `proj_node.mbt`'s import set. If `proj_node.mbt` doesn't already
use `@incr.Memo`, add import.

**Collision risks:** None.

**.mbti impact:** Stable.

---

### 10. Q3b — `lang/markdown/proj/markdown_memo.mbt` → `proj_node.mbt`

**Target:** `lang/markdown/proj/proj_node.mbt` (122→140L)

Same pattern as Q3a: move single `build_markdown_projection_memos` fn into
the sibling `proj_node.mbt`. Verify import set covers `@core`, `@incr`,
`@loom`, `@markdown`.

**Visibility downgrades:** None.

**.mbti impact:** Stable.

---

### 11. M6 — `lang/markdown/companion` adapters → `markdown_companion.mbt`

**Target:** new `lang/markdown/companion/markdown_companion.mbt` (~36L).

Two source files merge; total of two functions in one file.

**Source order:**
1. Imports (union of both files): `@editor`, `@md_edits`, `@md_proj`,
   `@markdown`, `@loom`
2. `pub fn new_markdown_editor(...)` — from `markdown_editor.mbt`
3. `pub fn apply_markdown_edit(...)` — from `markdown_edit_bridge.mbt`

**Visibility downgrades:** None — both fns are public, called by `ffi/markdown`.

**Imports that become redundant:** Both source files use overlapping import
sets; merge into one.

**Collision risks:** None.

**.mbti impact:** Stable.

**Why a new filename:** Both source filenames carry equal weight; neither is
a natural "primary." `markdown_companion.mbt` matches the package name and
is consistent with M7.

**`integration_wbtest.mbt` (144L):** Untouched.

---

### 12. M7 — `lang/json/companion` adapters → `json_companion.mbt`

**Target:** new `lang/json/companion/json_companion.mbt` (~40L).

Same pattern as M6.

**Source order:**
1. Imports (union): `@editor`, `@json_edits`, `@json_proj`, `@json`, `@loom`,
   `@bench` (only if needed by these fns; `@bench` is for benchmarks).
2. `pub fn new_json_editor(...)` — from `json_editor.mbt`
3. `pub fn apply_json_edit(...)` — from `json_edit_bridge.mbt`

**`json_benchmark.mbt` (135L) and `integration_wbtest.mbt` (393L):** Untouched.

**Imports redundant:** `@bench` is only needed by `json_benchmark.mbt`; verify
its `import` directive is removed from the new merged file if unused.

**.mbti impact:** Stable.

---

### 13. M8 — `ffi/markdown` whole-package → `markdown_ffi.mbt`

**Target:** new `ffi/markdown/markdown_ffi.mbt` (~125L). Entire production
surface of the package collapses to one file.

**Source order:**
1. Imports (union of all three files)
2. State maps / handle registries
3. `view.mbt` content — view tree / patches FFI
4. `lifecycle.mbt` content — create/destroy/text-io FFI
5. `edit.mbt` content — apply edits FFI

(Final ordering should follow the lifecycle of a typical caller: lifecycle
→ edit → view. Adjustable during execution.)

**Visibility downgrades possible:**
- Any state-map `let` definitions that were `pub`-leaked to enable cross-file
  sharing within the package can become file-local. Read the actual sources
  during execution to verify.

**Imports that become redundant:** Multiple — three files have similar
import sets. Single merged import block.

**Collision risks:** Top-level `let` registries (e.g. handle maps) — verify
no two files define the same name.

**.mbti impact:** Stable. Public exports are pinned by the `link.exports`
list in `moon.pkg`, not by file boundaries.

---

### 14. Q6 — `ffi/json` 3-of-4 merge → `json_ffi.mbt`

**Target:** new `ffi/json/json_ffi.mbt` (~117L). `edit.mbt` (160L) stays.

**Source order:**
1. Imports (union of three small files)
2. State maps (`json_view_states`, `json_editors`, `json_next_handle`)
3. `lifecycle.mbt` content (create/destroy/get_text/set_text)
4. `diagnostics.mbt` content (errors / proj_node / source_map JSON)
5. `view.mbt` content (view tree / patches)

**Visibility downgrades possible:**
- `json_editors` and `json_view_states` are currently top-level package
  state shared across files — likely already package-private. No change.

**Imports that become redundant:** Yes — three files' near-identical import
blocks collapse to one.

**Collision risks:** None expected — verify state-map names are unique
across the three sources.

**.mbti impact:** Stable.

**`edit.mbt`:** Untouched. It will need to keep importing whatever state map
moves into the new merged file. **CHECK during execution:** does
`edit.mbt` reference state maps owned by `lifecycle.mbt` or `view.mbt`? If
yes, those are package-internal `let` bindings already and the move is
silent. If `edit.mbt` calls private helpers in those files, mark those as
`fn` (file-local) becoming exposed by absorption — verify visibility
maintains.

---

### 15. Q2 — `editor/edit_bridge.mbt` → `sync_editor_parser.mbt`

**Target:** `editor/sync_editor_parser.mbt` (134→154L)

**Source order:**
1. (existing) imports — already include `@loom_core`
2. (existing) parser-related `SyncEditor::*` methods
3. **(new)** `pub fn merge_to_edits` — moved from `edit_bridge.mbt`

**Visibility downgrades possible:** `merge_to_edits` is `pub` because tests
reference it. After merge, since `edit_bridge_test.mbt` still calls it from
the same package, visibility could in theory drop to file-local — but
tests in the same package still need the symbol exposed at package-level.
Recommend: **keep `pub`**.

**Imports that become redundant:** Verify `@loom_core.Edit` and any helpers
in `edit_bridge.mbt`'s `compute_text_edits` chain are accessible from the
merged file.

**Collision risks:** None expected.

**.mbti impact:** Stable.

**`edit_bridge_test.mbt`:** Untouched. Continues to reference `merge_to_edits`
from the same package.

---

### 16. M4 — `editor/sync_editor*` fragments → `sync_editor.mbt`

**Target:** `editor/sync_editor.mbt` (286→~520L). Five small fragment files
fold in.

**Sources (all are `Self::method` impls on `SyncEditor[T]`):**
- `sync_editor_history.mbt` (42L) — `causal_snapshot`, `identity`,
  `editor_identity_counter`, `next_editor_identity`
- `sync_editor_pretty.mbt` (39L) — `get_pretty_view`, `compute_pretty_patches`
- `sync_editor_span_edit.mbt` (35L) — `apply_span_edits`
- `sync_editor_sync.mbt` (60L) — `apply_sync`, `get_version`, `export_all`,
  `export_since`, `adjust_cursor` (private)
- `editor/projection_memo.mbt` (58L) — `get_proj_node`, `get_source_map`,
  `get_registry`, `get_tree`, `get_node`, `node_at_position`, `get_node_range`

**Source order in merged `sync_editor.mbt`:**
1. (existing) imports — already cover all the dependencies
2. (existing) `const DEFAULT_WATCHDOG_MS`
3. (existing) `pub struct SyncEditor[T] { … }`
4. (existing) `SyncEditor::new_generic` and primary constructor logic
5. **(new — projection accessors group)** `get_proj_node`, `get_source_map`,
   `get_registry`, `get_tree`, `get_node`, `node_at_position`,
   `get_node_range` — from `projection_memo.mbt`
6. **(new — span edit)** `apply_span_edits` — from `span_edit.mbt`
7. **(new — sync/export group)** `apply_sync`, `get_version`, `export_all`,
   `export_since`, private `adjust_cursor` — from `sync.mbt`
8. **(new — pretty)** `get_pretty_view`, `compute_pretty_patches` — from
   `pretty.mbt`
9. **(new — history/identity)** `causal_snapshot`, `identity`, plus the
   module-level `editor_identity_counter` ref and `next_editor_identity`
   helper — from `history.mbt`
10. (existing) any remaining methods in `sync_editor.mbt`

**Visibility downgrades possible after merge:**
- `editor_identity_counter` (file-local `let` in `history.mbt`) is already
  file-private; stays so.
- `next_editor_identity` (helper fn) is already file-private; stays so.
- `adjust_cursor` (helper fn from `sync.mbt`) is already file-private; stays so.

No package-level `pub` symbols can downgrade — all the `Self::method`s are
called by external packages (lambda/json/markdown companions, ffi/lambda,
test files).

**Imports that become redundant:** Verify the merged file's import block
covers `@history.CausalSnapshot`, `@text.SyncMessage`, `@text.Version`,
`@pretty.Pretty`, `@protocol.ViewNode`, `@protocol.layout_to_view_tree`,
`@protocol.ViewPatch`, `@core.NodeId`, `@core.ProjNode`, `@core.SourceMap`,
`@core.SpanEdit`, `@core.FocusHint`, `@loom_core.Range`. Most are already
imported. Add any missing.

**Collision risks:**
- `editor_identity_counter` `let` binding — verify name is unique across
  source files.
- Top-of-file ///  doc comments — five files have headers; merge with one
  cohesive section comment per group.

**.mbti impact:** Stable. All public method signatures preserved.

**Reading sequence during execution:** Read all six files completely
(target + 5 sources) before composing the merged file. Then follow the
top-of-document verification loop. The list of formerly-public symbols
to spot-check via `moon ide find-references` after the merge:
`apply_span_edits`, `apply_sync`, `get_pretty_view`,
`compute_pretty_patches`, `causal_snapshot`, `identity`, `get_proj_node`,
`get_source_map`, `get_registry`, `get_tree`, `get_node`,
`node_at_position`, `get_node_range`, `get_version`, `export_all`,
`export_since`. Each must still resolve.

---

## Risks & stopping conditions

These would halt execution and require checking back:

1. **Q6 hidden coupling:** if `ffi/json/edit.mbt` reaches into private state
   maps owned by `lifecycle.mbt` or `view.mbt` via package-internal access,
   the merge is silent. If it reaches via name collision with the merged
   file's locals, fix the collision rather than working around it.
2. **M4 method collision:** if two source files define `Self::method` with
   the same name (e.g. two helper `adjust_cursor`s), stop and ask. Unlikely
   but verifiable upfront with a quick grep at execution time.
3. **`.mbti` growth:** any new public symbol after a merge means the file
   move accidentally re-exposed something. Investigate root cause, do not
   suppress.
4. **`optimize_term` is unused:** consider as follow-up after Phase 3
   completes. Not in scope for this cohesion pass.
5. **Test count regression:** if `moon test` reports fewer tests after a
   merge, stop. The merge accidentally moved a test out of its discovery
   path.

---

## Commit message format

Per the task brief:

```text
refactor(<package>): merge <old_files> into <new_file>

<one-sentence rationale>
```

Examples:
- `refactor(core): merge proj_node_json.mbt into proj_node.mbt` — body:
  "ToJson impl belongs with the type definition."
- `refactor(editor): merge five sync_editor_* fragments into sync_editor.mbt`
  — body: "Consolidate scattered Self::method impls; net -5 files."

---

## Out of scope

These are deliberately not in this plan; raise as separate refactors if
desired.

- Flattening any sub-package (lang/{json,markdown,lambda}/* architecture).
- Aggressive M4 (collapsing all 14 `sync_editor_*.mbt` into one file).
- Aggressive ffi/json (folding `edit.mbt` into the merged file).
- Any consolidation in `ffi/lambda` (kept feature-grouped per FFI exports).
- Visibility narrowing or unused-symbol deletion outside the merge target.
- Renames or signature changes during merging.
