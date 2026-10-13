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
| **App & UI Shell** | `app/` | Rabbita component tree, view modes (Text, Preview, Split), viewport coordination, and DOM event subscriptions. |
| **Domain Logic** | `internal/` | Pure document catalogs (`documents/`), local-first storage engines (`source_repository/`), writing focus algorithms (`writing_focus/`), and sign-in state machines (`sign_in/`). |
| **Server & Sync** | `server/` | Cloudflare Worker endpoints, Google OAuth handlers, D1 database migrations, and replica conflict resolvers. |

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
- **Split Scroll Alignment (`app/split_scroll.mbt`):** Split mode attaches directly to the resolved scroll owner, synchronizing textarea and preview positions. The connection cleanly resets across document switches, mode changes, or layout breakpoint transitions.

### 4.2 Writing Focus

While actively typing, surrounding paragraphs gently fade to 50% opacity, while the active paragraph—including block quotes—and current selection remain 100% visible:

- **Core Algorithm (`internal/writing_focus/`):** Pure layout and presentation decisions calculate active block boundaries without touching the browser DOM.
- **Browser Integration (`app/writing_focus.mbt`):** Measures DOM node rectangles, applies subtle opacity transitions, and manages subscription lifetimes. Leaving the editor instantly restores full readability across the document.

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
- **Pure Calculation Engine (`app/viewport_policy.mbt`):** Contains pure numeric CSS parsing and arithmetic for caret scrolling, viewport bounds, keyboard baselines, and split alignments. It neither reads nor mutates retained state.
- **DOM Access Boundary (`app/viewport_dom.mbt`):** Encapsulates low-level native DOM accessors, isolating native browser calls from application logic.
