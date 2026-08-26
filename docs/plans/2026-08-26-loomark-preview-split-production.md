# Loomark Preview and Split production implementation

**Issue:** [#1372](https://github.com/dowdiness/canopy/issues/1372)

**Status:** Implementation reached the practical-corpus performance stop
condition. See
[production performance evidence](../evidence/2026-08-26-loomark-preview-split-production-performance.md)
before continuing.

This plan extends the completed
[standard Rabbita Text app](2026-08-24-loomark-standard-rabbita-text-app.md).
That plan remains authoritative for Document text, browser storage, Autosave,
Recovery, and the native textarea edit boundary. This plan supersedes only its
statements that Loomark has no modes or Parser.

## Goal

Add three editor modes to the current standard Rabbita app:

- **Text** shows the existing textarea;
- **Preview** shows one read-only Preview while retaining the same hidden
  textarea element; and
- **Split** shows that textarea and the same Preview in RUI resizable panels.

Document text remains the only editing and saving authority. Preview is derived
state. A session that stays in Text mode creates no Parser or Markdown
attachment.

## Non-goals

- HTML strings or `innerHTML`
- a second Document representation or text authority
- Worker execution, async Parser, pending edit batches, or revision queues
- CodeMirror, Block Editor, widgets, or app-owned undo/redo
- scroll-position reading, writing, retention, reset, or synchronization
- an app-owned draggable divider or persisted panel ratio
- persisted editor mode or any change to `{document_id, text}` browser records
- artificial warm-up, idle preparation, or background retry
- changes to Loom, Rabbita, RUI, or other submodules
- production profiling hooks or test-only production state

## Product boundaries

| Event | Document text | Parser | Visible Preview | Autosave |
|---|---|---|---|---|
| Exact textarea edit | Updates immediately | One `apply_edit` command after the native handler returns | Keeps the last result; refresh is debounced by 50 ms | Existing behavior |
| `ReplaceAll` fallback | Updates immediately | One `set_source` command after the native handler returns | Same debounce | Existing behavior |
| IME intermediate update | Unchanged | No new work | Previously scheduled work may finish | Unchanged |
| IME end | Applies once | Advances once | Schedules one refresh | Existing behavior |
| First Preview or Split selection | Unchanged | Shows Preparing, then creates one pair after a paint opportunity | Shows Preparing, then first result | Unchanged |
| Return to Text during preparation | Unchanged | Preparation continues | Result is retained but hidden | Unchanged |
| Parser transition failure | Unchanged | Pair becomes unusable | Last result remains with a stale alert | Continues |
| Semantic or Html failure | Unchanged | Healthy pair remains | Last result remains with a stale alert | Continues |
| Allowed retry | Unchanged | Replaces only an unusable pair; otherwise reuses it | Publishes success or keeps the failure | Unchanged |

The 50 ms debounce applies only to reading the Markdown attachment, building
typed Html, and publishing a visible result. Parser source synchronization does
not wait for the debounce.

## Package and file map

Use one deep internal Preview package rather than separate renderer, timer, and
Parser packages.

```text
apps/loomark/
  CONTEXT.md                                  # already updated glossary
  moon.mod                                    # add Loom, Markdown, and RUI modules
  public/styles.css                           # restored visual system and responsive shell
  app/
    app.mbt                                   # construct shells and state machine
    model.mbt                                 # modes and Preview display state
    update.mbt                                # deterministic transitions and commands
    view.mbt                                  # mode bar, panels, Loading, Recovery, alerts
    moon.pkg                                  # Preview/RUI/DOM/subscription imports
    *_wbtest.mbt                              # pure transition tests where useful
  internal/preview/
    moon.pkg                                  # new package
    engine.mbt                                # Parser and attachment shell
    renderer.mbt                              # pure MarkdownIR -> typed Html
    preview_wbtest.mbt                        # engine and renderer behavior
    renderer_benchmark_wbtest.mbt             # 500/2,500-block materialization
  examples/vanilla/tests/standalone.spec.ts  # production browser behavior
```

After implementation measurements, retain evidence under `docs/evidence/` and
remove temporary browser measurement code.

## Ownership

### Functional core

Keep these decisions deterministic:

- editor mode and keyboard-focused mode;
- whether first preparation is required;
- whether a delayed refresh still matches current Document text;
- whether a failure shows an initial message or a stale last result;
- whether an allowed retry reuses a healthy pair or replaces an unusable pair;
- exhaustive `MarkdownIR` to typed Rabbita Html rendering; and
- safe URL classification.

The core receives values and returns next state plus commands to run. It does
not read the DOM, viewport, Parser, clock, browser storage, or RUI state.

### Imperative shell

Effects remain in these owners:

- app-owned `TextArea`: native browser input and textarea element;
- `PreviewEngine`: Parser, `MarkdownSemanticAttachment`, and their lifecycle;
- Rabbita commands: Parser transitions, delayed refresh, and preparation;
- standard Rabbita resize subscription: viewport changes;
- RUI: panel ratio, pointer drag, keyboard resize, and separator semantics; and
- browser storage: unchanged open and save effects.

Do not put Parser, attachment, RUI ratio, DOM handles, commands, or scroll state
in the app Model.

## State and messages

Keep **editor mode** separate from Preview preparation state.

- `EditorMode`: `Text | Preview | Split`.
- The keyboard-focused mode is stored separately so Left/Right Arrow can move
  focus without selecting a mode.
- `PreviewState` distinguishes:
  - never requested;
  - preparing with no completed result;
  - a completed `PreviewResult`; and
  - failure with an optional last completed result.
- `PreviewResult` contains the Document text it represents and typed
  `@rabbita.Html`; it derives `Eq` and contains no timing data.

The Model may retain the current compact/wide presentation decision, but never
the RUI size ratio. Every application start selects Text mode; mode is not
stored in browser or session storage. Preserve one standard `create_state_with_init` state
machine. Read initial viewport width in the shell, carry the compact decision
through Loading, and update it from `@sub.on_resize`.

New messages cover these events without creating a queue:

- viewport width changed;
- mode tab focus moved;
- mode selected;
- begin first preparation;
- Parser transition completed or failed;
- delayed Preview refresh requested for candidate text; and
- Preview preparation or refresh completed.

The delayed first-preparation message carries no Document snapshot. When it is
handled, update passes the then-current Model text to `PreviewEngine`.

## PreviewEngine

`PreviewEngine` is constructed once in `app()` and passed to update callbacks.
It stays outside the Model.

Its private state has three cases:

1. no pair yet;
2. one healthy Parser and `MarkdownSemanticAttachment`, plus the Parser source;
3. unusable after a Parser transition failure.

Required behavior:

- First preparation creates `@loom.Parser[@markdown.Block]` with
  `@markdown.markdown_grammar`, then attaches
  `MarkdownSemanticAttachment`.
- `ReplaceRange` validates against the engine's known source and calls one
  `Parser::apply_edit(@loom.Edit::new(...), new_text)`.
- `ReplaceAll` calls one `Parser::set_source(new_text)` and does not recreate a
  healthy pair.
- Parser work runs as a Rabbita command after the native input handler returns.
- A Parser transition failure disposes the attachment and marks the pair
  unusable. Do not apply later exact edits to that pair.
- At the next allowed retry, create one replacement pair from current Document
  text. Never keep two active pairs.
- A semantic read or renderer failure retains its healthy pair; retry reads it
  again.
- `MarkdownSemanticAttachment::dispose()` runs before replacing an unusable
  pair. The current app has one page-lifetime document and no in-app close
  action, so no new close protocol is introduced.

Return structured `Result` values to update. Do not hide failures in mutable
flags or abort the app.

## Initial preparation and refresh

### First preparation

Selecting Preview or Split for the first time performs these steps:

1. update Model to Preparing;
2. patch `Preparing preview…` into the Preview reading frame;
3. run an AfterRender command;
4. from that command, schedule a deferred task so the browser has a paint
   opportunity; and
5. have that deferred task emit the no-snapshot preparation message.

Rabbita `AfterRender` means "after DOM patching"; it does not itself guarantee a
browser paint. The browser test must observe that Preparing was inserted before
cold work. If it cannot, stop and diagnose the scheduling boundary rather than
adding a Worker or artificial warm-up.

### Later refreshes

Reuse the existing Autosave pattern:

- schedule a refresh request with candidate Document text after 50 ms;
- when it arrives, compare the candidate with current Model text;
- ignore a different, older candidate; and
- read the attachment and build typed Html only for a current candidate.

Do not add a counter or cancellable timeout handle. Entering Preview or Split
while a normal refresh is pending does not force or reschedule it. If text
changes and returns to the same value within 50 ms, an older equal-text request
may cause one extra refresh. That does not change correctness and is not optimized in this slice.

Once Preview has been prepared, the same rules continue while Text mode hides
it so re-entry normally has a current result.

## Renderer reuse

Restore only the pure direct renderer behavior from commit
`65f134a7bac3c7a624f9d4bde5f0186594f4942f` and its focused tests. Do not restore
the old Driver, projection artifact renderer, Worker, or state. Restore the five
example documents as app-owned Markdown source files embedded by the package
pre-build and exposed through immediate whole-Document replacement actions;
they use the current `TextChange::ReplaceAll`, Parser, Preview, and Autosave path
rather than old application machinery.

The renderer must:

- exhaustively handle all 24 current public `MarkdownIRView` variants;
- use `MarkdownIR::children`, `text_value`, and `diagnostics`;
- preserve tight and loose list behavior, ordered starts, break forms, code
  info, link forms, and diagnostic fallbacks;
- render block and inline Markdown HTML as inert text;
- render long URLs with wrapping, code blocks with internal horizontal
  overflow, and images within the reading width;
- allow the former URL policy: relative, root-relative, fragment, query, and
  protocol-relative destinations, plus `http`, `https`, and `mailto` links;
- exclude `mailto` for images and reject control characters,
  whitespace-changing destinations, and other schemes; and
- open accepted links in a new tab with `target="_blank"` and
  `rel="noopener noreferrer"`.

The renderer returns typed Rabbita Html directly. It never serializes or injects
an HTML string.

## RUI and responsive layout

Reuse `resizable_panel_group_with_input`, `resizable_panel`, and
`resizable_handle`.

- Configure default size 50, minimum 25, maximum 75.
- Leave the ratio entirely to RUI's normal component lifecycle.
- Do not observe, reset, copy, or persist the ratio.
- Above 640 px use horizontal panels.
- At or below 640 px use vertical panels with textarea first.
- Read initial width through the browser shell and use standard
  `@sub.on_resize` for later changes.
- Current RUI captures orientation when the resizable component is constructed;
  it has no dynamic orientation setter. Select an orientation-specific RUI
  component when the breakpoint is crossed. RUI may naturally reinitialize its
  local ratio, which is allowed because Loomark does not retain or reset it.
- Rabbita VDOM reconciliation must preserve the existing textarea element while
  replacing that orientation-specific component. Prove this in the first
  browser prototype. If it replaces the textarea, stop; this issue authorizes
  neither modifications to RUI nor a custom divider.
- Do not implement drag behavior or orientation with custom DOM listeners.

RUI tabs are not reused. Their current Arrow-key handler focuses **and clicks**
the next tab, which automatically selects it. The accepted interaction uses
manual activation: Arrow keys move focus; Enter or Space selects. Implement
three typed Html buttons with `role="tab"`, roving `tabindex`, `aria-selected`,
`aria-controls`, matching accessible names and native `title` text, visible
selected state, and visible focus. Activation leaves focus on the selected tab.
The five restored example actions follow the mode tabs in DOM and keyboard
order, followed by the visible content.

Render the textarea under a stable structural path. Browser E2E must prove that
the exact `HTMLTextAreaElement` object survives mode changes, RUI dragging, and
responsive orientation changes. Stop if any of those operations replaces it.

## Visual and accessibility behavior

Retain the previous full-height editor structure while applying the accepted
cool gray-white palette and restored example actions:

- fixed top mode bar with left-aligned icon-only mode controls and the five
  `Demo`, `Hello`, `Guide`, `List`, and `Code` actions on the right;
- near-white, low-chroma gray paper and shell surfaces without an outer frame,
  shadow, webfont, dark-mode branch, or custom scrollbar styling;
- centered 46 rem reading width and compact mobile inset;
- borderless, non-resizable monospace textarea;
- previous Markdown typography;
- centered Loading text and centered Recovery panel no wider than 36 rem;
- Document-wide Autosave failure bar at the shell bottom;
- Preview-local sticky stale alert and no Preview Retry button;
- muted `Nothing to preview` text for a completed empty semantic document;
- immediate mode/layout changes with no added animation; and
- native scrollbars.

Keep `#loomark-text` and `#loomark-preview-scroll` as stable internal DOM seams.
Do not attach scroll listeners in this issue.

Preview is a focusable region named `Markdown preview`. From the mode bar,
keyboard order passes through the five example actions before entering visible
content. Within Split content, order is textarea, Preview region, then links.
Preparing and empty completion are polite status messages; failures are alerts;
completed Markdown is not a live region.

## Existing API First

| Responsibility | Existing candidate | Decision |
|---|---|---|
| Exact Document change | `@text_change.TextChange::apply` | Reuse for Model update and engine validation. |
| Incremental Parser change | `Parser::apply_edit` | Reuse for every healthy `ReplaceRange`. |
| Complete replacement | `Parser::set_source` | Reuse for `ReplaceAll`; do not rebuild a healthy pair. |
| Parser construction | `@loom.new_parser` / `Parser::new` | Reuse the existing public facade used by Markdown consumers. |
| Semantic document | `MarkdownSemanticAttachment::document` | Reuse; do not fold syntax independently. |
| Attachment cleanup | `MarkdownSemanticAttachment::dispose` | Reuse before broken-pair replacement. |
| Preview rendering | Historical direct typed-Html renderer | Restore the pure renderer only. |
| Resizable layout | RUI resizable panel group, panels, handle | Reuse; RUI owns ratio and interaction. |
| Mode tabs | RUI tabs | Checked but not reused because Arrow keys automatically activate. |
| Delayed work | `@cmd.delay`, `@cmd.custom_cmd`, `@cmd.after_render` | Reuse; AfterRender is followed by a deferred task for a paint opportunity. |
| Viewport changes | `@dom.window().inner_width`, `@sub.on_resize` | Reuse; no custom resize listener. |
| Child traversal | `Array::map`, `Array::join`, `MarkdownIR::children` | Reuse where the historical renderer already does. |
| String inspection | `String::trim`, `contains_any`, `to_lower`, `find`, `has_prefix`; `StringView` parameters | Reuse for URL validation without a new parser. |
| Optional and failed values | `Option` matching and `Result` | Reuse; no exception suppression. |
| `ArrayView` | Core view API | Checked; renderer receives owning child arrays, so a new view layer is unnecessary. |
| `Map` / `Set` | Core keyed collections | Checked; fixed enums and exhaustive matching need no keyed collection. |
| `Buffer` / `StringBuilder` | Core builders | Checked; production renderer builds typed Html, so no output string builder is needed. `StringBuilder` is appropriate only for benchmark fixture construction. |
| `cmp` / `math` | Core comparison/math helpers | Checked; RUI owns size clamping and the breakpoint needs only one integer comparison. |
| `Iter` | Core iterator API | Checked; existing array methods are clearer for the renderer's owning children. |

Any new helper must stay private unless it forms the narrow `PreviewEngine`,
`PreviewResult`, or `PreviewFailure` package boundary.

## Red-green implementation order

### 0. Preflight

1. Fetch current `origin/main`, create/update the dedicated worktree, and verify
   submodule commits and module identities.
2. Run the current focused check and all nine Warren production E2E tests.
3. Record the behavioral boundary matrix from this plan in the first test
   change.

### 1. Prototype the UI shell first

1. Add a failing browser test for Text/Preview/Split controls and exact textarea
   object identity.
2. Add modes, manual keyboard activation, the old visual frame, and a placeholder
   read-only Preview.
3. Add RUI resizable Split and standard responsive orientation.
4. Verify in Chromium that mode switches, divider drag, and crossing 640 px do
   not replace the textarea or lose native undo.
5. Review screenshots at wide and narrow sizes before adding Parser work.

Stop here if the persistent textarea cannot be proven.

### 2. Restore the pure renderer

1. Add `internal/preview` and port the historical direct renderer tests first.
2. Restore the exhaustive typed-Html renderer and safe URL policy.
3. Add coverage for inert raw HTML, rejected URLs, new-tab attributes, tight and
   loose lists, long content, images, and every fallback variant.
4. Add retained 500- and 2,500-block release benchmarks for renderer
   materialization.

### 3. Add Preview state and lazy preparation

1. Add pure update tests for mode selection, first preparation, no preparation
   in Text-only use, failure display, and allowed retry decisions.
2. Add `PreviewEngine`, Parser/attachment creation, latest-text Prepare handling,
   and disposal on broken-pair replacement.
3. Prove Preparing is inserted before cold work with browser-only observation;
   add no production test hook.
4. Keep initial, current, and stale display states distinct.

### 4. Synchronize Parser and debounce visible refresh

1. Add tests that `ReplaceRange` maps to one `apply_edit` and `ReplaceAll` to one
   `set_source` after the native handler returns.
2. Add the Autosave-style 50 ms candidate comparison and verify that only
   semantic read, typed Html, and publication wait.
3. Cover IME: intermediate events schedule no new work; previously scheduled
   work may finish; composition end advances once.
4. Cover parser failure, healthy semantic failure, retry, and preservation of
   the last successful Preview.

### 5. Production browser coverage

Extend `standalone.spec.ts` without production debug APIs:

- manual tab focus and Enter/Space activation;
- no Preview preparation from Arrow focus alone;
- initial Preparing observation and lazy construction behavior;
- textarea identity, selection, native undo/redo, and value across every mode;
- RUI pointer and keyboard resize plus 25–75 bounds;
- horizontal/vertical orientation across 640 px while preserving textarea;
- read-only Preview, empty state, links, raw HTML safety, and responsive layout;
- immediate example-document replacement through current Document, Preview,
  and Autosave paths;
- independent native Text and Preview scrolling in both Split orientations,
  with the textarea scrollbar at its pane's right edge;
- 50 ms refresh behavior and IME boundary;
- initial and stale failure reducer coverage, with browser coverage only where a
  real boundary can fail without a production hook; and
- all existing storage, recovery, exact-input, and 10 ms Text-input tests.

### 6. Measurement and final validation

1. Build the exact production renderer and run three fresh Chromium launches on
   the existing approximately 500-block practical corpus.
2. Report initial full preparation, first cold incremental preparation, later
   incremental preparation, typed-Html materialization, after-render wall time,
   and visible freshness separately.
3. Preserve the independent 10 ms Text-input gate with per-edit Parser
   transitions. Treat 10 ms later practical-corpus Preview preparation as an
   investigation target rather than a release gate.
4. Run the 2,500-block renderer benchmark as scaling characterization, not as
   evidence about practical-corpus acceptance.
5. Report any Preview target miss by measured phase. Do not add a Worker,
   virtualization, partial renderer, or warm-up under this issue; carry further
   optimization as a measured Loom follow-up after acceptance.
6. Remove temporary browser measurement code and retain source-backed evidence.
7. Run independent MoonBit review, fetch `origin/main` again, sync if needed,
   repeat affected checks, then follow the repository push/CI workflow.

## Validation commands

```bash
# Focused loop from repository root
NEW_MOON_MOD=0 moon check --target js apps/loomark/internal/preview apps/loomark/app
NEW_MOON_MOD=0 moon test --target js apps/loomark/internal/preview apps/loomark/app

# Format and generated interfaces
NEW_MOON_MOD=0 moon fmt apps/loomark/internal/preview apps/loomark/app apps/loomark/main
NEW_MOON_MOD=0 moon info apps/loomark/internal/preview apps/loomark/app apps/loomark/main
git diff -- '*.mbti'

# Retained renderer benchmark
NEW_MOON_MOD=0 moon bench --release apps/loomark/internal/preview

# Warren production browser suite
./scripts/test-loomark-standalone-e2e.sh

# Final workspace validation
moon check
moon test

git diff --check
```

After `moon info`, the public app interface must remain only
`app() -> @rabbita.Val[@rabbita.Html]`. Review the new internal Preview
interface for accidental Parser, attachment, mutable collection, or RUI type
leaks. Any widened generated trait bound is an API regression.

## Documentation, tests, and evidence

- Update `apps/loomark/CONTEXT.md`, this plan, and the prior plan's supersession
  note in the design PR.
- TypeScript product code does not change; Playwright production tests do.
- Implementation evidence records exact environment, commits, fixture, raw
  samples, and separated cold/steady phases.
- The current evidence is
  [2026-08-26-loomark-preview-split-production-performance.md](../evidence/2026-08-26-loomark-preview-split-production-performance.md).
- Link the final evidence from #1372 and this plan.
- Do not claim Safari device validation without macOS/iOS Safari hardware tests.

## Stop conditions

Stop and return for a new decision if:

- RUI mode/orientation changes replace the textarea element;
- Preparing cannot become observable before cold work;
- a healthy Parser cannot remain aligned with Document text;
- ordinary exact input performs a complete textarea read or complete-source
  diff;
- raw Markdown HTML becomes executable;
- the independent Text-input performance gate fails;
- generated interfaces expose unintended implementation types or wider bounds;
- a changed submodule becomes necessary; or
- a build, test, or runtime failure cannot be reproduced and explained.

Do not add a fallback, compatibility layer, suppression, or optimization to
make an unexplained failure pass.
