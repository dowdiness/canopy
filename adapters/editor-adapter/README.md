# @canopy/editor-adapter

Bridges Canopy's `ViewPatch` protocol to a concrete editor surface — CodeMirror 6, ProseMirror, or plain HTML. Consumers feed it patches from any source (Canopy's own engine, or their own) and receive `UserIntent` events back.

This package is the **editor boundary**: rendering and input only. It does not parse, lex, evaluate, type-check, or merge documents. Those concerns live elsewhere in the Canopy stack and are reachable through the patch stream — never imported directly.

## Status

Pre-1.0. The wire-format types (`ViewPatch`, `UserIntent`, `Decoration`, `Diagnostic`) are stable enough to integrate against; concrete adapter classes (`CM6Adapter`, `PMAdapter`, `HTMLAdapter`) are still settling. See [Versioning](#versioning).

## Install

```bash
npm install @canopy/editor-adapter
```

Peer dependencies are optional — install only what you use:

| Adapter        | Required peers                                                                 |
|----------------|--------------------------------------------------------------------------------|
| `HTMLAdapter`  | none                                                                           |
| `CM6Adapter`   | `@codemirror/state`, `@codemirror/view`, `@codemirror/language`, `@codemirror/commands` |
| `PMAdapter`    | `prosemirror-state`, `prosemirror-view`, `prosemirror-model`, `prosemirror-transform`, `prosemirror-keymap`, `prosemirror-commands` |

## Quick start

```ts
import { CM6Adapter, type ViewPatch, type UserIntent } from '@canopy/editor-adapter';

const adapter = new CM6Adapter(parentEl);

adapter.onIntent((intent: UserIntent) => {
  // Forward to your engine: parser, evaluator, audio runtime, etc.
  engine.handleIntent(intent);
});

// Push patches produced by your engine back into the editor.
const patches: ViewPatch[] = engine.tick();
adapter.applyPatches(patches);

// On teardown:
adapter.destroy();
```

The protocol is symmetric: patches flow engine → adapter, intents flow adapter → engine. The adapter is a passive renderer; it owns no document state of its own beyond what's needed to display the latest patches.

## Scope

### In scope

- Render `ViewPatch[]` streams onto CM6, ProseMirror, or HTML.
- Emit `UserIntent` events for keyboard, mouse, and text input.
- Apply `Decoration[]` (errors, peer cursors, custom highlights) and `Diagnostic[]` (squigglies, hover messages).
- Lifecycle: `applyPatches`, `onIntent`, `destroy`.
- Stable JSON wire format compatible with non-Canopy engines.

### Out of scope

- **Parsing, lexing, incremental reparsing** — that is `@canopy/loom`.
- **CRDT, multi-user merging, history** — that is `@canopy/eg-walker`.
- **Language semantics, scope, types, evaluation** — that is `@canopy/lang`.
- **Non-text editor surfaces** (canvas, block tree, custom DOM) — separate adapters in their own packages.

Anything imported from `@canopy/loom`, `@canopy/lang`, or `@canopy/eg-walker` inside this package is a layering violation. The package builds and runs without any of them.

## Public API

| Export                            | Stability  | Notes                                              |
|-----------------------------------|------------|----------------------------------------------------|
| `ViewPatch`, `UserIntent`         | stable     | Wire-format unions; breaking changes need a major. |
| `Decoration`, `Diagnostic`        | stable     | Decoration shapes consumers extend via `css_class`. |
| `ViewNode`                        | stable     | Tree shape for structural patches.                 |
| `EditorAdapter`                   | stable     | The interface every adapter implements.            |
| `CM6Adapter`                      | unstable   | CodeMirror 6 adapter; constructor surface may change. |
| `PMAdapter`, `pmAdapterSchema`    | unstable   | ProseMirror adapter and node schema.               |
| `HTMLAdapter`                     | unstable   | DOM-only adapter, primarily for tests and previews.|
| `MarkdownPreview`                 | unstable   | Helper view for markdown rendering.                |
| `BlockInput`                      | internal   | Used by Canopy demos; not for external consumption.|

External consumers should program against `stable` exports. `unstable` exports may break in minor versions until they graduate.

## Wire-format invariants

The patch protocol is intentionally minimal. Three rules every engine must respect:

1. **JSON-serializable.** Every `ViewPatch` and `UserIntent` round-trips through `JSON.stringify` / `JSON.parse` without loss.
2. **Idempotent re-application.** Applying the same patch sequence twice from the same starting state yields the same result. Adapters may dedupe but engines must not rely on it.
3. **Synchronous intents.** `UserIntent` events fire synchronously from input. Consumers may respond async, but ordering across an input gesture is preserved.

The MoonBit-side custom `ToJson` impls in `framework/protocol/` are the source of truth for the wire format. TypeScript types in `types.ts` mirror them.

## Extension points

**Bring your own engine.** Implement `EditorAdapter` directly, or use a built-in adapter and feed it `ViewPatch[]` from any source — a parser, an evaluator, a remote server, a wasm audio engine. The adapter does not know or care where patches come from.

**Diagnostics.** Send `{ type: "SetDiagnostics", diagnostics: [...] }`. Severity is `"error" | "warning" | "info" | "hint"`; the adapter renders them as inline marks plus a hover panel. Parse errors, type errors, runtime errors all use the same path.

**Custom decorations.** Send `{ type: "SetDecorations", decorations: [...] }` with a `css_class` namespaced to your project (e.g. `moondsp-pattern-cursor`). Style it in your host CSS. Use the `widget` flag for inline DOM widgets.

**Selection and cursor.** `SetSelection` and `SelectNode` patches drive editor focus. `SetCursor` and `SelectNode` intents come back from the user.

## Versioning

- **Pre-1.0:** minor bumps may break `unstable` exports; `stable` exports follow semver.
- Breaking changes to `stable` exports require a major bump and a `CHANGELOG.md` entry.
- Two consumers (Canopy's own demos and at least one external integration) must build on CI before any `stable` change is released.

See [`CHANGELOG.md`](./CHANGELOG.md) for release history.

## Layering self-check

Before publishing, the package's own boundary is verified by:

```bash
grep -r "@canopy/loom\|@canopy/lang\|@canopy/eg-walker" .
```

Any hit is a layering violation and blocks release.

## License

See repository [LICENSE](../../LICENSE).
