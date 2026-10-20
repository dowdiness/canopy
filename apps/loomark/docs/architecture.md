# Loomark Technical Architecture

This document details the internal architecture, runtime lifecycle, and DOM subsystems of Loomark.

- For a high-level product introduction and philosophy, see the [Loomark README](../README.md).
- For canonical product terminology and behavioral rules, see [CONTEXT.md](../CONTEXT.md).
- For remote sync and database mechanics, see [sync-and-account.md](sync-and-account.md).
- For the full document map, see [Documentation Index](README.md).

---

## Table of Contents

1. [High-Level Architecture & Data Flow](#1-high-level-architecture--data-flow)
2. [Codebase Organization](#2-codebase-organization)
3. [Application Lifecycle & Startup](#3-application-lifecycle--startup)
4. [Key Subsystems](#4-key-subsystems)
   - [4.1 Editing & Incremental Preview](#41-editing--incremental-preview)
   - [4.2 Writing Focus](#42-writing-focus)
   - [4.3 Demand-Driven Sidebar](#43-demand-driven-sidebar-recent-documents)
   - [4.4 Mobile Viewport & Virtual Keyboard Handling](#44-mobile-viewport--virtual-keyboard-handling)
   - [4.5 Element Resizing & Caret Visibility](#45-element-resizing--caret-visibility)
   - [4.6 Document Lifecycle](#46-document-lifecycle)

---

## 1. High-Level Architecture & Data Flow

Loomark follows a unidirectional flow built on [Rabbita](https://github.com/dowdiness/rabbita). The native `<textarea>` owns browser input, composition, and undo. `documents.Model` owns admitted Document text and persistence transitions; previews, document leads, and autosave consume that text.

Explicit operation failures emit `Notify` only after the application accepts the
result. Notifications are events, not differences between rendered error strings;
two accepted failures with the same message each notify. Autosave failures remain
in the persistent **Not saved** indicator without a duplicate toast.

`sonner_host` builds the application once with its notification scope. Sonner owns
timers, retained DOM slots, and interaction pause state. The application supplies
a focus-return command that reads its current editor mode; it runs only when a
closing notification owns focus. Neither notification commands nor focus callbacks
are stored in the application Model.

```
                     ┌──────────────────────────────┐
                     │ Native Browser <textarea>   │
                     │(Input / Composition / Undo) │
                     └──────────────┬───────────────┘
                                    │
                  ┌─────────────────┴─────────────────┐
                  ▼                                   ▼
        ┌──────────────────┐                ┌──────────────────┐
        │  Document Text   │                │  Autosave Timer  │
        │ (Committed Input)│                │  (250 ms quiet)  │
        └─────────┬────────┘                └─────────┬────────┘
                  │                                   │
                  ▼                                   ▼
        ┌──────────────────┐                ┌──────────────────┐
        │   SyntaxParser   │                │ Source Repository│
        │(Incremental CST) │                │  (IndexedDB)     │
        └─────────┬────────┘                └─────────┬────────┘
                  │ (24 ms quiet window)              │
                  ▼                                   ▼
        ┌──────────────────┐                ┌──────────────────┐
        │   Markdown IR    │                │ (Optional) Sync  │
        │(Direct Lowering) │                │Worker / D1 Cloud │
        └─────────┬────────┘                └──────────────────┘
                  │
                  ▼
        ┌──────────────────┐
        │   HTML Preview   │
        │ (Typed Renderer) │
        └──────────────────┘
```

---

## 2. Codebase Organization

The Loomark codebase is structured into three distinct layers:

| Layer | Directory | Responsibilities |
|---|---|---|
| **App & UI Shell** | `app/` | Application Model/Msg, state updates, view projections, and selection of active feature subscriptions. |
| **Features & Browser Integration** | `internal/` | Document transitions, persistence, synchronization, UI components, pure calculations, and browser effects in their owning packages. |
| **Server & Sync** | `server/` | Cloudflare Worker endpoints, Google OAuth handlers, D1 database migrations, and replica conflict resolvers. |

### Package ownership

- `internal/documents/`, `internal/sync/`, and `internal/source_repository/`
  own document transitions, synchronization, and browser persistence.
- `internal/writing_focus/` owns pure writing-focus calculations;
  `internal/writing_focus/browser/` owns presentation measurements, animation
  policy, and listener lifetimes.
- `internal/text_layout/` owns the single incremental textarea mirror shared by
  reading position and writing focus: copied styles, line geometry, and retained
  nodes for native Undo. Its document-owned surface retains no textarea and
  exposes synchronous line and caret measurements, not DOM mutation protocols.
  Every position query takes the textarea, synchronizes the surface, and returns
  plain values; no result retains the mirror. Offset searches synchronize once
  for the entire search. Consumers cache against immutable source identity and
  an explicit reflow revision, separate from the numeric metrics. Font loads
  advance that revision even when computed CSS is unchanged. Neither feature
  owns cleanup of the surface or its retired nodes.
- `internal/text_lines/` owns the pure UTF-16 line index and incremental edits.
  It knows neither DOM nor Markdown. Writing focus builds its Markdown groups
  from this index only when dimming needs them; reading position does not.
- `internal/viewport/` owns viewport placement, caret visibility, and Split
  scroll geometry and effects. The app selects the active connections.
- `internal/browser/` owns feature-independent browser operations and resolved
  CSS numeric parsing. Native operations are grouped by object in `document.mbt`,
  `element.mbt`, `window.mbt`, `visual_viewport.mbt`, `animation.mbt`, and `file.mbt`.
  Both viewport and writing-focus browser code depend on it; writing focus does
  not depend on viewport. Feature-specific observers and policy stay with their
  owning features.
- `internal/examples/` owns example selection UI, Markdown sources in
  `documents/`, and their build-time embedding.
- `internal/recent_documents/`, `internal/sidebar/`, and `internal/view/`
  own the existing UI components.

These are packages within the Loomark module, not separately versioned
libraries. Dependencies point from application composition to feature packages,
never back to `app` types. Keep app-specific account/document coordination in
`app` rather than exposing its Model merely to split files.

---

## 3. Application Lifecycle & Startup

Loomark exposes a single entry point defined in `apps/loomark/app`:

```moonbit
pub fn app() -> @rabbita.Val[@rabbita.Html]
```

1. **Startup (`app/app.mbt`):** Initializes stable browser handles and kicks off the initial reconciliation of stored documents against IndexedDB via `internal/source_repository`.
2. **Post-Render Wire-up (`app/subscriptions.mbt`):** Resolves visible editor elements (the active `<textarea>`, scroll containers, and split dividers) and attaches typed event observers.

---

## 4. Key Subsystems

### 4.1 Editing & Incremental Preview

- **Native Input:** Keystrokes flow directly into `modules/rabbita-markdown/text_area`, which produces minimal `TextChange` diffs.
- **Incremental Syntax Parsing:** Changes feed into a long-lived `SyntaxParser`, re-parsing only the affected CST subtrees.
- **Demand-Driven Preparation:** Text mode creates no syntax parser. Choosing Preview or Split creates at most one parser for the selected document. Returning to Text retains the parser and keeps it updated with committed Document text without producing hidden preview output.
- **Quiet-Window Refresh:** Preview lowering waits for a 24 ms candidate-text quiet window so rapid keystrokes produce a single coherent syntax snapshot, lowered directly to MarkdownIR and rendered to typed HTML.
- **Reading Position (`internal/viewport/`):** Text and Preview answer the same geometry questions: where a source offset is shown, which offset is shown at a height, and where the readable area lies. `TextGeometry` reads them from a hidden mirror of the textarea; `@preview.PreviewGeometry` reads them from the rendered Preview, whose blocks record their source ranges. A mode change records a `ReadingAnchor` in the pane being read and holds it in the next pane until the user engages a pane, scrolls it away, or edits. Split follows the reading pane with the same geometry. The mode, which in Split names the reading pane, and the held anchor decide what keeps each pane in place: the textarea reveals the caret, holds the anchor, or follows Preview (`TextPlacement`).

### 4.2 Writing Focus

Only in explicit Focus Mode, surrounding paragraphs gently fade to 50% opacity while the textarea has focus; the active paragraph—including block quotes—and current selection remain 100% visible:

- **Core Algorithm (`internal/writing_focus/`):** Pure layout and presentation decisions calculate active block boundaries, visible ranges, fades, and dimming-layer bounds from text and measured numbers without touching the browser DOM.
- **Mode Ownership (`app/model.mbt`, `app/update.mbt`):** `focus_mode` is a presentation flag independent of the editor mode. Entry and exit preserve Text, Preview, or Split and do not invoke the mode-change path. Toggling leaves focus where it is, never focusing the textarea, so it cannot summon an on-screen keyboard; focus moves to Recent documents only when exit makes the editor inert. `app/focus.mbt` resolves focus candidates after rendering, passes their inert state to a pure focus decision, and applies the result.
- **Connection (`app/writing_focus.mbt`):** Resolves this render's textarea and dimming layer only after rendering, then passes those elements to the browser connection. Like text placement, Split following, and the Preview anchor, it attaches through `AfterRender` (`app/after_render.mbt`), whose state is awaiting render, attached, or detached: subscription removal cancels pending attachment or releases the existing connection once, and deferred work or browser callbacks cannot revive it.
- **Browser Integration (`internal/writing_focus/browser/`):** Receives elements rather than IDs, measures their geometry, passes measured values to the core, and applies opacity and positioning decisions. Each frame first brings the per-line mirror's text and copied styles up to date; a focus range or caret measured for the same text, styles, and lines or offset is reused, so scrolling and moves within a paragraph read no layout. Owns listeners, animation frames, and cleanup; its mutable connection handle stays in the shell, never in the application model. Leaving the editor instantly restores full readability across the document.
- **Chrome (`app/layout.mbt`, `styles/tailwind.css`):** The toggle is a sibling of the footer inside the viewport-sized editor and, like the view controls, is hidden while a keyboard is detected and the textarea has focus; without that focus no on-screen keyboard can be open, so a mistaken detection keeps the exit. CSS hides routine controls without destroying their state. Failure notices and exceptional sync/durability actions remain available.
- **Writing caret:** The same session draws the caret in the writing-focus layer from the mirror's line elements, so one per-line mirror serves both features. The session runs in Text and Split whether or not Focus Mode is on; Focus Mode attaches dimming to it and leaving detaches it, so toggling keeps the mirror and the caret, and the session measures the focused paragraph only while dimming is attached. Like CodeMirror's layers and VS Code's cursors, each frame reads the caret's layout before writing. As in VS Code, typing cancels the blink once and a 500 ms pause plays it again, so continuous typing adds no animation work per keystroke. Only the changed span of a mirror line is replaced, letting Chromium reuse its shaping. Every line draws the caret: the native textarea already lays out the edited line on each keystroke, so a native-caret fallback for long lines would only halve a cost that remains. Pure decisions choose whether the caret is drawn (`selection_end`; an IME composition caret is a collapsed selection, so composition needs no separate state), whether it needs a layout read and what moved it (`caret_measure`), and how a shown caret follows its next placement (`caret_move`: still, scroll, jump, or glide): like VS Code's `explicit` smooth caret, only navigation through unchanged text glides, because starting an animation on every keystroke costs extra main-thread frames; the native caret is transparent only while the drawn caret is shown.

### 4.3 Demand-Driven Sidebar (Recent Documents)

- **Demand-Driven Evaluation:** Recent documents entries render and compute layouts only when the sidebar drawer is actually opened.
- **Bounded Recognition Content:** Document leads are computed on demand by parsing source into a syntax tree, lowering directly to MarkdownIR, and deriving a bounded primary lead (heading, task, list, code, or plain content) along with a structured description of subsequent readable content within finite text budgets.

<a id="mobile-viewport"></a>
### 4.4 Mobile Viewport & Virtual Keyboard Handling

Loomark uses Rabbita's typed `@dom.VisualViewport` for native viewport access and resize/scroll events:

- **Interactive Resizing:** The HTML shell sets `interactive-widget=resizes-content`. Supported browsers resize the layout dynamically rather than leaving an exposed document strip above the virtual keyboard. Other browsers retain the visual-viewport path.
- **Available Height Calculation:** Available height is computed as `visualViewport.height * visualViewport.scale`. Zoom alone preserves layout height, while resizing continues normally while zoomed. Zoom panning retains the last layout offset, bounded by the remaining layout height.
- **Two Detection Paths for Bottom-Bar Visibility:**
  1. *Visual Viewport Occlusion:* Direct detection on browsers without content resizing.
  2. *Layout Height Deficit:* Under content resizing, baseline height is estimated from the largest observed layout height, adjusted by changes in `window.outerHeight`. A deficit greater than 100 CSS pixels hides the bottom bar. Width changes reset this estimate.
- **Invariants:**
  - Detection affects **bottom-bar visibility only**, never the editor's available height.
  - The **Focus Mode toggle hides with the bottom bar while the textarea has focus**; failure notices remain available, and the top toolbar stays available outside Focus Mode.
- **Known Limitations:**
  - Small or floating keyboards, rotation with the keyboard open, and startup without an unobscured sample can leave the bar visible.
  - Large browser-UI changes (such as dynamic address-bar collapse) can also resemble a keyboard.
- **Edge Softening & Scroll Padding:** Text and Preview share softened edge fades beneath fixed controls outside Focus Mode. The bars own their blurred backgrounds, leaving no independent overlay when the bottom bar is hidden. Textarea bottom padding returns only while a footer, such as `Not saved` or Focus Mode attention actions, stays visible with a keyboard. Textarea `scroll-padding` keeps native caret navigation clear of controls without requiring manual per-input DOM measurements; manual reading scrolls remain browser-owned.

### 4.5 Element Resizing & Caret Visibility

- **ResizeObserver Integration:** Loomark uses Rabbita's typed `@dom.ResizeObserver` to observe the textarea after rendering.
- **Node Replacement:** The subscription disconnects the observer when that node is replaced. Width and height changes place the textarea again (`TextPlacement`) independently of visual-viewport events.
- **Pure Calculation Engine (`internal/viewport/policy.mbt`):** Contains pure arithmetic for fitting lines into the readable area, locating textarea lines, viewport bounds, and keyboard baselines. It neither reads nor mutates retained state. Shared resolved CSS numeric parsing lives in `internal/browser/css.mbt` and preserves NaN for nonnumeric keywords such as `normal`.
- **DOM Access Boundary (`internal/browser/`):** Encapsulates missing native DOM accessors in object-specific files, isolating native browser calls from application logic. Viewport scheduling and retained measurements remain in `internal/viewport/`.

### 4.6 Document Lifecycle

`internal/documents` exposes `Model` and `Msg` for Document lifecycle transitions:

| Operation | Normal outcome | Raised refusal |
|---|---|---|
| `Model::create(document_id)` | `Transition` | `CreateError`: duplicate identity |
| `Model::edit(key, text)` | `Changed(Transition)` or `SameText` | `EditError`: missing Document or pending deletion |
| `Model::delete(key)` | `Accepted(Transition)` or `AlreadyPending` | `DeleteError`: missing Document, ownership transfer, or missing Replica |
| `Model::update(msg)` | `Applied(Transition)`, `Unchanged`, or `Superseded` | `UpdateError`: missing Document, blocked retry, duplicate identity, mismatched Document, or invalid acknowledgment |
| `Model::save_changes()` | `Transition` | `DeleteError` if retrying a deletion cannot be admitted; no partial model or effects escape |

A `Transition` contains the next `model` and read-only `effects`. The model
contains no browser commands or callbacks. The app installs the model and
hands effects to their owner in the same root update; browser work then
returns a concrete `Msg`, such as `Saved`, `SaveFailed`, or `Deleted`.
Storage failures become retryable model facts. They do not raise into the
caller that originally requested an asynchronous write.

`Model(saved)` constructs the lifecycle model from saved Documents.
`model.create(document_id)` instead adds an untouched New document to that
existing model, preserving its Documents and pending work. Creation returns a
transition directly, never `Unchanged` or `Superseded`; duplicate identities
raise `CreateError::DocumentAlreadyExists`. Its effects are empty, and the New
document remains absent from storage and Recent documents until its first edit.
The app handles creation directly, like `edit` and `delete`, rather than
sending a creation request through `Msg`.

Editor input branches directly on `Edit`: `Changed` installs the transition and
forwards accepted text to the editor; `SameText` leaves the model and Preview
unchanged. An `EditError` restores authoritative text and displays the refusal,
without forwarding the rejected edit. Example creation likewise handles the
edit outcome before activation. Neither path infers acceptance by comparing
the resulting Document text.

`Unchanged` means that the current input is already satisfied, such as a
duplicate composition notification, a flush without pending work, or a retry
without a failed save. `Superseded` instead identifies obsolete acknowledgments,
timers, notifications for a removed Document, and attempts to begin composition
or flush a Document whose deletion is pending.

Explicit retry and failure-dismissal requests require an existing Document.
Retrying a pending deletion's save raises `PendingDeletion`. Retrying a failed
save during IME composition raises `CompositionInProgress`, retains the text
and failure, and does not queue a retry. The app displays the refusal; finishing
composition allows a subsequent explicit retry.

Editing contract tests use the public text, Recent documents, pending-edit and
save-status projections and the emitted effects. They do not depend on the
private `Record` or `LeadSource` representation.

Promotion and fork-recovery durability tests drive public lifecycle operations
and complete the actual persistence attempts. After the ownership write commits,
they verify an empty persistence queue, an older saved body, and newer Document
text that is still `Saving`. Only acknowledgment of the newer body makes the
model `Durable`; a pending ownership write cannot mask a premature durability
decision.

Source save and deletion ownership is a single sum in
[`documents_types.mbt`](../internal/documents/documents_types.mbt):

| Source phase | Required state | Persistence restriction |
|---|---|---|
| `Writable` | Source save phase and any previous deletion failure | At most one active Source write and one text-free pending autosave window |
| `WaitingToDelete` | Active save, accepted deletion, optional pending window | The active save must settle before deletion; no newer save starts |
| `Deleting` | Accepted deletion and restoration autosave state | Restoration cannot contain an active Source write |

Deletion failure restores the working copy and its autosave eligibility.
An eligible newer edit can resume saving without losing the deletion retry.
While Source or Replica deletion is pending, `CompositionEnded` still records
the end of composition in the retained working copy, but starts no save or
timer. If deletion fails, a pending edit can resume its quiet window, and an
already eligible edit can save without another composition notification.
Source saves carry a private attempt identity taken from the consumed
autosave window. Imports and explicit retries allocate fresh windows,
so identical Document identity and text cannot admit an older completion.
Retrying deletion likewise allocates a fresh operation. A current
acknowledgment with the wrong Document raises an error; an obsolete or
duplicate Source completion yields `Superseded`.

The 250 ms quiet window, non-restarting 2000 ms maximum window, and IME
deferral remain independent of storage latency. Promotion and recovery
retain edits while ownership transfers. Replica write ordering and durable
acknowledgments remain the responsibility of `internal/replica_persistence`.
The app rejects stale Replica attempts there before translating accepted
acknowledgments into document `Msg` values; an idle autosave window is not
evidence of Replica durability.

At the app level, `Creation` holds only request identity, intent, and
progress or failure. `OpeningNew` keeps document and display context
separate from its required creation request; an editing page has an
optional `Creation`. Creation request IDs are distinct from editor
activation generations. Both identity-generation failure and a rejected
identity can be retried with a fresh request, while older completions are
ignored. A failed opening creation has its own screen with the failure
notice and retry action, not a storage-read failure screen. Typed document
refusals produce a visible notice and do not continue into dependent edits
or activation.
