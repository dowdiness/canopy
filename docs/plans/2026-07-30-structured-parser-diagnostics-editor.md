# Structured Parser Diagnostics in the CodeMirror Editor

Status: ready

Canonical issue: [#1034](https://github.com/dowdiness/canopy/issues/1034)

## Why

Canopy already receives structured parser diagnostics from Loom, but the editor path converts them to strings and emits every finding at `0..0`. The current custom CodeMirror renderer then removes every zero-width finding. Users therefore lose the real range, severity, code, and missing-token marker even though Loom preserves them.

This plan deepens the existing `ViewPatch::SetDiagnostics` path. It does not create another diagnostic model or renderer.

## Scope

In:

- `editor/view_updater.mbt`
- `editor/view_updater_test.mbt`
- `protocol/view_patch.mbt`
- `protocol/view_patch_test.mbt`
- `protocol/README.md`
- `adapters/editor-adapter/cm6-adapter.ts`
- `adapters/editor-adapter/types.ts`
- `adapters/editor-adapter/package.json`
- `adapters/editor-adapter/package-lock.json` (new)
- `adapters/editor-adapter/tsconfig.cm6-test.json` (new)
- `adapters/editor-adapter/test/cm6-diagnostics.html` (new)
- `adapters/editor-adapter/test/cm6-diagnostics.ts` (new)
- `adapters/editor-adapter/README.md`
- `adapters/editor-adapter/CHANGELOG.md`

Out:

- diagnostic fixes or CodeMirror actions (#1037, #1038)
- source IDs, labels, multiple files, or a new generic model (#1035)
- plain-text rendering (#1036)
- semantic diagnostics (#1039)
- changes to ProseMirror or web-example manifests: neither directly imports `CM6Adapter`
- ANSI, JSON interchange, LSP, SARIF, or HTML renderers

## Current State

- `editor/sync_editor_parser.mbt:107-112` exposes `get_errors()`, suppresses diagnostics for an empty document, and formats `parser.diagnostics()` into strings.
- `editor/view_updater.mbt:90-107` consumes those strings and emits each as severity `error` at `0..0`.
- `editor/view_updater_test.mbt:173-210` proves only that malformed input emits a nonempty set and later valid input clears it. It does not inspect range, severity, code, or empty-document findings.
- `loom/loom/core/diagnostics.mbt:466-490` already defines `Diagnostic` with structured severity, optional code, optional primary `TextRange`, labels, notes, and token evidence. `DiagnosticSet::items()` returns a defensive copy at lines 628-645.
- `protocol/view_patch.mbt:31-70` defines all four severities and a half-open UTF-16 `Diagnostic`, but the wire type has no code field.
- `adapters/editor-adapter/types.ts:25-30` mirrors the four existing wire fields.
- `adapters/editor-adapter/cm6-adapter.ts:150-219` owns a second diagnostic `StateField` and decoration plugin. Its `from < to` filter drops point diagnostics.
- Repository-wide import search found no executable consumer that imports or constructs `CM6Adapter`. The only construction is the adapter README example. `examples/prosemirror` imports `PMAdapter`; web examples import other adapter subpaths.

## Prototype Evidence

A temporary browser prototype replaced the custom diagnostic field/plugin with `@codemirror/lint` `setDiagnostics` while retaining the current wire shape. On 2026-07-30:

- `{from: 3, to: 4, severity: "warning"}` rendered as `.cm-lintRange-warning`;
- `{from: 11, to: 11, severity: "error"}` at EOF rendered as `.cm-lintPoint-error`;
- both markers were visible simultaneously.

The prototype initially used the ProseMirror example only as a convenient Vite host. Those manifest/Vite edits are not part of the implementation because it is not a `CM6Adapter` consumer. Browser coverage belongs to a dedicated adapter-owned harness.

## Desired State

`SyncEditor::parser_diagnostics()` is the editor display source. `compute_view_patches` projects each Loom diagnostic to the existing protocol with its primary UTF-16 range, severity, message, and optional code. A locationless finding alone falls back to `0..0`; an empty source does not suppress structured parser diagnostics. CodeMirror lint renders ranges and points, and the superseded custom renderer is deleted.

The protocol remains producer-neutral. It does not expose Loom tokens, CST nodes, entities, notes, labels, or parser-specific types.

## Reuse Check

Reuse:

- Loom `DiagnosticSet`, `Diagnostic`, `DiagnosticSeverity`, `DiagnosticCode::value`, `TextRange::start/end`, and `TextOffset::value`.
- `SyncEditor::parser_diagnostics()` rather than another parser accessor.
- Existing protocol `Severity`, `Diagnostic`, and `ViewPatch::SetDiagnostics`.
- `@codemirror/lint` `Diagnostic` and `setDiagnostics`, including supported `from == to` points.

Checked but not used:

- `get_errors()` remains suitable for legacy human-readable callers, not editor projection.
- Loom labels, notes, and token evidence require #1035.
- The custom CodeMirror diagnostic field duplicates lint behavior and must be removed, not retained.

No new MoonBit core helper or type is required.

## Steps

1. Add `code : String?` to protocol `Diagnostic`, its constructor, and JSON encoding. The field is always present on the wire as `"code": null|string`, matching existing nullable protocol fields. Update protocol snapshots for both values, document the field, regenerate interfaces, and inspect `.mbti` drift.
2. Strengthen `editor/view_updater_test.mbt` before changing editor production code. Assert that `if x then y` emits a diagnostic at the UTF-16 EOF offset with its actual severity, message, and code when present. Preserve the clear-after-correction case and add a nonzero-range assertion. Assert structured diagnostics are not suppressed solely because the document is empty.
3. In `editor/view_updater.mbt`, replace `get_errors()` with `parser_diagnostics().read_or_abort().items()`. Convert Loom severity exhaustively. Convert `primary` through `TextRange::start/end` and `TextOffset::value`; use `0..0` only when absent. Pass message and code. Keep existing `had_errors` clearing behavior.
4. Mirror the protocol field exactly as `code: string | null` in TypeScript. In `cm6-adapter.ts`, delete the custom diagnostic effect, field, builder, and plugin. Map patches to CodeMirror lint diagnostics, clamp only at this defensive UI boundary, preserve point spans, expose non-null code through CodeMirror's `source`, and dispatch `setDiagnostics(this.view.state, diagnostics)`.
5. Add `@codemirror/lint` `^6.9.7` as an optional adapter peer. Add adapter-local dev dependencies needed by its CM6 test harness, scripts for typecheck/build, and a lockfile. Do not alter unrelated example manifests.
6. Add a minimal adapter-owned Vite page that constructs `CM6Adapter`, applies one nonzero warning and one EOF error, and records a deterministic pass/fail result after finding `.cm-lintRange-warning` and `.cm-lintPoint-error`. It must also clear diagnostics and prove both marker forms disappear. This harness is test-only, not a shipped adapter export.
7. Run final focused and workspace validation. Update issue #1034 to link this plan; the plan becomes the sole implementation spec.

## Acceptance Criteria

- [ ] Editor display reads structured `parser_diagnostics()`; it does not call `get_errors()`.
- [ ] Loom primary UTF-16 range, all four severities, message, and optional code survive conversion.
- [ ] Only a locationless diagnostic falls back to `0..0`.
- [ ] `if x then y` renders a visible EOF point marker.
- [ ] A nonzero diagnostic renders as a lint range.
- [ ] Correcting input emits `SetDiagnostics([])` and removes markers.
- [ ] The custom CM6 diagnostic field/plugin and `from < to` filter are gone.
- [ ] Protocol JSON always contains `code`, covered with both a string and `null`; TypeScript declares `code: string | null`.
- [ ] `@codemirror/lint` is an optional peer; no nonconsumer manifest is changed.
- [ ] The adapter-owned browser harness passes without Canopy parser, CST, or editor internals.
- [ ] No fix, source-ID, semantic, or standalone-renderer API enters this change.

## Validation

After every MoonBit file edit, run the matching package check before editing another file:

```bash
NEW_MOON_MOD=0 moon check editor
NEW_MOON_MOD=0 moon check protocol
```

Focused and final checks:

```bash
NEW_MOON_MOD=0 moon test -p dowdiness/canopy/editor
NEW_MOON_MOD=0 moon test -p dowdiness/canopy/protocol
moon check
moon test
moon build --target js --release
NEW_MOON_MOD=0 moon info
NEW_MOON_MOD=0 moon fmt
git diff -- '*.mbti'
```

Adapter checks, using the exact script names introduced in step 5:

```bash
cd adapters/editor-adapter
npm ci
npm run typecheck:cm6
npm run build:test:cm6
npm run dev:test:cm6
```

Drive the last command in a real browser. Require the harness pass signal, inspect `.cm-lintRange-warning` and `.cm-lintPoint-error`, verify clearing, and capture a screenshot.

## Risks

- Adding always-present `code` changes generated JSON for older producers. The clean cutover updates every in-repo producer and TypeScript consumer together; snapshots pin `"code": null|string`.
- Optional peers can typecheck but fail bundling if the host does not install them. The adapter-owned harness is the positive installation test; future real consumers must declare lint at their boundary.
- Defensive frontend clamping must not hide producer defects. MoonBit tests assert exact producer ranges before the adapter boundary.
- `get_errors()` suppresses empty-document errors. Moving display to `parser_diagnostics()` intentionally removes that display-only suppression; `is_parse_valid()` remains unchanged unless tests prove it belongs to #1034.
