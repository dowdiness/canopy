# CRDT Bundle Split Plan

> **For agentic workers:** This is a combined design + implementation plan. Steps use checkbox (`- [ ]`) syntax for tracking. Land as three separate PRs in the order below; do not batch.

**Goal:** replace the single monolithic `ffi/ffi.js` (currently 648 kB minified, exceeds the 500 kB budget by 148 kB) with three per-entry MoonBit FFI packages — one per language page — so each `.html` loads only the machinery it actually needs.

**Source of the 148 kB figure:** live build on `main` at 2026-04-18. The original TODO item cited 553 kB; the gap has grown since.

**Tech Stack:** MoonBit (JS target), existing `vite-plugin-moonbit`, existing language-backend packages under `lang/lambda`, `lang/json`, `lang/markdown`.

**Key prior finding (subtractive measurement, 2026-04-18):**

| Scenario | crdt bytes | Δ from baseline |
|---|---:|---:|
| baseline (all features) | 648,514 | — |
| drop LLM | 629,654 | −18,860 |
| drop Sync (WS + relay) | 635,530 | −12,984 |
| drop Markdown | 600,041 | −48,473 |
| drop JSON | 596,114 | −52,400 |
| drop all non-lambda (LLM+JSON+MD) | 527,970 | −120,544 |
| lambda-only minimum (also drop Sync) | 515,005 | −133,509 |

Interpretation: the **lambda-only floor is ~515 kB** — shared infrastructure (editor, core, event-graph-walker internals, loom parser, lambda typecheck, egglog evaluator, moonbitlang/core runtime). Splitting will drop `json.html` and `markdown.html` well below 500 kB but **will not bring `index.html` under the budget by itself**. See §7.

**Scope boundary:** `ffi/` tree and `examples/web/` wiring only. No changes to `lang/`, `editor/`, `core/`, `event-graph-walker/`, or any MoonBit backend package.

**Out of scope:**
- Reducing the 515 kB lambda floor (tracked as a follow-up — see §7).
- `examples/demo-react/` wiring (mentioned but not verified; cover in a sweep task).
- Any change to FFI semantics or exported function signatures.

**Branch strategy:** one feature branch per PR (`feat/ffi-json-split`, `feat/ffi-markdown-split`, `feat/ffi-lambda-split`). The `ffi_json` PR lands first as the green-field proof and validates the nested-package assumption against `vite-plugin-moonbit`.

---

## File Structure

### New files (after all three PRs)

```
ffi/
├── lambda/                         # PR 3
│   ├── lifecycle.mbt
│   ├── diagnostics.mbt
│   ├── undo.mbt
│   ├── sync.mbt
│   ├── ws.mbt
│   ├── relay.mbt
│   ├── ephemeral.mbt
│   ├── view.mbt
│   ├── pretty.mbt
│   ├── intent.mbt
│   ├── llm.mbt
│   ├── destroy_editor_wbtest.mbt    # moved from ffi/
│   ├── integration_ws_test.mbt      # moved from ffi/
│   ├── relay_room_leak_wbtest.mbt   # moved from ffi/
│   └── moon.pkg
├── json/                           # PR 1
│   ├── lifecycle.mbt
│   ├── diagnostics.mbt
│   ├── edit.mbt
│   ├── view.mbt
│   └── moon.pkg
└── markdown/                       # PR 2
    ├── lifecycle.mbt
    ├── edit.mbt
    ├── view.mbt
    └── moon.pkg
```

**No `ffi/moon.pkg` at the root** — `ffi/` becomes a namespace directory only. MoonBit requires `moon.pkg` to define a package; its absence means `ffi/` is not a package.

**Shared helpers:** if any are needed beyond trivia, create `ffi/common/` as a fourth package. Prefer inlining 1-3-line helpers (`result_to_json`-style) per leaf package over creating a package just to host them.

### Deleted files (end state)

After all three PRs land, the original `ffi/*.mbt` files and `ffi/moon.pkg` are gone. Files move, contents don't change substantively — primarily cut/paste with import-path updates.

### MoonBit package paths

| Before | After |
|---|---|
| `dowdiness/canopy/ffi` | *(deleted)* |
| — | `dowdiness/canopy/ffi/lambda` |
| — | `dowdiness/canopy/ffi/json` |
| — | `dowdiness/canopy/ffi/markdown` |
| — | `dowdiness/canopy/ffi/common` *(only if needed)* |

### Build output paths

MoonBit emits each package's linked JS at `_build/js/release/build/<pkg-path>/<leaf>.js`:

```
_build/js/release/build/ffi/json/json.js
_build/js/release/build/ffi/markdown/markdown.js
_build/js/release/build/ffi/lambda/lambda.js
```

### Modified files (per PR)

- `examples/web/vite.config.ts` — register new virtual modules
- `examples/web/src/*-editor.ts` — switch import from `@moonbit/crdt` to entry-specific virtual module
- `lib/editor-adapter/*.ts` — parameterize over the `crdt` namespace (today the adapter imports `@moonbit/crdt` at module scope; it needs to accept the namespace as a constructor/factory argument so each entry can pass its own)
- `examples/web/scripts/build-deploy.sh` — update output paths if referenced
- `examples/web/playwright.config.ts` + tests — adjust fixtures if they reference the old path
- `CI_CD_SETUP.md` — documentation sweep

---

## Phase 0 — Baseline and scouting

**Goal:** confirm the working tree builds green, capture the current bundle size deterministically, and identify every file that references `ffi/ffi.js` before any edit.

**Files:** none — this is a read-and-confirm phase.

- [ ] **Step 1:** `moon check && moon test` from canopy root. Expected: green.
- [ ] **Step 2:** `cd examples/web && npm run build` and record the `dist/assets/crdt-*.js` byte size as the baseline.
- [ ] **Step 3:** `grep -rn "_build/js/release/build/ffi/ffi.js" .` from canopy root. Record every hit — each is a migration target.
- [ ] **Step 4:** `grep -rn "@moonbit/crdt" .` from canopy root, excluding `node_modules` and `_build`. Record every hit.
- [ ] **Step 5:** `moon ide outline ffi/` to confirm the current public surface.
- [ ] **Step 6:** If any of 1–5 surprises you, stop and reconcile before starting Phase 1.

---

## Phase 1 — PR 1: `ffi/json/` green-field package

**Goal:** create `ffi/json/` as an independently-linked MoonBit package exporting only the JSON FFI surface, wire it into Vite as `@moonbit/crdt-json`, and switch `json.html` to use it. The original `ffi/ffi.js` stays intact — `json.html` is the only consumer that migrates. This PR exists to validate the per-package build assumption and the nested-directory layout before touching markdown or lambda.

**Design sections exercised:** file structure, build output paths, Vite wiring.

**Invariant this phase must preserve:** `index.html` and `markdown.html` continue to load the original `@moonbit/crdt` (monolithic) with zero behavior change. Playwright JSON tests pass.

### Task 1.1: Create `ffi/json/moon.pkg`

**Files:**
- Create: `ffi/json/moon.pkg`

**Intent:** declare a new MoonBit package at path `dowdiness/canopy/ffi/json` with link-target `js` and the exact JSON FFI export list (from today's `ffi/moon.pkg`: `create_json_editor`, `destroy_json_editor`, `json_get_text`, `json_set_text`, `json_get_errors`, `json_get_proj_node_json`, `json_get_source_map_json`, `json_apply_edit`, `json_get_view_tree_json`, `json_compute_view_patches_json`). Imports are the minimal set identified in §2: `editor`, `core`, `lang/json/edits`, `lang/json/companion`, `dowdiness/json`, `seam`, `incr/cells`, `moonbitlang/core/json`, `moonbitlang/core/string`.

- [ ] **Step 1:** Write `ffi/json/moon.pkg` with imports + `link.js.exports`.
- [ ] **Step 2:** `moon check` — expected errors: no source files yet. Package skeleton is acceptable.

### Task 1.2: Move JSON source

**Files:**
- Create: `ffi/json/lifecycle.mbt`, `ffi/json/diagnostics.mbt`, `ffi/json/edit.mbt`, `ffi/json/view.mbt`

**Intent:** port the contents of today's `ffi/canopy_json.mbt` into the four new files, grouped by concern. Port the JSON halves of `ffi/canopy_view.mbt` (the `json_get_view_tree_json` + `json_compute_view_patches_json` functions and the `json_view_states` map) into `ffi/json/view.mbt`. Move `json_editors : Map[Int, ...]` into `ffi/json/lifecycle.mbt` as a package-level `let`.

Do not modify function bodies. The only change is the module they live in. The 10000-handle-offset convention documented in the comment header can move to `ffi/json/lifecycle.mbt` verbatim; keep it.

- [ ] **Step 1:** Create the four files, copy relevant content from `ffi/canopy_json.mbt` and the JSON path from `ffi/canopy_view.mbt`. Keep `///|` block separators.
- [ ] **Step 2:** `moon check` from canopy root. Expected: green for the new package.
- [ ] **Step 3:** `moon info` to regenerate `ffi/json/pkg.generated.mbti`. Review the output — the JSON exports should match the `link.js.exports` list.

### Task 1.3: Register `@moonbit/crdt-json` in Vite

**Files:**
- Modify: `examples/web/vite.config.ts`

**Intent:** add a third entry to `moonbitPlugin({ modules: [...] })` pointing `@moonbit/crdt-json` at `_build/js/release/build/ffi/json/json.js`. Add `'@moonbit/crdt-json'` to the `optimizeDeps.exclude` array.

- [ ] **Step 1:** Edit `vite.config.ts` per the sketch.
- [ ] **Step 2:** `cd examples/web && npm run build`. Expected: build succeeds. A new `dist/assets/json-*.js` chunk is produced that references the new MoonBit output. The original `crdt-*.js` chunk may or may not still appear (depends on whether any other entry still imports `@moonbit/crdt` — at this point both `index.html` and `markdown.html` do, so yes).
- [ ] **Step 3:** Record the new `ffi/json/json.js` size on disk (`stat -c%s _build/js/release/build/ffi/json/json.js`) and the post-minification chunk size in `dist/`.

### Task 1.4: Switch `json.html` to the new module

**Files:**
- Modify: `examples/web/src/json-editor.ts`
- Possibly modify: `lib/editor-adapter/*.ts` if the JSON entry uses them

**Intent:** change `import * as crdt from '@moonbit/crdt'` to `import * as crdt from '@moonbit/crdt-json'` in `json-editor.ts`. If any shared adapter in `lib/editor-adapter/` is imported only by `json-editor.ts`, switch that import too; if it's shared across entries, see Task 1.5.

- [ ] **Step 1:** Update the import in `src/json-editor.ts`.
- [ ] **Step 2:** `cd examples/web && npm run build`. Expected: new json chunk links only the new JSON ffi.
- [ ] **Step 3:** Record the `json-*.js` chunk byte size. This is the Phase 1 measurement — target is well under 500 kB.

### Task 1.5: Parameterize shared adapters (if any)

**Files:** to be determined at Phase 0 Step 4. Likely candidates: `lib/editor-adapter/html-adapter.ts`.

**Intent:** if a shared adapter imports `@moonbit/crdt` at module scope and is used by multiple entries, refactor it to take the `crdt` namespace as a function/class parameter. Each entry constructs the adapter with its own `crdt` module.

- [ ] **Step 1:** For each shared adapter hit from Phase 0 Step 4, decide: "used only by JSON" → switch the import directly; "used by multiple entries" → parameterize.
- [ ] **Step 2:** Update callers.
- [ ] **Step 3:** `npm run build` + `npx playwright test --grep json` (or equivalent) to confirm no regression.

### Task 1.6: End-to-end verification

**Files:** none — verification.

- [ ] **Step 1:** `npm run dev` and manually open `json.html`. Check: editor loads, text edits work, diagnostics show, view patches render. If broken, go back to Task 1.2 and double-check the file-split preserved all refs.
- [ ] **Step 2:** `npx playwright test` (or the project's JSON-editor subset) from `examples/web/`. Expected: all JSON tests pass.
- [ ] **Step 3:** Confirm `index.html` and `markdown.html` still work (they still use the monolithic `@moonbit/crdt` — zero change expected).
- [ ] **Step 4:** Record final bundle sizes: new `json-*.js` chunk, old `crdt-*.js` chunk (still monolithic at this point, minus zero bytes because json.html no longer imports it but the other two entries still do).

### Task 1.7: PR 1 commit + review

- [ ] **Step 1:** `moon fmt && moon info`. Confirm `git diff *.mbti` is clean.
- [ ] **Step 2:** Write PR 1 description citing the subtractive measurement table as motivation and recording the observed `json.html` chunk size.
- [ ] **Step 3:** Request review. Merge only with CI green (per `CLAUDE.md` CI merge policy).

**Phase 1 exit criteria:**
- `ffi/json/` package exists and links independently.
- `json.html` loads `@moonbit/crdt-json` and passes Playwright.
- `index.html` and `markdown.html` continue to load `@moonbit/crdt` (unchanged).
- New JSON chunk is measurably smaller than the shared `crdt-*.js`.

---

## Phase 2 — PR 2: `ffi/markdown/` package

**Goal:** same shape as Phase 1 but for markdown. The `markdown.html` entry migrates. The monolithic `ffi/ffi.js` still exists (for `index.html` + `memo.html`), now stripped of JSON but still containing lambda + markdown + LLM + sync.

Wait — after PR 1, what's in `ffi/ffi.js`? The monolithic build still *compiles* markdown + JSON into it, because `ffi/moon.pkg` still imports everything. That's fine: `index.html` and `memo.html` still load the monolith, `json.html` loads the new chunk. No functional regression, just temporary build duplication of JSON code.

**Invariant:** `index.html`, `memo.html`, `json.html` behavior unchanged.

### Task 2.1: Create `ffi/markdown/moon.pkg`

**Files:**
- Create: `ffi/markdown/moon.pkg`

**Intent:** declare `dowdiness/canopy/ffi/markdown`. Imports from §2: `editor`, `core`, `lang/markdown/edits`, `lang/markdown/companion`, `dowdiness/markdown`, `seam`, `incr/cells`, `moonbitlang/core/json`, `moonbitlang/core/string`. Exports: `create_markdown_editor`, `destroy_markdown_editor`, `markdown_get_text`, `markdown_export_text`, `markdown_set_text`, `markdown_compute_view_patches_json`, `markdown_apply_edit`.

- [ ] **Step 1:** Write `ffi/markdown/moon.pkg`.

### Task 2.2: Move markdown source

**Files:**
- Create: `ffi/markdown/lifecycle.mbt`, `ffi/markdown/edit.mbt`, `ffi/markdown/view.mbt`

**Intent:** port `ffi/canopy_markdown.mbt` split by concern. Markdown does not appear in `ffi/canopy_view.mbt` today (confirmed by Phase 0 Step 5), so no cross-file porting required. Move `markdown_editors : Map[Int, ...]` into `ffi/markdown/lifecycle.mbt`.

- [ ] **Step 1:** Create files, copy content, keep `///|` separators.
- [ ] **Step 2:** `moon check`. Expected: green for the new package.

### Task 2.3–2.6: Vite + switchover + verification

Mirror Tasks 1.3 through 1.7 for markdown:

- [ ] **Step 1:** Register `@moonbit/crdt-markdown` in Vite.
- [ ] **Step 2:** Switch `examples/web/src/markdown-editor.ts` to the new module.
- [ ] **Step 3:** Update any shared adapters used by markdown (same logic as Task 1.5).
- [ ] **Step 4:** `npm run dev` + open `markdown.html` manually, then run Playwright markdown tests.
- [ ] **Step 5:** Record bundle sizes. Target: well under 500 kB.
- [ ] **Step 6:** `moon fmt && moon info`, diff check, PR.

**Phase 2 exit criteria:**
- `ffi/markdown/` package exists.
- `markdown.html` loads `@moonbit/crdt-markdown`.
- `json.html` (now uses `@moonbit/crdt-json`) and `index.html`/`memo.html` (still monolithic) continue to work.
- Markdown chunk measurably under 500 kB.

---

## Phase 3 — PR 3: `ffi/lambda/` migration and decommission of root `ffi/`

**Goal:** migrate the remaining lambda FFI surface (the biggest single chunk of today's `ffi/`), switch `index.html` + `memo.html` to it, then delete the now-empty root `ffi/` package.

**Scope:** this is the largest and riskiest of the three because:
- `canopy_lambda.mbt` is 553 lines — the biggest single file.
- Ephemeral, sync (WS + relay), view (lambda path), pretty, and intent all depend on `lambda_handles`.
- Tests in `ffi/*_wbtest.mbt` and `ffi/integration_ws_test.mbt` assume the old package path.

**Invariant:** all existing FFI functions behave identically. No semantic changes.

**Expected outcome:** `index.html` chunk lands at ~515 kB (per the subtractive measurement). Still 15 kB over the 500 kB budget. Addressing that overage is a follow-up (§7) — not this PR.

### Task 3.1: Create `ffi/lambda/moon.pkg`

**Files:**
- Create: `ffi/lambda/moon.pkg`

**Intent:** declare `dowdiness/canopy/ffi/lambda`. Imports are the superset needed by lambda + ephemeral + sync + ws + relay + view + pretty + intent + llm + undo: basically today's `ffi/moon.pkg` minus the `json` and `markdown` branches. Exports are every FFI name *not* already migrated to json/markdown — lambda, ephemeral, sync, ws, relay, undo, view (lambda half), pretty, intent, llm.

- [ ] **Step 1:** Write `ffi/lambda/moon.pkg`. Cross-check the exports list against the current `ffi/moon.pkg`: after removing the 10 JSON exports (migrated in PR 1) and the 7 markdown exports (migrated in PR 2), the remaining exports belong here.

### Task 3.2: Move lambda source

**Files (create):**
- `ffi/lambda/lifecycle.mbt` — create/destroy/get_text/set_text/create_editor_with_undo
- `ffi/lambda/diagnostics.mbt` — get_errors_json, get_diagnostics_json, get_ast_dot_resolved, get_ast_pretty, export_all_json, export_since_json, apply_sync_json, get_version_json, get_proj_node_json, get_source_map_json
- `ffi/lambda/undo.mbt` — insert_and_record, delete_and_record, backspace_and_record, set_text_and_record, undo_manager_*, undo_and_export_json, redo_and_export_json
- `ffi/lambda/intent.mbt` — handle_text_intent, handle_undo, handle_redo, handle_structural_intent, apply_tree_edit_json, insert_at, delete_at
- `ffi/lambda/ephemeral.mbt` — (entire `canopy_ephemeral.mbt` contents)
- `ffi/lambda/sync.mbt` — sync-specific helpers from `canopy_sync.mbt` if distinct from WS/relay
- `ffi/lambda/ws.mbt` — ws_on_open, ws_on_message, ws_on_close, ws_broadcast_edit, ws_broadcast_cursor
- `ffi/lambda/relay.mbt` — relay_on_connect, relay_on_message, relay_on_disconnect
- `ffi/lambda/view.mbt` — `get_view_tree_json`, `compute_view_patches_json`, `view_states` map (lambda half of `canopy_view.mbt`)
- `ffi/lambda/pretty.mbt` — entire `canopy_pretty.mbt` contents
- `ffi/lambda/llm.mbt` — entire `canopy_llm.mbt` contents
- `ffi/lambda/destroy_editor_wbtest.mbt`, `integration_ws_test.mbt`, `relay_room_leak_wbtest.mbt` — move tests verbatim

**Intent:** port file-by-file. `lambda_handles` stays a `let` in `ffi/lambda/lifecycle.mbt` where `create_editor` defines it. Every other file references it by name within the same package — no imports needed.

- [ ] **Step 1:** Create each file, moving content from the corresponding `ffi/canopy_*.mbt`.
- [ ] **Step 2:** After every 2-3 files, `moon check`. Fix errors before continuing (incremental edit rule from `CLAUDE.md`).
- [ ] **Step 3:** Pay special attention to `ffi/canopy_view.mbt`: the JSON half was already migrated in PR 1 (or will be via the common stub); the lambda half moves here. The `view_states : Map[Int, ...]` binding stays; the `json_view_states` binding is now in `ffi/json/view.mbt`.
- [ ] **Step 4:** Test files: update any `@ffi.` or `dowdiness/canopy/ffi` references inside them to `@lambda.` or `dowdiness/canopy/ffi/lambda`. Run `moon test ffi/lambda/`.

### Task 3.3: Decommission root `ffi/`

**Files:**
- Delete: `ffi/moon.pkg`, `ffi/canopy_*.mbt`, `ffi/pkg.generated.mbti`, `ffi/destroy_editor_wbtest.mbt` (moved to lambda/), `ffi/integration_ws_test.mbt` (moved), `ffi/relay_room_leak_wbtest.mbt` (moved)

**Intent:** after PR 3, the root `ffi/` directory contains only the three subdirectories (and possibly `common/`). No `moon.pkg`, no `.mbt` files at the root.

- [ ] **Step 1:** After Task 3.2 builds green, delete the root `ffi/*.mbt` and `ffi/moon.pkg`.
- [ ] **Step 2:** `moon check && moon test` from canopy root. Expected: green across the whole workspace.
- [ ] **Step 3:** `moon ide outline ffi/lambda` + `ffi/json` + `ffi/markdown`. Confirm the three public surfaces sum to the original `ffi/` public surface (no FFI function lost).

### Task 3.4: Vite + switchover

**Files:**
- Modify: `examples/web/vite.config.ts` — register `@moonbit/crdt-lambda`, remove the old `@moonbit/crdt` entry
- Modify: `examples/web/src/editor.ts`, `examples/web/src/memo-editor.ts`
- Modify: any remaining `lib/editor-adapter/*.ts` that still imports `@moonbit/crdt`

**Intent:** after this task, the virtual module name `@moonbit/crdt` no longer exists. Nothing imports it.

- [ ] **Step 1:** Swap the Vite entry.
- [ ] **Step 2:** Update `editor.ts`, `memo-editor.ts`, and any remaining shared adapters.
- [ ] **Step 3:** `npm run build`. Expected: three crdt-shaped chunks (`crdt-lambda-*.js`, `crdt-json-*.js`, `crdt-markdown-*.js`), no monolithic `crdt-*.js`.
- [ ] **Step 4:** `grep -rn "@moonbit/crdt[^-]" examples/web/ lib/editor-adapter/` — should return zero hits.

### Task 3.5: External-reference sweep

**Files:** determined at Phase 0 Step 3. Candidates:
- `examples/web/scripts/build-deploy.sh`
- `examples/demo-react/` configs + path aliases
- `release/` packaging scripts
- `CI_CD_SETUP.md`
- `post-merge-docs.sh`

- [ ] **Step 1:** For each hit, update the path to point at one of the three new outputs (the lambda one is the closest semantic replacement for the old `ffi.js` in most contexts).
- [ ] **Step 2:** Run the deploy/release script in dry-run mode if one exists.

### Task 3.6: End-to-end verification

- [ ] **Step 1:** `npm run dev`, manually test all four pages: `index.html`, `json.html`, `markdown.html`, `memo.html`. Cross-page navigation, CRDT peer sync between two open tabs, markdown DnD, JSON structural intent.
- [ ] **Step 2:** `npx playwright test` — full suite.
- [ ] **Step 3:** `npm run build` and record bundle sizes: all three `crdt-*` chunks.
- [ ] **Step 4:** Update `docs/TODO.md §1` with the measured sizes and the note about the remaining 515 kB lambda floor.

### Task 3.7: PR 3 commit + review

- [ ] **Step 1:** `moon fmt && moon info`. Confirm `git diff *.mbti` — the three new `pkg.generated.mbti` files should each match the `link.js.exports` of their `moon.pkg`.
- [ ] **Step 2:** Write PR description summarizing: what moved where, final bundle sizes, remaining gap on `index.html`.
- [ ] **Step 3:** Merge with CI green.

**Phase 3 exit criteria:**
- Root `ffi/` is a directory-only namespace. All FFI code lives under `ffi/{lambda,json,markdown}`.
- Four HTML pages use the three new virtual modules. `@moonbit/crdt` is gone.
- All Playwright tests pass.
- `index.html` bundle size measured. Expected ~515 kB per the subtractive data. Document the overage.

---

## §7 — What this plan does *not* solve

The subtractive measurement already told us the lambda-only floor is 515 kB. Splitting gets `json.html` and `markdown.html` under budget but leaves `index.html` and `memo.html` 15 kB over. Candidates for a follow-up PR (not this plan):

1. **Dynamic import of LLM** (−19 kB measured). `canopy_llm_fix_typos` / `canopy_llm_edit` are called lazily from the TS side only when the user invokes the LLM action. Move to a code-split chunk via `const { ... } = await import('@moonbit/crdt-lambda-llm')`. Cheapest single-win path.
2. **Lazy egglog Tier-2 evaluator.** Symbol-prefix tally in the measurement pass showed substantial `dowdiness/egglog/examples/lambda_-eval/*` footprint. If egglog tier 2 is only needed when escalated from tier 1, move the escalation path behind a dynamic import. Non-trivial — touches `editor/` or `lang/lambda/companion`.
3. **Lambda typecheck lazy.** Diagnostics are polled on demand. Check whether `typecheck` is reachable only from polled diagnostic paths; if so, lazy-load.
4. **Revisit the budget.** 500 kB was chosen without data. After splitting, the per-page reality is known — propose a revised per-page budget in `docs/TODO.md §1`.

Track these as separate TODO items after PR 3 lands, informed by the real numbers.

---

## §8 — Risks & open questions

1. **`moon build` runs 3× redundantly.** All three `ffi_*` packages live in the same MoonBit workspace (same `path: '../..'` in Vite config). `vite-plugin-moonbit`'s `buildAllModules` runs `moon build` once per listed module. Dedupe by unique `absolutePath` in a ~5-line plugin change; defer to a follow-up if build time is acceptable.
2. **Shared-adapter TypeScript refactor scope is unknown until Phase 0 Step 4.** If the refactor is large, split PR 1 into two: ffi-json MoonBit side first, adapter parameterization second.
3. **`ffi/canopy_test.mbt` unscoped.** Phase 0 check: read it and decide whether it's a lambda test or a cross-cutting test that belongs in a `ffi/common/` if we create one.
4. **`ffi/canopy_view.mbt` is the only true cross-language file.** PR 1 migrates the JSON half via a stub (see sketch); PR 3 migrates the lambda half. Between PR 1 and PR 3, the monolithic `ffi/` keeps building (it still has both halves) — no intermediate-state breakage.
5. **`memo.html` uses lambda.** Confirmed by grep in Phase 0 Step 4. `memo-editor.ts` switches to `@moonbit/crdt-lambda` in PR 3 alongside `editor.ts`.
6. **Bundle duplication during PRs 1–2.** Between PR 1 merge and PR 3 merge, JSON code is linked into *both* `ffi/ffi.js` (for index.html) and `ffi/json/json.js` (for json.html). Wasteful but temporary. Accept; PR 3 removes the duplication.
7. **Per-entry MoonBit link verification.** The working assumption is that declaring `link.js.exports` in each `ffi/{lambda,json,markdown}/moon.pkg` produces three independent linked outputs. Precedent: `cmd/main/moon.pkg` + `ffi/moon.pkg` already produce separate outputs (`_build/js/release/build/cmd/main/main.js`, `_build/js/release/build/ffi/ffi.js`). Task 1.1 + 1.2 validate this empirically before any downstream commitment.

---

## §9 — Effort estimate

| PR | Focus | Est. time |
|---|---|---|
| PR 1 | `ffi/json/` + Vite wiring + E2E | ~1 afternoon |
| PR 2 | `ffi/markdown/` + E2E | ~half day |
| PR 3 | `ffi/lambda/` + decommission root `ffi/` + sweep | ~1 day |
| Total | | **~3 days focused** |

Sequential merges. Each PR is independently revertible. The plan's structural risk is concentrated in PR 1 (validating per-package MoonBit linking against the nested-directory layout); PRs 2 and 3 are largely mechanical once PR 1 lands.
