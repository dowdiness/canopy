# Patch Protocol Probe — Decision Record

**Date:** 2026-05-23
**Branch:** `worktree-research-from-main`
**Probe package:** `workspace/probe/patch_protocol_wbtest.mbt`
**Research basis:** `docs/research/2026-05-22-spec-aware-workspace.md` §5.2, Appendix B P0a #2

---

## Question

Can `UserIntent::StructuralEdit { node_id, op: String, params: Map[String, String] }`
(`protocol/user_intent.mbt:11-23`) faithfully carry the full set of Lambda
structural edits, or does it need a protocol-level widening before §5.2
Layer B work begins?

**Decision-exit options:**

- **(i)** Widen `params` to `Map[String, Json]` — small protocol change, broad
  ripple across encoder/decoder sites.
- **(ii)** Per-language typed patch type — more invasive, op-level type-safe.

---

## Scope

The recipe named six ops. Codex review on 2026-05-23 swapped `CommitEdit`
out of the probe (it has its own `UserIntent::CommitEdit` variant, so testing
it through `StructuralEdit` is non-load-bearing) and `WrapInLambda` in (also
exercises the missing/default param semantics from
`lang/lambda/companion/tree_edit_json.mbt:98-107`). Final probe set:

`Rename`, `ExtractToLet`, `WrapInLambda`, `Drop`, `WrapInBop`, `InsertChild`.

---

## Findings

### Verdict table

| Variant         | Category        | What the probe demonstrates                                                                                                                                                                                              |
|-----------------|-----------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `Rename`        | FIT-CLEAN       | Both params natively strings. Inline encode→JSON-roundtrip→decode reproduces source.                                                                                                                                     |
| `ExtractToLet`  | FIT-CLEAN       | Same shape as `Rename`.                                                                                                                                                                                                  |
| `WrapInLambda`  | FIT-CLEAN       | Strings only. Probe additionally verifies the missing-key default policy: an empty `params` decodes via the `"x"` fallback from `lang/lambda/companion/tree_edit_json.mbt:98-107`.                                       |
| `WrapInBop`     | FIT-TOKENIZED   | `@ast.Bop` carried as `"Plus"`\|`"Minus"` string tag (matches `parse_bop_string` at `lang/lambda/companion/tree_edit_json.mbt:29-33`). Codec is ad-hoc; every consumer must mirror the same enum→string mapping.         |
| `Drop`          | FIT-TOKENIZED   | Three forced compromises in one variant: (a) duplicates `source` into the spare `StructuralEdit.node_id` slot since the wire carries a single node_id (`protocol/user_intent.mbt:13-17`) but `Drop` references two nodes (`lang/lambda/edits/tree_lens.mbt:24`); (b) `target` stringified via `id.to_json().stringify()`; (c) `DropPosition` carried as `"Before"`\|`"After"`\|`"Inside"` tag (`lang/lambda/companion/tree_edit_json.mbt:55-63`). Round-trips, but the encoding rule is opaque protocol convention. |
| `InsertChild`   | NEEDS-WIDENING  | `kind: @ast.Term` is a recursive enum (`loom/examples/lambda/src/ast/ast.mbt:17-41`). The only encoding into a `Map[String, String]` value is `term.to_json().stringify()` — JSON smuggled through a String field, violating the protocol's "params values are strings" invariant. Decoding is currently impossible regardless: `@ast.Term` derives only `Eq, ToJson, Debug`, not `FromJson`. |
| (negative ctrl) | enforced today  | Decoder rejects a `UserIntent` JSON whose `params` contains a non-string value (`protocol/user_intent.mbt:129-137`). The constraint isn't theoretical; the wire format enforces it.                                      |

**Summary count:** 3/6 FIT-CLEAN, 2/6 FIT-TOKENIZED, 1/6 NEEDS-WIDENING.

### What the categories actually mean

- **FIT-CLEAN** is the only category where `Map[String, String]` is the
  *right* abstraction — every consumer can read the param without a codec.
- **FIT-TOKENIZED** is where the protocol *appears* to fit but each consumer
  must mirror a per-variant string vocabulary (`"Plus"`/`"Minus"`,
  `"Before"`/`"After"`/`"Inside"`, stringified NodeId, etc.). This is
  exactly what a typed patch type would replace with constructor calls;
  the protocol pretends to be flat strings while leaking enum semantics.
- **NEEDS-WIDENING** is where the abstraction breaks regardless of codecs:
  no choice of string encoding fits a recursive payload without smuggling
  JSON-in-a-string.

A 1/6 NEEDS-WIDENING is sufficient on its own to force a protocol change —
LLM-emitted `InsertChild` is named in the §5.2 Layer B set, so the workspace
work cannot proceed under the current protocol.

---

## Recommendation

**Option (i): widen `params` from `Map[String, String]` to `Map[String, Json]`.**

Reasoning:

1. **Option (i) is necessary.** The `InsertChild` case rules out
   `Map[String, String]` on its own. No alternative encoding satisfies
   both the protocol invariant and the recursive payload.
2. **Option (i) is sufficient at the protocol layer.** The existing FFI
   surface `handle_structural_intent` (`ffi/lambda/intent.mbt:112-140`)
   already takes `params_json` as a raw JSON object string and merges it
   into a `Map[String, Json]` before dispatching to `parse_tree_edit_op`.
   The lower-level path is already JSON-shaped; widening `UserIntent`
   aligns the upper protocol with the lower one rather than introducing a
   new constraint.
3. **Option (ii) is heavier than the gap warrants today.** A per-language
   typed patch type is the right destination *eventually* — typed enums
   beat string tags for compile-time safety — but it's a larger ripple
   (every language needs its own typed enum + JSON codec + protocol
   variant). The current gap is the data shape of one field, not the
   discipline of typing every patch.

### Necessary but not sufficient for `InsertChild`

Widening `params` to `Map[String, Json]` makes `InsertChild` *representable*
on the wire. It does **not** make it decodable. The remaining gap:

- `@ast.Term` lacks `derive(FromJson)` (`loom/examples/lambda/src/ast/ast.mbt:41`).
- Until that derive (or a bespoke `FromJson` impl) is added, a consumer
  receiving an `InsertChild` JSON cannot reconstruct the typed `Term` —
  even with `Map[String, Json]`.

Therefore the §5.2 Layer B story for `InsertChild` requires *both*
the protocol widening *and* the Term codec. These are separable changes;
do the widening first (small, ripple-of-one-field), then the Term codec
follow-up.

---

## Named follow-ups

In rough priority order, all gated on shipping Option (i):

1. **Add `derive(FromJson)` to `@ast.Term`** (or write a bespoke
   `FromJson` impl). Required before `InsertChild` can round-trip from
   LLM output to a typed patch. Trivial mechanical change if `derive`
   suffices; needs care if any variant has unusual JSON shape.
   File: `loom/examples/lambda/src/ast/ast.mbt:41`.
2. **Decide whether `@core.DropPosition` and `@core.NodeId` should
   acquire `derive(FromJson)`.** Today's decoders use manual string-tag
   parsing (`lang/lambda/companion/tree_edit_json.mbt:50-63`). With
   `Map[String, Json]`, `from_json` for these types would be ergonomic
   but not forced. Engineering call, not a correctness gap.
   Files: `core/types.mbt:30-33` (NodeId — has ToJson, no FromJson),
   `core/types.mbt:111-118` (DropPosition — no Json derives at all).
3. **Mirror the existing `parse_tree_edit_op` (`lang/lambda/companion/
   tree_edit_json.mbt:81-223`) at the `UserIntent::StructuralEdit`
   decode site**, OR write a single `UserIntent → TreeEditOp` decoder
   that consumes the widened `params: Map[String, Json]`. Today the
   protocol-level decoder does not exist — only the FFI bridge has one,
   and it bypasses `UserIntent::StructuralEdit` entirely (takes
   `params_json` as a raw JSON object string at
   `ffi/lambda/intent.mbt:117-139`).
4. **Add a Drop / multi-NodeId convention to the protocol.** The probe
   currently encodes Drop as `node_id = source` + `params["target"]`. This
   works but is opaque; either (a) document the convention, (b) extend
   `UserIntent::StructuralEdit` with an optional `extra_node_ids: Array[NodeId]`
   field, or (c) — preferred long-term — collapse this into the typed
   patch type from Option (ii) when it eventually lands.
5. **Audit other languages' patch shapes** before relying on the
   "Map[String, Json] is sufficient" claim. The probe is Lambda-specific.
   Markdown's structural patches today carry only scalars
   (`examples/web/src/markdown-editor.ts:135-152`), but JSON and any
   future language with structured payloads need their own audit.

---

## Probe-design caveats (worth recording before this is read by reviewers)

- **The probe writes its own inline encoder/decoder for each op.** No
  production `UserIntent::StructuralEdit → TreeEditOp` decoder exists in
  the codebase today (the FFI bridge takes a different JSON shape; see
  `ffi/lambda/intent.mbt:112-140` and `lang/lambda/companion/tree_edit_json.mbt`).
  The probe therefore tests *representability of the protocol shape*, not
  any currently-deployed decode path. This is labelled in the probe's
  header comment and was explicitly endorsed by Codex pre-implementation
  review.
- **The FIT-TOKENIZED category is fragile.** Drop's "node_id duplicates
  source" rule is an *invented* convention; the probe could have chosen
  "node_id is unused, source lives in params" or "node_id is target".
  Any of these works for the round-trip, but the probe's verdict for
  Drop is contingent on documenting *one* convention. If reviewers want
  a different convention they can pick — the count of FIT-TOKENIZED
  variants does not change.
- **`@debug.to_string` equality is the assertion device** because
  `@lambda_edits.TreeEditOp` derives only `Debug` (not `Eq`). This means
  the verdicts are "the same Debug-rendered form survives the round-trip"
  rather than "structurally equal values." For the recipe's six ops this
  is good enough; Debug renders all the fields the encoders touch.
- **Toolchain note.** `moon test -f <file>.mbt` produces a corrupted
  blackbox-test driver on this branch (likely related to the
  rr_moon_mod migration noise mentioned in the prompt). Use
  `moon test -p dowdiness/canopy/workspace/probe` (no `-f`) to run the
  probe; all 17 tests (gate #3's 10 + gate #2's 7) pass.

---

## Summary

| Question | Verdict | Confidence |
|----------|---------|------------|
| Can `Map[String, String]` carry the full Lambda patch set? | **No.** 1/6 needs structural payload; 2/6 fit only with ad-hoc tokenization. | High (7 tests, all assertions concrete) |
| Option (i) `Map[String, Json]` vs Option (ii) typed patch? | **Option (i) now.** Necessary for `InsertChild`; aligns the upper protocol with the already-JSON FFI surface. Option (ii) remains the long-term destination for type safety but is over-scoped for the immediate workspace work. | Medium-high (depends on follow-up #1 / Term FromJson landing before Layer B) |
| Is the protocol change blocking §5.2 Layer B? | **Yes for `InsertChild`/`Drop`/`WrapInBop`; no for `Rename`/`ExtractToLet`/`CommitEdit`.** Layer A's `Rename`, `ExtractToLet`, `CommitEdit` can ship under the current protocol; Layer B cannot. | High |

**Action item.** Before §5.2 Layer B work begins: widen `params` to
`Map[String, Json]` and ship follow-up #1 (`@ast.Term` FromJson). Layer A
work can start immediately on the existing protocol.
