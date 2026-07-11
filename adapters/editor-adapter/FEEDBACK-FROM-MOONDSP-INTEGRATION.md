# Feedback from moondsp integration

Findings from integrating `@canopy/editor-adapter@0.1.0-alpha.0` into
`dowdiness/moondsp` (live-coding REPL, phase A). The integration shipped
green — these notes are the punch list for `0.1.0-alpha.1` based on
real friction, not speculation.

**Source of truth:** `dowdiness/moondsp` commit `e8bdbee`, vendor copy
at `web/live/src/canopy/`. Diff against this package's `9df029d`
captures the workarounds applied.

## Headline: the contract held

The `EditorProtocol` shape is right. Bringing up CM6 with the adapter
on a non-Canopy engine (a wasm AudioWorklet) was straightforward, and
the patch/intent split mapped cleanly onto a debounced-eval live-coding
loop. No type changes were needed. **`stable` exports earn the label.**

The items below are gaps in the concrete adapter, not in the protocol.

## P1 — `SetDiagnostics` is a no-op in `CM6Adapter` (resolved)

**Resolved:** implemented in canopy after this doc landed. `SetDiagnostics`
patches now dispatch a `StateEffect` into a `diagnosticField` /
`diagnosticPlugin` pair (mirrors the existing decoration code), rendering
each diagnostic as a CM6 `Decoration.mark` with class
`cm-diagnostic cm-diagnostic-${severity}` and a native-tooltip
`title`/`data-severity` attribute pair. No new dependency on
`@codemirror/lint`. The `static extensions()` return now includes the
new field + plugin so consumers get squigglies automatically.

**Original report below for context.**



**File:** `cm6-adapter.ts`, `applyPatch`

```ts
case "SelectNode":
case "SetDiagnostics":
  break;
```

`SetDiagnostics` is dropped on the floor. moondsp routes parse errors
into a footer panel as a workaround; inline squigglies, hover messages,
and gutter markers — the whole reason a `Diagnostic` type exists — are
unreachable from any external consumer.

**Suggested fix:** mirror the `setDecorations` pattern. Add a
`StateField<Diagnostic[]>` plus a `ViewPlugin` that builds CM6
`Decoration.mark` ranges with severity-namespaced classes
(`cm-diagnostic-error`, `…-warning`, `…-info`, `…-hint`) and an
`@codemirror/lint`-compatible source so existing CM6 lint UI lights up.

**Cost to implement:** ~80 lines, mirrors the existing decoration code.
**Cost of *not* implementing:** every consumer reinvents an error panel
or a sibling decoration channel and the protocol's `Diagnostic` type
becomes vestigial.

## P2 — `verbatimModuleSyntax` breaks the build downstream

**File:** `cm6-adapter.ts` lines 3–10

```ts
import {
  EditorView,
  Decoration as CmDecoration,
  DecorationSet,    // type-only — value import errors with verbatimModuleSyntax
  ViewPlugin,
  ViewUpdate,       // type-only — same
  WidgetType,
} from "@codemirror/view";
```

`DecorationSet` and `ViewUpdate` are used only in type positions. Under
`tsconfig`'s `verbatimModuleSyntax: true` (a recommended modern default,
shipped by Vite/SvelteKit/etc.) this fails:

> Type-only import of an external module is not allowed when …

**Suggested fix:** split to `import type { DecorationSet, ViewUpdate }`.
moondsp applied this in the vendor copy.

## P3 — `noImplicitOverride` requires `override` on `WidgetType` subclass

**File:** `cm6-adapter.ts`, `class PeerCursorWidget extends WidgetType`

`eq`, `toDOM`, `ignoreEvent` override base methods but lack the
`override` modifier. Under `noImplicitOverride: true` (also a common
modern default) tsc fails:

> This member must have an 'override' modifier because it overrides …

**Suggested fix:** add `override` to all three. moondsp applied this in
the vendor copy.

## P4 — `private: true` blocks vendoring → install path until publish (resolved)

**Resolved:** the publish-prep commit (`eb4e10b`, on `main` since alpha.0)
already dropped `private: true`, bumped to `0.1.0-alpha.0`, and added the
license / repository / homepage / bugs / keywords / files allowlist. The
`0.1.0-alpha.x` tag carries the pre-stable signal. `file:../canopy/adapters/editor-adapter`
deps now work for sibling-checkout consumers; `npm publish` remains the
follow-on step if/when the package goes registry-public.

**Original report below for context.**



**File:** `package.json`

The package is currently `private: true`. Even consumers willing to
take a `file:../canopy/adapters/editor-adapter` dep run into npm
refusing to install a private package without `workspaces` or
`installPrivate` flags. moondsp went the vendor-copy route partly to
sidestep this. Either:

- **Publish to npm** (the path the README assumes), or
- **Drop `private: true`** and rely on the `0.1.0-alpha.x` tag to
  signal pre-stable. Local-path deps then work for sibling-checkout
  monorepo setups.

Without one of these, "two consumers on CI" can't actually be wired up.

## Notes that aren't items

- **Wire format**: `ViewPatch` and `UserIntent` were used unmodified.
  No round-trip surprises.
- **`createUpdateListener` ergonomics**: the "construct adapter, then
  inject the listener via Compartment" dance worked but is a touch
  awkward — a future API could let `CM6Adapter` own its compartment
  and provide a `mount(parent, initialDoc, extras): EditorView`
  helper. Not a blocker; flagged for the future shape.
- **Decoration `data: "name|color"` pipe-encoding**: works but feels
  like a string-typed escape hatch on `Decoration`. If more widget
  metadata accrues, consider a typed widget-data union.

## Concrete asks for `0.1.0-alpha.1`

- [x] P1 — implement `SetDiagnostics` in `CM6Adapter`
- [x] P2 — `import type` fix for `DecorationSet` + `ViewUpdate`
- [x] P3 — `override` modifier on `PeerCursorWidget` methods
- [x] P4 — `private: true` dropped (publish-prep commit `eb4e10b`)

All four punch-list items are resolved on `main`. moondsp's vendor copy
can be dropped in favor of a `file:` dep (or, once the package is
registry-published, an `npm` dep).
