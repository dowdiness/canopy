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

---

## 1. High-Level Architecture & Data Flow

Loomark follows a clean unidirectional flow built on [Rabbita](https://github.com/dowdiness/rabbita) (a TEA-inspired MoonBit web framework). What the user writes in the native `<textarea>` is the single source of truth; everything else—previews, sidebars, autosave—is derived incrementally.

```
                     ┌──────────────────────────────┐
                     │ Native Browser <textarea>   │
                     │ (Source of Truth / Keystroke)│
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
  `internal/writing_focus/browser/` owns measurement, animation policy, and
  listener lifetimes. Browser implementation types stay private to that package.
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
- **Split Scroll Alignment (`internal/viewport/split_scroll.mbt`):** Split mode attaches directly to the resolved scroll owner, synchronizing textarea and preview positions. The connection cleanly resets across document switches, mode changes, or layout breakpoint transitions.

### 4.2 Writing Focus

While actively typing, surrounding paragraphs gently fade to 50% opacity, while the active paragraph—including block quotes—and current selection remain 100% visible:

- **Core Algorithm (`internal/writing_focus/`):** Pure layout and presentation decisions calculate active block boundaries without touching the browser DOM.
- **Browser Integration (`internal/writing_focus/browser/`):** Measures DOM node rectangles, applies subtle opacity transitions, and manages subscription lifetimes. Leaving the editor instantly restores full readability across the document.

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
  - The **top toolbar and failure notices remain available** at all times.
- **Known Limitations:**
  - Small or floating keyboards, rotation with the keyboard open, and startup without an unobscured sample can leave the bar visible.
  - Large browser-UI changes (such as dynamic address-bar collapse) can also resemble a keyboard.
- **Edge Softening & Scroll Padding:** Text and Preview share softened edge fades beneath fixed controls. The bars own their blurred backgrounds, leaving no independent overlay or reserved gap when the bottom bar is hidden. Textarea `scroll-padding` keeps native caret navigation clear of controls without requiring manual per-input DOM measurements; manual reading scrolls remain browser-owned.

### 4.5 Element Resizing & Caret Visibility

- **ResizeObserver Integration:** Loomark uses Rabbita's typed `@dom.ResizeObserver` to observe the textarea after rendering.
- **Safe Fallback:** Observer creation and registration run inside `@js.try_sync`, preserving safety on browsers without full modern API support. The subscription disconnects the observer when that node is replaced. Width and height changes trigger caret measurement independently of visual-viewport events.
- **Pure Calculation Engine (`internal/viewport/policy.mbt`):** Contains pure arithmetic for caret scrolling, viewport bounds, keyboard baselines, and split alignments. It neither reads nor mutates retained state. Shared resolved CSS numeric parsing lives in `internal/browser/css.mbt` and preserves NaN for nonnumeric keywords such as `normal`.
- **DOM Access Boundary (`internal/browser/`):** Encapsulates missing native DOM accessors in object-specific files, isolating native browser calls from application logic. Viewport scheduling and retained measurements remain in `internal/viewport/`.
