# moji API derivation — what canopy needs from a MoonBit UAX #29 library

**Status:** historical derivation record (v5). The library and integration shipped in [#251](https://github.com/dowdiness/canopy/pull/251); the follow-up parser/undo non-BMP fixes also landed. The clean-cut spec at [`2026-05-10-moji-api-spec.md`](2026-05-10-moji-api-spec.md) and `docs/TODO.md` §16 carry current implementation status.

**Original audience:** moji author. Current audience: canopy maintainers
auditing why the shipped API has this shape.

**Revision history:**

- v1 (2026-05-10) — initial six-function surface.
- v2 (2026-05-10) — Codex review. Five critical fixes: strict-vs-snap
  semantics for cursor stepping (§1.3/§1.4/§1.6), insertion-vs-replace
  policy split (§1.1), explicit UTF-16 ↔ item-space layer (new §0),
  `compute_text_change` re-added for moji integration (§1.10), JS bridge
  recommended to reject non-boundary splices rather than silently snap
  (§1.9). Plus the unit-storage decision promoted to §6.
- v3 (2026-05-10) — Second Codex pass. Critical: strict-step formulas
  in §1.3/§1.4 only worked when the cursor was already on a grapheme
  boundary; interior cursors bisected surrogate pairs. Fixed by
  promoting the cursor-on-boundary invariant to a hard contract
  (new §0.5) and prescribing pre-snap repair when violated. Also:
  narrowed the §0 combining-mark coincidence claim, made `§1.10`
  Option A the unconditional recommendation (other repos call
  `compute_text_change` too), named the §1.9 checked/unchecked split
  as "exact splice" vs "snap splice," added a §2.1 fallback contract
  for moji authors who can't accept arbitrary UTF-16 offsets, fixed
  the §4.1 Hangul fixture, and split §4.4 by seam variant. §6.1
  notes Codex's Option A recommendation before the human decision.
- v4 (2026-05-10) — Self-review pass (Opus, deep-think). Critical:
  §0.5's invariant maintenance for `apply_text_edit_internal` was
  unconditionally false in cluster-fusing-insert scenarios (regional
  indicators, ZWJ, virama can shift downstream boundaries even when
  the splice itself was boundary-aligned in the *old* text). Fixed by
  making post-snap unconditional, not gated on a §1.1 promise that
  doesn't hold. Also: §0.5's undo/redo entry was misleading — undo
  can leave the cursor stale; defense-in-depth catches it but the
  invariant isn't preserved by undo itself. Plus: §2.4 driver mapping
  now lists §0.5 repair, §1.10 adds a submodule-coordination note,
  §1.2 unit-invariant phrasing simplified, §6.1 mentions bridge
  impact, §0.5 repair-direction trade-off flagged, §7 process notes
  refreshed.
- v5 (2026-05-10) — Third Codex pass. Critical: v4's unconditional
  post-snap only addressed the `move_cursor_to_edit_end = true`
  branch of `apply_text_edit_internal`; the false branch (used by
  `insert_at`, `delete_at`, `set_text_and_record`, span edits) still
  only bounds-clamped. Fixed by specifying post-snap for both branches.
  Also: undo wording corrected (undo *does* call `adjust_cursor()`
  which bounds-clamps; conclusion unchanged but the mechanism was
  wrong); §0.5 repair-direction default switched from A (snap-outside)
  to B (snap-toward-containing-cluster) to match §1.1's "partially
  touched cluster is fully consumed" policy and standard editor UX;
  "local segmentation" performance claim softened; §6.4 closed
  (Codex did the grep — `valtio` and `loom` both path-dep on canopy's
  `lib/text-change`, so single-fix coverage holds); TL;DR mentions
  the fallback contract; §4.4 adds a `move_cursor_to_edit_end=false`
  fusion fixture; legacy `editor/editor.mbt` declared out-of-scope.

**Inputs read first:**

- [docs/plans/2026-05-09-216-step4-bridge-audit.md](2026-05-09-216-step4-bridge-audit.md)
  — bulk-splice seam, Path E table, conversion-point recommendation.
- [docs/TODO.md §16](../TODO.md) — shipped moji items and remaining
  standalone follow-ups.
- `memory/project_unicode_failure_modes.md` — bimodal failure pattern.
- `memory/project_text_mutation_funnel.md` — funnel vs bypass routes.
- [docs/development/API_REFERENCE.md](../development/API_REFERENCE.md)
  — current UTF-16 position-unit contract.

## TL;DR

Canopy needs **four functions** from moji as the **preferred required
shape**, plus two ergonomics helpers it would like, plus one optional
reverse-iteration function. An **acceptable fallback shape** (boundary
arrays instead of point queries) is described in §2.1 if the
preferred shape is too invasive for moji's implementation:

| # | Function (preferred shape) | Required? |
|---|---|---|
| 1 | `prev_grapheme_boundary(text, pos) -> Int` *(at-or-before)* | required |
| 2 | `next_grapheme_boundary(text, pos) -> Int` *(at-or-after)* | required |
| 3 | `prev_word_boundary(text, pos) -> Int` *(at-or-before)* | required |
| 4 | `next_word_boundary(text, pos) -> Int` *(at-or-after)* | required |
| 5 | `is_grapheme_boundary(text, pos) -> Bool` | ergonomics |
| 6 | `grapheme_clusters(text) -> Iter[(Int, Int)]` | ergonomics |
| 7 | `grapheme_clusters_reverse(text) -> Iter[(Int, Int)]` | optional |

5 and 6 are mathematically derivable from 1 and 2. List them only if
moji can provide them cheaply. The §2.1 fallback shape replaces 1–4
with `grapheme_boundaries(text) -> Array[Int]` and
`word_boundaries(text) -> Array[Int]`; canopy then binary-searches.

All `pos` arguments are UTF-16 code-unit offsets, matching MoonBit's
`String[Int]` indexing and CM6's wire convention. **Moji must accept
positions inside surrogate pairs and inside multi-codepoint clusters
without aborting** (or, alternatively, expose a boundary-array form
that canopy binary-searches — see §2.1 fallback contract).

**Strict cursor stepping** (§1.3, §1.4, §1.6) is a canopy-side wrapper
expressed as `next_grapheme_boundary(text, pos + 1)` and
`prev_grapheme_boundary(text, pos - 1)` with bounds checks. **The
formulas are correct only when `pos` is already on a grapheme
boundary** — this is the cursor-on-boundary invariant in §0.5. Moji
exposes only at-or-before / at-or-after primitives; canopy maintains
the invariant and provides defense-in-depth pre-snap repair.

The JS bridge (`bridge.ts::applySpliceChanges`) needs no moji binding
because post-#246 it enters the bulk-splice seam — but only if the
seam *rejects* non-boundary splices via the existing `_checked`
return value rather than silently snapping (see §1.9).

## 0. Layer responsibilities (new in v2)

**This section was missing from v1 and is load-bearing.** Three
position units coexist in canopy's text path. Boundary-snapping alone
does not make positions safe to pass to the CRDT; canopy needs an
explicit conversion layer between moji and eg-walker.

| Layer | Unit | Source of truth |
|---|---|---|
| Editor public boundary | UTF-16 code-unit offset | CM6 `iterChanges`, JS `String.length`, MoonBit `String[Int]` |
| Grapheme layer (new, via moji) | UTF-16 offset that is a grapheme-cluster boundary | moji's UAX #29 segmenter |
| eg-walker text facade | Item-space offset (one item per codepoint, post-#240) | `@text.Pos`, `TextState::len()` |

For ASCII the three coincide. For non-ASCII they diverge:

- `"a😀b"` → UTF-16 length 4, item-space length 3, grapheme-cluster
  count 3. UTF-16 offset 3 (after the emoji) = item-space offset 2.
- `"e\u{0301}"` → UTF-16 length 2, item-space length 2, cluster count
  1. UTF-16 offset 2 = item-space offset 2 *for this specific input*
  because both codepoints are BMP and therefore each is one UTF-16
  unit. **This coincidence does not generalise.** Non-BMP combining
  marks exist (e.g. `"a\u{1D165}"` — base `a` + Musical Symbol Combining
  Stem) where UTF-16 length is 3, item-space length is 2, cluster
  count 1. Do not assume "combining mark inputs keep UTF-16 and
  item-space aligned" as a rule.

**The seam at `apply_text_edit_internal` therefore needs two
conversions, in order, on every call:**

1. **UTF-16 → grapheme-aligned UTF-16** via moji. Snap each endpoint
   per the policy in §1.1.
2. **UTF-16 → item-space** via codepoint counting. Walk the doc text
   from 0, counting one item per codepoint (treating a surrogate pair
   as one item), until the UTF-16 cursor is reached.

Step 2 is **canopy's responsibility, not moji's.** Moji has no
opinion about CRDT positions. Canopy already needs codepoint-counting
internally for any UTF-16 → eg-walker conversion; moji's contribution
is only step 1.

This conversion stack must also exist in the per-char paths (§1.2–
§1.4): they currently store `self.cursor` in UTF-16 code units and
pass that to `@text.Pos::at(self.cursor)`. After #240, `@text.Pos`
expects item-space; for non-ASCII inputs the existing call is wrong
even before grapheme work begins. Step 2 fixes this; moji has no
hand in it.

§6 lifts this into a top-level open question: which of UTF-16 /
grapheme-ordinal / item-space does `self.cursor` store going forward?
Each choice changes which conversions live where.

## 0.5 Cursor-on-boundary invariant (new in v3)

**Hard contract:** every time `SyncEditor::insert`, `delete`,
`backspace`, or any of the `_and_record` family runs, `self.cursor`
MUST be on a grapheme-cluster boundary of `self.doc.text()`.

This was implicit in v2 and the strict-step formulas in §1.3/§1.4
silently assumed it. Codex demonstrated the failure: with
`"a😀b"` (boundaries `0,1,3,4`) and `cursor = 2` (interior of the
emoji), v2's `next_grapheme_boundary(text, cursor + 1)` evaluates to
`next_grapheme_boundary(text, 3) = 3`, so forward delete deletes
range `2..3` — bisecting the surrogate pair. Symmetric breakage for
backspace.

**Maintenance:** the invariant is preserved by these operations
(table corrected in v4 — see notes below):

| Operation | How the invariant is preserved |
|---|---|
| `move_cursor(pos)` | Pre-snap with `prev_grapheme_boundary` (or `next_`, per §1.5 direction choice) before assigning. |
| `insert(text)` | Pre-snap the cursor before splice; **unconditional** post-snap the resulting cursor with `next_grapheme_boundary` after splice (§1.2). The post-snap is unconditional because inserted text can fuse with surrounding clusters. |
| `delete` / `backspace` | Pre-condition: cursor is on a boundary (defense-in-depth pre-snap if violated). Strict-step formula in §1.3/§1.4 then works. |
| `apply_text_edit_internal` (`move_cursor_to_edit_end = true` branch) | **Unconditional** post-snap the new cursor (`safe_start + inserted.length()`) against `new_text` via `next_grapheme_boundary`. v3 gated this on a §1.1 promise that doesn't hold; v4 made it unconditional for this branch. |
| `apply_text_edit_internal` (`move_cursor_to_edit_end = false` branch) | Used by `insert_at`, `delete_at`, `set_text_and_record`, and tree-edit-derived span edits. Current code calls `adjust_cursor()` (bounds-clamp). v5 requires: clamp the existing cursor to `[0, new_text.length()]` first, then post-snap with `next_grapheme_boundary(new_text, cursor)`. The cursor wasn't necessarily anywhere near the splice, but cluster-fusing across the splice can still shift its boundary status. |
| `undo` / `redo` | **Does not preserve the invariant.** Replay reverts the doc and calls `adjust_cursor()` (`editor/sync_editor_undo.mbt:78` → `editor/sync_editor.mbt:384`), which bounds-clamps to `doc.len()` only. The cursor may be in-bounds but off-boundary relative to the reverted doc. Defense-in-depth at the next `insert` / `delete` / `backspace` repairs it. |

**Cluster-fusing inserts (added in v4, both branches addressed in v5).**
The §1.1 splice policy guarantees the splice's `safe_start` and
`safe_start + safe_deleted_len` are boundaries in the *old* text. It
does NOT guarantee that the resulting cursor lands on a boundary in
the *new* text, because UAX #29 cluster formation can extend across
the splice point. **Both `apply_text_edit_internal` branches are
affected**, with subtly different failure modes:

- **`move_cursor_to_edit_end = true` branch** (CM6Adapter, BlockInput,
  the `apply_text_edit` entry). New cursor = `safe_start + inserted.length()`.
  Failure: doc `"🇯🇵🇺🇸"` (boundaries `0,4,8`), splice `(4, 0, "🇮")`.
  After splice, doc `"🇯🇵🇮🇺🇸"` re-pairs RIs into `🇯🇵`, `🇮🇺`, `🇸`
  with boundaries `0,4,8,10`. New cursor `4 + 2 = 6` lands inside the
  new `🇮🇺` cluster.

- **`move_cursor_to_edit_end = false` branch** (`insert_at`,
  `delete_at`, `set_text_and_record`, span edits). The cursor is left
  alone (or clamped). Failure: doc `"👩💻"` (woman + laptop, two
  separate clusters, boundaries `0,2,4`), cursor `2` (boundary
  between them). `insert_at(2, "\u{200D}")` (ZWJ insert) is
  boundary-aligned in the old text. After splice, doc `"👩‍💻"` is
  one cluster (woman + ZWJ + laptop = profession emoji), boundaries
  `0,5`. Cursor stays at `2`, now interior. v4 missed this branch.

- Same risk class with ZWJ insertions joining adjacent emoji into a
  family/profession sequence, or virama insertions joining Indic
  consonants into a conjunct, or VS-16 insertions promoting a
  text-style heart to emoji-style.

The unconditional post-snap on `new_text` (applied in both branches)
covers all cases. Cost is one extra moji call per splice. Performance
is **typically local** — UAX #29 grapheme rules look back a small
fixed window — but **worst-case proportional to the containing
sequence** for pathological RI/ZWJ/Extend runs. Moji implementations
typically use safe-boundary backup or a cached boundary array; see
[UAX #29 implementation notes](https://www.unicode.org/reports/tr29/).

§3 ("splice-boundary integrity") explicitly defers the broader question
of "does the inserted text combine with neighbours in unintended ways?"
The v4 post-snap addresses only the *cursor-position* consequence, not
the broader semantic question. A user who pastes a regional indicator
between two existing flags will see them re-pair; that is a
splice-integrity concern, not a cursor-invariant concern.

**Defense in depth:** every entry point to `delete` / `backspace` /
the per-char insert path performs a defensive `is_grapheme_boundary`
assertion in debug builds. In release builds, if the invariant is
violated (defect from a missed migration, undo, or out-of-band cursor
mutation), pre-snap the cursor and continue rather than corrupt the
document.

**Repair-direction (v5 — recommendation switched from A to B).** Two
reasonable interpretations exist when the cursor lands interior to a
cluster:

- **A (snap outside containing cluster).** Forward delete snaps cursor
  forward, then strict-steps; deletes the *next* cluster, leaving the
  containing cluster intact. Backspace snaps cursor backward; deletes
  the *previous* cluster.
- **B (snap toward containing cluster).** Forward delete snaps cursor
  backward (treating cursor as on the left boundary of the containing
  cluster), then strict-steps forward; deletes the containing cluster.
  Backspace snaps forward, then strict-steps backward; also deletes
  the containing cluster.

v4 recommended A. v5 switches to **B** for two reasons:

1. **Matches §1.1 splice policy.** §1.1 says "any partially-touched
   cluster is fully consumed" for replacement/deletion splices. The
   per-char delete/backspace defense should follow the same rule for
   consistency.
2. **Matches editor UX.** Most code editors treat backspace from
   inside a cluster as "delete the cluster I'm in," not "delete the
   neighbour." For `"a😀b"` with cursor `2`, A makes forward delete
   remove `b` and backspace remove `a` — surprising. B deletes the
   emoji in both cases, which is what users expect.

Concretely (option B):

- Forward delete with interior cursor: snap cursor backward
  (`cursor = prev_grapheme_boundary(text, cursor)`) to the left
  boundary of the containing cluster. Then strict-step forward —
  deletion range is `cursor..<next_grapheme_boundary(text, cursor + 1)`.
- Backspace with interior cursor: snap cursor forward
  (`cursor = next_grapheme_boundary(text, cursor)`) to the right
  boundary of the containing cluster. Then strict-step backward —
  deletion range is `prev_grapheme_boundary(text, cursor - 1)..<cursor`,
  with new cursor = `prev_grapheme_boundary(text, cursor - 1)`.

Since the invariant should hold in normal operation, the repair is
rare; either choice is non-corrupting. The §0.5 invariant + §1.1
splice policy together should make interior cursors essentially
unreachable in practice; the repair is hardening, not a hot path.

The pre-snap is a *repair*, not a *spec*. The spec is the invariant.
The repair exists only because catching every callsite that mutates
`self.cursor` is fragile across refactors; defense-in-depth costs one
extra moji call and prevents data corruption.

This invariant is what makes the §1.3/§1.4 strict-step formulas
correct. Without it, `next_grapheme_boundary(text, cursor + 1)` is
not "next cluster's right boundary" — it's "the next boundary after
position `cursor + 1`," which only equals "next cluster's right
boundary" when `cursor` itself was a left boundary.

## 1. Per-call-site analysis

Per the audit, the following call sites need grapheme awareness. v2
adds §1.10 (`compute_text_change`) and breaks out the `_and_record`
family.

### 1.1 `apply_text_edit_internal` — bulk-splice seam (POLICY UPDATED)

`editor/sync_editor_text.mbt:105`. Called from `apply_text_edit`
(CM6Adapter, BlockInput, post-#246 ideal bridge), `set_text`,
`set_text_and_record`, `insert_at`, `delete_at`, and tree-edit-derived
span edits.

- **Operation:** snap the splice to grapheme boundaries. **Policy
  splits by operation type:**

  - **Pure insertion (`deleted_len == 0`):** snap `start` to a *single*
    boundary using one direction. The recommended direction is `prev`
    (insertion happens at the boundary before the requested position),
    matching "the cluster the user clicked into starts here." This is
    the §1.5 cursor-snap question; see Direction ambiguity below for
    the alternative.
  - **Replacement / deletion (`deleted_len > 0`):** snap `start` with
    `prev_grapheme_boundary`, snap `start + deleted_len` with
    `next_grapheme_boundary`. Round expansively — any partially-
    touched cluster is fully consumed. This matches user intuition for
    "delete the thing under the cursor."

  v1 used the expansive rule for both cases. That was wrong for pure
  insertion: in `"a😀b"`, inserting `"X"` at UTF-16 offset 2 with
  `deleted_len = 0` snapped (1, 3), turning the insert into a
  replacement that destroys the emoji. The v2 split fixes this.

- **Current:** clamps `start` to `[0, text_len]` and `deleted_len` to
  `[0, text_len - safe_start]`. Code units only.

- **Inputs needed:** the document text and the two integer endpoints.

- **Failure modes if not grapheme-aware:** as v1, plus the
  insertion-vs-replace failure described above.

- **After grapheme snap, the conversion to item-space happens.** §0,
  step 2.

### 1.2 `SyncEditor::insert` — per-char cursor edit

`editor/sync_editor_text.mbt:4`. Bypasses the seam.

- **Operation:** maintain the cursor on a grapheme boundary across the
  insert.
- **Current:** `self.cursor = self.cursor + text.length()`.
- **Inputs needed:** document text, post-insert cursor position.
- **Failure mode:** post-insert cursor lands inside a multi-codeunit
  cluster.
- **Function used:** `next_grapheme_boundary(text, cursor)` to round
  the post-insert cursor forward.
- **Unit assumption (v4 rephrase).** All §1.x analyses assume §6.1
  Option A — `self.cursor` is a UTF-16 code-unit offset. If §6.1
  picks Option B (item-space) or Option C (grapheme-ordinal), §1.2–
  §1.4 need to be redone with the chosen unit's boundary semantics.
  Moji's API is UTF-16-shaped regardless; the cursor unit is canopy's
  decision.

### 1.3 `SyncEditor::delete` — per-char forward delete (REVISED IN V3)

`editor/sync_editor_text.mbt:20`. Bypasses the seam.

- **Pre-condition:** `is_grapheme_boundary(text, cursor)` per §0.5.
  If violated, pre-snap per §0.5 Option B: `cursor = prev_grapheme_boundary(text, cursor)`
  (snap to left boundary of containing cluster), then strict-step.
- **Operation:** delete the entire grapheme cluster starting at the
  cursor.
- **Current:** `doc.delete(@text.Pos::at(self.cursor))`.
- **Function used:** **strict next-cluster step from a boundary.**
  With the cursor invariant in force, compute
  `right = next_grapheme_boundary(text, cursor + 1)` (clamped to
  `<= text.length()`); deletion range is `cursor..<right`. The `+1`
  is required because at-or-after of `cursor` itself returns `cursor`
  when the invariant holds.
- **Bounds:** if `cursor >= text.length()`, no-op.
- v2 omitted the cursor invariant and the §0.5 repair; the formula
  bisected surrogate pairs whenever the cursor was interior. v3 makes
  the invariant a hard contract and the formula correct *given the
  invariant*.
- **Item-space conversion still required** after computing the UTF-16
  deletion range.

### 1.4 `SyncEditor::backspace` — per-char reverse delete (REVISED IN V3)

`editor/sync_editor_text.mbt:37`. Bypasses the seam.

- **Pre-condition:** `is_grapheme_boundary(text, cursor)` per §0.5.
  If violated, pre-snap per §0.5 Option B: `cursor = next_grapheme_boundary(text, cursor)`
  (snap to right boundary of containing cluster), then strict-step backward.
- **Operation:** delete the cluster ending at the cursor.
- **Current:** `cursor = cursor - 1; doc.delete(cursor)`.
- **Function used:** **strict prev-cluster step from a boundary.**
  Compute `left = prev_grapheme_boundary(text, cursor - 1)` (clamped
  to `>= 0`); deletion range is `left..<cursor`; new cursor is `left`.
  Same `−1` rationale as §1.3.
- **Bounds:** if `cursor <= 0`, no-op.

### 1.5 `SyncEditor::move_cursor` — cursor placement

`editor/sync_editor_text.mbt:62`.

- **Operation:** snap the requested position to a grapheme boundary.
- **Function used:** snap. Direction ambiguous; canopy decides.
  - *Snap previous:* `prev_grapheme_boundary(text, pos)`. Stable.
  - *Snap nearest:* compute both prev and next; pick whichever has
    smaller code-unit distance from `pos`.

  Both expressible from the two primitives.

### 1.6 `move_cursor_left/right_grapheme` and word variants (STRICT FIX)

Shipped via #251 per TODO.md §16.

- **Operation:** strict step left/right by one cluster (or one word).
- **Function used (corrected):**
  - Left grapheme: `prev_grapheme_boundary(text, cursor - 1)`,
    clamped to `>= 0`. If `cursor == 0`, no-op.
  - Right grapheme: `next_grapheme_boundary(text, cursor + 1)`,
    clamped to `<= text.length()`. If `cursor == text.length()`, no-op.
  - Word variants: same shape with `prev_word_boundary` /
    `next_word_boundary`.

  v1 hand-waved between "if on boundary, then strict; else snap." The
  `pos ± 1` form unifies both cases at the cost of requiring moji to
  accept positions inside clusters (which it must — see §2.1).

- **Editor word-navigation policy is a separate concern.** UAX #29
  word boundaries appear at every transition between word characters,
  whitespace, and punctuation. Editor "word movement" usually skips
  whitespace and may treat punctuation specially. Moji provides the
  raw boundaries; canopy layers the policy. See §6 open question.

### 1.7 `text_diff::find_common_prefix` / `find_common_suffix_after_prefix`

`editor/text_diff.mbt:166` and `:182`.

- **Operation:** longest common prefix and suffix at grapheme-cluster
  granularity. Returns code-unit length (unchanged unit).
- **Function used:** `grapheme_clusters` for the forward walk;
  `grapheme_clusters_reverse` for the suffix walk *if* moji supplies
  it, otherwise canopy materialises a forward array of boundaries and
  iterates in reverse (see §2.4).

### 1.8 `compute_split_block` — markdown block split

`lang/markdown/edits/compute_markdown_edit.mbt:211`.

- **Operation:** snap the `offset` argument to a grapheme boundary
  inside the block's text span before computing the split.
- **Function used:** `next_grapheme_boundary(source, split_pos)`
  (recommended direction: split *after* the cluster the user pointed
  at). Same direction-ambiguity comment as §1.5.

### 1.9 `bridge.ts::applySpliceChanges` (REVISED)

`examples/ideal/web/src/bridge.ts:154`.

- **Operation:** none on the JS side **if** the MoonBit seam *rejects*
  non-boundary splices via the existing `handle_text_intent_checked`
  Bool return. Snapping silently inside the seam is unsafe given the
  JS-side bookkeeping.

  v1 claimed silent snapping was safe because the bridge doesn't see
  the adjusted lengths. That is wrong: the bridge maintains
  `posOffset += change.insert.length - deleteLen` across changes in a
  batch. If the seam expanded change K's deletion (e.g. `deleteLen = 0`
  inside `"😀"` snapped to `deleteLen = 2`), MoonBit removed two code
  units while JS thinks zero were removed; change K+1 in the batch
  targets the wrong location.

- **Recommended seam policy — name the split explicitly:**

  | FFI | Semantic name | Behavior on non-boundary splice |
  |---|---|---|
  | `handle_text_intent_checked` | **"exact splice"** | Reject (return `false`); doc unchanged. Caller maintains its own offset bookkeeping; silent snapping would diverge it. |
  | `handle_text_intent` | **"snap splice"** | Snap endpoints per §1.1 policy; apply. Callers do not maintain cumulative offsets. |
  | `set_text` / `set_text_and_record` | "full replace" | No splice positions to validate; the doc-level diff is recomputed via §1.10. |

  These names should appear in the FFI doc-comments. The current
  contract documents `_checked` only as "Bool-returning variant" —
  insufficient. Future callers reading "checked" might assume "checked
  = bounds-checked" and pick it from a non-batched context, then be
  surprised by rejection of legitimate-looking splices. Or worse, pick
  the unchecked variant from a batched context (re-introducing the
  `posOffset` drift that v2's recommendation was meant to prevent).

- **Partial-batch trigger expansion (v3 callout).** The bridge's
  existing partial-batch behavior — if change K rejects, changes
  `0..K-1` stay applied to the CRDT but un-broadcast until the next
  successful edit's `export_since_json` — is preserved by v2's
  rejection policy, but the *trigger surface widens*. Pre-#246 the
  only trigger was CM6/CRDT drift (rare); post-grapheme-rejection it
  becomes drift OR any non-boundary splice (more likely with non-ASCII
  input). This is not a new bug class but it is a more-likely-to-fire
  one. Cross-references TODO §16's standalone follow-up on tightening this.

- **Inputs needed from moji:** none directly; the seam calls the
  primitives already listed.

- **Bridge-side change required at integration time** (out of scope
  for the moji API but must be in the integration plan): when
  `handle_text_intent_checked` returns false, the bridge currently
  logs and aborts the batch. That stays correct. The CM6Adapter and
  BlockInput entries on the unchecked path do not change.

### 1.10 `text_diff::compute_edit` and `compute_text_change` (NEW IN V2)

`editor/text_diff.mbt:6` → `lib/text-change/text_change.mbt:13`.

v1 marked this out of scope. Codex flagged it as misclassified — both
`SyncEditor::set_text` and `SyncEditor::set_text_and_record` route the
new text through `@text_change.compute_text_change` *before* reaching
the seam. Existing xfail tests in `editor/text_diff_test.mbt` already
pin its surrogate-splitting behaviour.

- **Operation:** compute a `(start, delete_len, inserted)` splice from
  `(old_text, new_text)` such that the splice does not bisect any
  grapheme cluster.
- **Current:** byte/codeunit walk; can return splices with lone
  surrogates in `inserted`.
- **Function used:** `grapheme_clusters` + (optionally) reverse
  iteration. **Fix lives in `lib/text-change/text_change.mbt`** —
  Option A is the unconditional recommendation in v3.

  v2 listed Option B (post-snap at call sites) as an alternative that
  "keeps the leaf module dependency-free." Codex pointed out this
  framing was misleading: `compute_text_change` has callers outside
  the editor — at minimum `valtio/src/egwalker.mbt` (submodule) and
  `loom/loom/src/core/delta.mbt` (submodule). Option B would leave
  those un-fixed and re-introduce the bug whenever any of them
  produces a CRDT splice from a string diff. The leaf module is the
  only place where a single fix covers every caller.

- **`text_diff::compute_edit` (the editor-layer wrapper)** is a thin
  veneer over `compute_text_change`. Fixing the leaf module fixes the
  veneer and the submodule callers in one move.

- **Submodule coordination — verified in v5.** Codex v5 review
  confirmed `valtio/moon.mod.json` path-deps on `../lib/text-change`
  and `loom/loom/moon.mod.json` path-deps on `../../lib/text-change`.
  Both submodules share canopy's lib via path-dep, so the single fix
  in `lib/text-change/text_change.mbt` covers all current callers
  (canopy editor + valtio + loom). No fork consolidation needed.

### 1.11 Per-char `_and_record` family (NEW IN V2)

`ffi/lambda/undo.mbt:37,46,55` — `insert_and_record`,
`delete_and_record`, `backspace_and_record` duplicate the §1.2–§1.4
direct `doc.insert / doc.delete` paths (rather than calling them).

- Same moji functions cover them. Listed explicitly so the integration
  PR doesn't fix one family and leave undo-recorded typing broken.
- `set_text_and_record` is covered by §1.1 (it's a seam caller).

### Direction ambiguity (consolidated, updated)

| Site | Recommended direction | Alternative |
|---|---|---|
| §1.1 splice — pure insertion | `prev` (snap point) | `next` (snap point) |
| §1.1 splice — replacement, start | `prev` (round down) | `next` (shrink) |
| §1.1 splice — replacement, end | `next` (round up) | `prev` (shrink) |
| §1.5 `move_cursor` | `prev` (stable) | nearest (mouse intuition) |
| §1.8 `compute_split_block` | `next` (split after) | `prev` (split before) |

All five expressible from `prev_grapheme_boundary` /
`next_grapheme_boundary`. Canopy decides per call site at integration
time. The pure-insertion split (new in v2) is the most consequential
change.

## 2. Minimum API surface

### 2.1 Required functions and offset-tolerance contract

```moonbit
/// Largest grapheme-cluster boundary `<= pos`. Returns `pos` if it
/// already is a boundary. Returns `0` if `pos <= 0`.
///
/// MUST accept any UTF-16 code-unit offset, including positions
/// inside surrogate pairs and inside multi-codepoint clusters.
/// MUST NOT abort on out-of-range positions; clamp to
/// `[0, text.length()]` and answer for the clamped value.
pub fn prev_grapheme_boundary(text : String, pos : Int) -> Int

/// Smallest grapheme-cluster boundary `>= pos`. Returns `pos` if it
/// already is a boundary. Returns `text.length()` if `pos >= text.length()`.
///
/// Same offset-tolerance contract as `prev_grapheme_boundary`.
pub fn next_grapheme_boundary(text : String, pos : Int) -> Int

/// Word-boundary counterparts of `prev_/next_grapheme_boundary` per
/// UAX #29 word segmentation. Same offset-tolerance contract.
///
/// These return raw UAX #29 boundaries. Editor word-navigation
/// policy (skip whitespace, treat punctuation specially) layers on
/// top in canopy.
pub fn prev_word_boundary(text : String, pos : Int) -> Int
pub fn next_word_boundary(text : String, pos : Int) -> Int
```

**Offset-tolerance contract — preferred shape.** Canopy uses the
`pos ± 1` pattern for strict-step cursor movement (§1.3, §1.4, §1.6),
which intentionally passes positions inside clusters. The contract
above (accept any UTF-16 offset, including mid-surrogate / mid-cluster)
is the simplest API for canopy.

**Fallback contract — if moji can only segment well-formed codepoint
streams.** A pure UAX #29 implementation may not natively accept
arbitrary UTF-16 offsets (the algorithm is defined over codepoints,
not code units). If the moji author finds the offset-tolerance
contract too invasive, an alternative shape that still covers every
canopy call site:

```moonbit
/// Boundary array indexed by code-unit offset (sparse) or returned
/// as a sorted list. Always starts with `0` and ends with
/// `text.length()`.
pub fn grapheme_boundaries(text : String) -> Array[Int]

/// Word-boundary counterpart.
pub fn word_boundaries(text : String) -> Array[Int]
```

Canopy then derives `prev_/next_*_boundary(text, pos)` and
`is_*_boundary(text, pos)` by binary-searching the array. The cost is
O(n) memory per call (unless canopy caches per text-version) and
O(log n) per query, vs. O(?) for moji's native segmentation. For
editor-scale strings this is acceptable. The §0.5 cursor invariant
and the §1.3/§1.4 strict-step formulas continue to work; the strict
formulas become "binary-search for the first boundary > `cursor`,"
which is well-defined for any integer cursor including mid-cluster.

The trade is: **simpler moji contract** (boundaries from a
codepoint-stream walk) vs. **more glue in canopy** (binary-search
plus optional per-version caching). The fallback is preferred over
the moji author refusing the offset-tolerance contract and forcing
canopy to call `is_boundary` before every `prev_/next_` query.

### 2.2 Ergonomics helpers (required-if-cheap)

```moonbit
/// True iff `pos` is a UAX #29 grapheme cluster boundary.
/// Endpoints `0` and `text.length()` are always boundaries.
/// Same offset-tolerance contract.
///
/// Derivable as `prev_grapheme_boundary(text, pos) == pos`. Listed
/// because it makes assertion sites read clearly and avoids
/// reimplementing the equality check.
pub fn is_grapheme_boundary(text : String, pos : Int) -> Bool

/// Iterate (start, end) UTF-16 code-unit ranges, one per cluster, in
/// forward order. Empty string yields zero items.
///
/// Derivable as a loop over `next_grapheme_boundary` from 0. Listed
/// because diff-style callers benefit from a ready-made iterator.
pub fn grapheme_clusters(text : String) -> Iter[(Int, Int)]
```

If implementation cost is non-trivial, omit. Canopy can build both
from the two required primitives.

### 2.3 Reverse iteration — caller composes (DECIDED IN V2)

```moonbit
// OPTIONAL — only if natural in moji's implementation:
pub fn grapheme_clusters_reverse(text : String) -> Iter[(Int, Int)]
```

**Recommendation:** moji exposes only the forward `grapheme_clusters`.
Canopy materialises a forward `Array[(Int, Int)]` of boundaries once
per `compute_text_change` call and iterates it in reverse for the
suffix scan. This costs O(n) memory and one forward pass per diff,
which is acceptable for editor-scale strings.

If moji has a natural reverse-walk (UAX #29 defines one), it's a free
ergonomics win — but not required.

v1 left this half-recommended. v2 picks one.

### 2.4 Driver mapping (which sites drive each function)

| Function | Drivers |
|---|---|
| `prev_grapheme_boundary` | §0.5 backspace defense pre-snap, §1.1 (replace start), §1.4 backspace strict step (`pos-1`), §1.5 cursor (option A), §1.6 left arrow (`pos-1`), §1.7 (via iterator), §1.8 split (option B), §1.10 diff prefix |
| `next_grapheme_boundary` | §0.5 forward-delete defense pre-snap + `apply_text_edit_internal` post-snap + `insert` post-snap, §1.1 (insert point + replace end), §1.2 post-insert clamp, §1.3 forward delete strict step (`pos+1`), §1.5 cursor (option B), §1.6 right arrow (`pos+1`), §1.7 (via iterator), §1.8 split (option A), §1.10 diff prefix/suffix |
| `prev_word_boundary` | §1.6 left-by-word |
| `next_word_boundary` | §1.6 right-by-word |
| `is_grapheme_boundary` | §0.5 debug-build invariant assertion; test scaffolding |
| `grapheme_clusters` | §1.7, §1.10 prefix/suffix scan; future render-layer chunking |

## 3. Out of scope — explicitly NOT in this API

Listed so moji does not grow accidentally.

- **Normalization** (NFC, NFD, NFKC, NFKD). Application-level decision;
  canopy stores what the user typed.
- **Bidi (UAX #9).** Renderer's job.
- **Casing.** No call site uses it. Locale handling (Turkish dotted-I)
  is well beyond #216.
- **Display width / East Asian width.** Renderer's job.
- **Line / sentence boundaries.** Defer until a concrete driver
  appears.
- **Script / language detection / collation.**
- **Well-formedness validation.** The CRDT layer's `MalformedContent`
  rejection covers the wire boundary; the editor trusts MoonBit
  `String` to be a valid UTF-16 sequence.
- **Splice-boundary integrity** — checking that an *inserted* string
  doesn't fuse with surrounding text into an unintended cluster (e.g.
  regional indicator merging with neighbour). Real concern, but not a
  moji API blocker. Canopy may layer it later by re-checking boundaries
  on the post-splice text using the primitives moji already exposes —
  no new moji function required.
- **JS bindings.** Moji is a MoonBit library. The JS side does not
  call moji directly; the bulk-splice seam carries the conversion.
- **CRDT position conversion.** UTF-16 ↔ item-space is canopy's
  responsibility (§0 step 2). Moji has no opinion about CRDT slots.
- **Legacy `editor/editor.mbt` `Editor`** mutates `cursor` / `doc`
  directly without going through `SyncEditor`. Codex v5 review notes
  it appears test-only — real language companions use `SyncEditor`.
  v5 declares it out-of-scope for #216 Step 2. If a future migration
  promotes it to non-test use, redo §1.2–§1.4 for the legacy paths.

## 4. Test-vector requirements

These are the unicode fixture cases canopy will use to verify the
*integration*, not what moji needs to prove internally (moji's own
tests presumably exercise UAX #29 reference data).

Reference: `memory/project_unicode_failure_modes.md`. The bimodal
failure pattern means tests need both `panic`-prefix tests
(historically; less needed post eg-walker #31) and `inspect` snapshots
pinned to current values.

### 4.1 Grapheme boundary fixtures (expanded in v2)

| Category | Sample input | Expected boundaries (UTF-16 code units) | Why |
|---|---|---|---|
| ASCII | `"hello"` | `0,1,2,3,4,5` | Baseline. |
| BMP single | `"あ"`, `"中"` | `0,1` | Single-codeunit non-Latin. |
| BMP combining | `"e\u{0301}"` | `0,2` | Combining mark binds to base. |
| Precomposed equivalent | `"é"` | `0,1` | Single codeunit; should not equal the previous case in code units even though they render the same. |
| Non-BMP single | `"😀"`, `"𠮷"` | `0,2` | Surrogate pair = one cluster of 2 codeunits. |
| Mixed | `"a😀b"` | `0,1,3,4` | Cluster boundaries skip surrogate interior. |
| ZWJ family | `"👨‍👩‍👦"` | `0,8` | Three emoji + two ZWJs collapse into one cluster. |
| **Skin-tone modifier** | `"👋🏽"` | `0,4` | Emoji + Fitzpatrick modifier. (v2 add) |
| **Variation selector** | `"❤️"` | `0,2` | Heart + VS-16 (text→emoji presentation). (v2 add) |
| **RGI ZWJ profession** | `"👩🏽‍💻"` | `0,7` | Emoji + skin tone + ZWJ + emoji. (v2 add) |
| Regional indicator | `"🇯🇵"` | `0,4` | Two RIs bond into one flag. |
| Two adjacent flags | `"🇯🇵🇺🇸"` | `0,4,8` | Pair-bonding stops every two RIs. |
| **Hangul jamo (decomposed)** | `"\u{1100}\u{1161}\u{11A8}"` | `0,3` | L+V+T jamo sequence forms one syllable cluster. **Note:** literal `"각"` is precomposed `U+AC01` and has boundaries `0,1` — different test, also worth pinning. (v2 add; input form fixed in v3) |
| **Hangul precomposed** | `"각"` (`U+AC01`) | `0,1` | Single precomposed syllable. Should NOT be folded with the decomposed jamo case — they're distinct strings even if they render the same. (v3 add) |
| **Indic virama conjunct** | `"क्ष"` (`U+0915 U+094D U+0937`) | `0,3` (per Unicode 15+; older versions may differ) | Devanagari virama joins consonants. (v2 add — version-sensitive; pin moji's Unicode version in the test) |
| **CRLF** | `"a\r\nb"` | `0,1,3,4` | CRLF is one cluster (UAX #29 GB3). (v2 add) |
| Empty | `""` | `0` | Edge case. |
| Leading combining | `"\u{0301}a"` | `0,1,2` | Combining mark with no base — degenerate but valid. |

### 4.2 Per-call-site test pattern

For each call site in §1, the integration test pins:

1. The current (pre-moji) behaviour with an `inspect` snapshot tagged
   `// PRE-MOJI: known-broken`.
2. The post-moji behaviour in a sibling test guarded by a feature
   flag, replaced at integration time.

The two-test pattern keeps canopy CI green during moji development;
flipping the snapshots is the merge gate.

### 4.3 Word-boundary fixtures

UAX #29 word boundaries only — editor word-navigation policy
(whitespace-skipping, punctuation handling) is layered on top and has
its own test file.

| Category | Sample input | Notes |
|---|---|---|
| Latin words | `"hello world"` | Boundaries at `0,5,6,11`. |
| CJK | `"日本語"` | Each character is its own word per UAX #29 (no inter-Han spaces). |
| Mixed script | `"hello 日本"` | Latin word + CJK word boundary. |
| Punctuation | `"don't"` | Apostrophe is part of the word per WB6. |
| Numeric | `"$3.14"` | Number cluster. |
| Hangul | `"안녕하세요"` | Each syllable becomes its own word for editor purposes; UAX-level may differ. (v2 add) |

### 4.4 Splice-policy fixtures (split by seam variant in v3)

v2 had a single table that conflated the two seam variants. Per
§1.9, `handle_text_intent_checked` ("exact splice") rejects
non-boundary splices, while `handle_text_intent` ("snap splice")
applies the §1.1 policy. Both behaviours need fixtures.

**Snap-splice fixtures — drives `handle_text_intent` and the §1.1
policy split:**

| Operation | Input doc | Splice (UTF-16) | Expected post-policy splice |
|---|---|---|---|
| Pure insert mid-cluster | `"a😀b"` | `(2, 0, "X")` | `(1, 0, "X")` *(snap start to prev boundary, deleted_len stays 0)* |
| Pure insert on boundary | `"a😀b"` | `(1, 0, "X")` | `(1, 0, "X")` *(no change)* |
| Replace mid-cluster | `"a😀b"` | `(2, 1, "X")` | `(1, 2, "X")` *(start prev, end next)* |
| Replace on boundaries | `"a😀b"` | `(1, 2, "X")` | `(1, 2, "X")` *(no change)* |
| Delete mid-cluster | `"a😀b"` | `(2, 1, "")` | `(1, 2, "")` |

**Exact-splice fixtures — drives `handle_text_intent_checked`:**

| Operation | Input doc | Splice (UTF-16) | Expected result |
|---|---|---|---|
| Pure insert mid-cluster | `"a😀b"` | `(2, 0, "X")` | **reject** (`false` return); doc unchanged |
| Pure insert on boundary | `"a😀b"` | `(1, 0, "X")` | accept; doc becomes `"aX😀b"` |
| Replace mid-cluster | `"a😀b"` | `(2, 1, "X")` | **reject**; doc unchanged |
| Replace on boundaries | `"a😀b"` | `(1, 2, "X")` | accept; doc becomes `"aXb"` |
| Delete mid-cluster | `"a😀b"` | `(2, 1, "")` | **reject**; doc unchanged |

The two tables share inputs intentionally — same splices, different
seam, different outcomes. The bridge calls the checked path; CM6Adapter
and BlockInput call the unchecked path. Fixture parity makes it
obvious which seam each call site exercises.

**Cluster-fusing-cursor fixtures (v5 add — drives §0.5 post-snap on
both `apply_text_edit_internal` branches):**

| Branch | Input doc | Cursor before | Splice (UTF-16) | Expected cursor after |
|---|---|---|---|---|
| `move_cursor_to_edit_end = true` | `"🇯🇵🇺🇸"` | any | `(4, 0, "🇮")` | `8` *(post-snap from naive `6`, snapped past `🇮🇺` cluster)* |
| `move_cursor_to_edit_end = false` (e.g. `insert_at`) | `"👩💻"` | `2` | `(2, 0, "\u{200D}")` | `0` or `5` *(post-snap from `2`; new doc `"👩‍💻"` has only `0,5` — direction depends on §1.5 choice)* |
| `move_cursor_to_edit_end = false` (e.g. `insert_at`) | `"a"` | `0` | `(1, 0, "\u{0301}")` | `0` *(cursor stays at `0`, which is a boundary in `"a\u{0301}"`)* |

The middle row is the failure scenario v4 missed. The post-snap
direction question is open per §6.2; pick consistent with the §1.5
`move_cursor` decision so cluster-fusing inserts and explicit cursor
moves behave the same way.

## 5. What this spec does not answer

- **Moji's implementation strategy** — table-driven vs. property-
  derived vs. external Unicode data.
- **Performance characteristics.** Canopy call sites scan short
  strings or do single forward walks; O(n) point queries are fine.
- **Versioning policy** — which Unicode version moji tracks. Document
  on moji's side; canopy will pin in tests (especially Indic
  conjuncts, which moved between Unicode versions).
- **Allocation strategy** — tuple iterator vs. out-buffer.

## 6. Historical questions for the human reviewer

In rough order of how much they shape the integration plan.

### 6.1 (NEW IN V2, HEADLINE) Unit-storage decision

**Current status:** #251 chose Option A. `self.cursor`, `move_cursor`, and
`get_cursor` remain UTF-16 code-unit offsets, with editor APIs maintaining a
grapheme-boundary invariant.

**Original question:** what unit should canopy store internally for
`self.cursor` and the public `move_cursor` / `get_cursor` boundary?
Three options, each shifts where conversions live:

| Option | `self.cursor` unit | What changes |
|---|---|---|
| A — keep UTF-16 | UTF-16 code unit | Per-char paths (§1.2–§1.4) gain a UTF-16 → item-space conversion before every CRDT call. Public boundary unchanged. Smallest blast radius. |
| B — switch to item-space | one per codepoint | CRDT calls become natural. Public boundary needs UTF-16 → item-space conversion at every entry (CM6, BlockInput, bridge, undo). Larger blast radius but eliminates per-call codepoint counting. |
| C — switch to grapheme-ordinal | one per cluster | Public boundary becomes the reserved `GraphemeOffset` opaque type. Both layers (moji + item-space) live at the boundary. Largest blast radius but cleanest invariant. |

The option chosen drove whether the seam needed both conversions on every call
(A) or just one (B), and whether `GraphemeOffset` became real immediately or
stayed reserved.

**Codex review (v3 pass) recommended Option A**, with reasoning:

- Smallest blast radius. Public boundary stays UTF-16 (matching CM6,
  the textarea API, and existing FFI shapes).
- Conversions live at well-defined seams (§0 step 2), not throughout
  the call graph.
- An optional per-text-version boundary cache (Map[doc-version →
  Array[Int]] of grapheme boundaries) makes repeated UTF-16 →
  item-space conversions O(log n) instead of O(n) without committing
  to a unit change.
- B and C are reversible from A but not vice-versa; A preserves
  optionality.

A "hidden fourth option" of dual-store (cursor stored in two units
simultaneously) is unsound — two authoritative cursor units will
drift. Caching is fine; dual *authority* is not.

The original spec deliberately did not pick — this was a human decision, and
Codex's recommendation was one input. Other inputs weighed:

- where canopy expects to land in 12 months (will it eventually need
  to expose grapheme-ordinal externally?);
- how much per-call codepoint counting costs in practice (measure
  before deciding — Option A's per-call O(n) walk may be a non-issue
  with caching);
- whether the `GraphemeOffset` opaque type would land now or later (it did
  not land in #251);
- **bridge impact (v4 add).** Option A leaves the JS bridge wire
  unchanged (still UTF-16 offsets). Options B and C change the public
  boundary, requiring updates to `bridge.ts`, `cm6-adapter.ts`,
  `block-input.ts`, the FFI doc-comments, and any external consumers
  of `get_cursor` / `move_cursor`. Migration cost grows accordingly.

### 6.2 Direction defaults (§1.1, §1.5, §1.8)

Confirm:

- §1.1 pure insertion → snap *prev* (insert before the cluster)?
- §1.5 `move_cursor` → snap *prev* (stable) vs *nearest* (mouse
  intuition)?
- §1.8 `compute_split_block` → snap *next* (split after pointed
  cluster)?

### 6.3 §1.9 seam policy

Confirm: `handle_text_intent_checked` should *reject* (return false)
on non-boundary splices rather than silently snap, to keep the JS
bridge's `posOffset` bookkeeping coherent across batched changes.
`handle_text_intent` (unchecked) and `set_text` may snap silently.

### 6.4 §1.10 placement (CLOSED IN V5)

Resolved: Option A (fix in `lib/text-change/text_change.mbt`). Codex
v5 review verified that `valtio/moon.mod.json` path-deps on
`../lib/text-change` and `loom/loom/moon.mod.json` path-deps on
`../../lib/text-change`, so the §1.10 submodule-coordination caveat
no longer bites — both submodules share canopy's lib. Single fix
covers all callers.

### 6.5 §6.4 / §1.6 word-navigation policy

What does canopy mean by "move by word"? Skip whitespace? Skip
punctuation? Treat camelCase or snake_case as multiple words? Moji
returns raw UAX boundaries; canopy needs to spec the policy layer in
a separate doc before §1.6 ships.

### 6.6 Smaller surface choices

- Keep `is_grapheme_boundary` in the API or make it a derived helper?
- Keep `grapheme_clusters` or have canopy derive it?
- Ship `is_word_boundary` for symmetry, or wait for a driver?

## 7. Process notes

- Spec is prose. No paste-ready implementations. Process band: Light.
- Review history: v1 → v2 (Codex pass 1) → v3 (Codex pass 2) → v4
  (Opus self-review) → v5 (Codex pass 3). All on 2026-05-10. Diff
  highlights at the top. Codex final verdict on v5: shippable for
  external moji review with §6 human decisions still open.
- Recommended next steps before sharing externally with the moji
  author:
  1. Human decides §6.1 (unit-storage) — gates whether §1.2–§1.4
     analyses need redoing under Option B or C.
  2. Human confirms §6.2 direction defaults, §6.3 seam policy, §6.5
     word-navigation policy, §6.6 surface choices.
  3. (Already done in v5) §6.4 closed; submodule grep verified.
- Once §6 decisions are made, rewrite §1.2–§1.4 (if §6.1 ≠ A) and
  collapse the "added in v4" / "v5 fixed" annotations — this spec
  carries enough revision-history scaffolding that a moji author
  reading it cold may find it noisier than necessary. Consider
  producing a clean v6 "for-external-share" cut that preserves the
  technical content but drops the audit-trail for the moji author's
  reading comfort.
