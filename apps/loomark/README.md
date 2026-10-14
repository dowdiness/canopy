# Loomark

A quiet, local-first Markdown space for your thoughts.
Built around one simple principle: **the text you type is the only source of truth.**

Open the browser. Start writing. No noise, no sign-up, no lock-in.

---

## The Philosophy: A Quiet Desk

Most modern writing tools try to do too much. They crowd your screen with floating menus, AI popups, and red spellcheck squiggles. They silently transform your characters or hide your words behind complex, proprietary formats.

**Loomark was built to give you back a calm, reliable desk:**

1. **Text is Ground Truth:** What you type is literally what is saved and exported. No hidden attributes, no arbitrary restructuring, and no lossy conversions.
2. **The Tool Stays Out of Your Way:** When you write, the editor recedes. Your active thought stays in focus, and surrounding paragraphs gently fade into the background.
3. **Your Words Belong to You:** Once loaded, Loomark lets you keep writing without an internet connection. It saves directly to your device first, and you can export standard Markdown at any moment.
4. **Reliability Over Novelty:** Every interaction—from caret navigation to native Undo/Redo—respects your natural muscle memory.

---

## The Experience

### ✍️ Pure, Distraction-Free Drafting
- **Natural Native Typing:** Standard browser text editing keeps IME composition and browser Undo/Redo completely natural.
- **Zero Visual Noise:** No dictionary red lines, no autocorrect interruptions, and no unexpected formatting jumps. Write freely in any language, dialect, or code snippet.
- **Two Typefaces, Two Moments:** Draft in a warm duospaced writing face; read in a literary serif. Both ship with the app, so they work offline once loaded.
- **Writing Focus:** While typing, surrounding paragraphs gently fade into the background so you can focus on the active sentence. Leaving the editor restores full readability immediately.

### 🍃 Thoughtful Modes & Viewport
- **Three Views:** Toggle effortlessly between **Text** (pure drafting), **Preview** (clean formatted reading), and **Split** (side-by-side with a draggable divider).
- **Light & Dark:** Follows your system appearance with the same warm paper tone; printing from Preview produces a clean reading page.
- **Mobile Responsive:** Adapts cleanly to on-screen keyboards and device rotation, hiding extraneous bottom bars to maximize vertical writing space.

### ☕ Local-First Peace of Mind
- **Quiet Autosave:** Automatically persists to your browser after a short pause in typing or when switching tabs. The footer always confirms local save status with an explicit retry option if a save fails.
- **Start Immediately:** Open the app and write. Loomark derives recognizable document leads from your first heading or line without requiring you to name or organize files first.
- **Recent Documents:** A lightweight slide-out sidebar lets you revisit and switch between recent documents seamlessly.

### 🛡️ Freedom & Optional Sync
- **Zero Lock-In:** Import any standard UTF-8 Markdown file cleanly. Export your current note as a `.md` file with one click at any time.
- **Opt-In Cloud Sync:** Sign in with Google to sync individual documents across devices when you choose. Sync is explicitly chosen per document, never forced on your private notes.
- **Explicit Conflict Recovery:** If offline edits diverge across devices, Loomark never silently overwrites your work. Divergent edits fork safely into local **Recovery documents**.

---

## The Interface: Simple & Intentional

Loomark has zero clutter, keeping all essential tools right at your fingertips:

- **Top-Left (Menu icon):** Opens the Recent documents drawer to switch between documents or view automatically extracted leads.
- **Top-Right (Pen icon):** Starts a fresh document instantly.
- **Mode Switcher (Text / Preview / Split):** Toggle between drafting, rendered reading, or side-by-side editing with a draggable divider.
- **More Actions (`...` menu):** Cleanly export your current note as a `.md` file, import existing Markdown documents, or manage optional cloud sync.
- **Footer:** Displays quiet durability feedback (`Saved on this device`, `Saving on this device`, or `Not saved`) with explicit retry controls when needed.

---

## When to Reach for Loomark

- **Morning stream of consciousness & journaling:** Open a blank tab and let thoughts flow without deciding on filenames or folder structures first.
- **Deep writing & long-form drafting:** Enable *Writing Focus* to dim surrounding paragraphs, keeping your eyes on the sentence you are shaping right now.
- **Scratchpad for code & ideas:** Draft technical notes, checklists, or prose with zero red squiggles or autocorrect getting in the way.
- **Writing on the go:** Keep writing on trains, planes, or off the grid with confidence that your words remain on your device.

---

## Quick Start (For Developers)

### Standalone Web App (Local-Only)

Run the editor locally in your browser with local IndexedDB storage:

```bash
./scripts/install-local-warren.sh
cd apps/loomark
npm ci
npm run build:styles
../../_build/tools/bin/warren dev --direct
```

### Full-Stack (With Optional Sync)

Run the Cloudflare Worker backend alongside the editor:

```bash
cd apps/loomark
cp .env.example .env
npm ci
npm run db:migrate:local
npm run dev:worker
```

### Running Tests

```bash
cd apps/loomark
npm run test:server
npm run typecheck:server
NEW_MOON_MOD=0 moon test --target js -p dowdiness/loomark/server/documents dowdiness/loomark/server/internal/document_store
```

---

## Documentation & Architecture

- **[Documentation Index (docs/README.md)](docs/README.md)** — Overview map of all architecture, operations, and design guides.
- **[Product Vocabulary & Behavior Contract (CONTEXT.md)](CONTEXT.md)** — Canonical terms, UI states, and product design rules.
- **[Technical Architecture (docs/architecture.md)](docs/architecture.md)** — Rabbita structure, incremental parser, viewport mechanics, and DOM lifecycle.
- **[Sync and Account Architecture (docs/sync-and-account.md)](docs/sync-and-account.md)** — Causal replicas, authentication, and conflict recovery.
- **[Production Release Runbook (docs/production.md)](docs/production.md)** — Cloudflare deployment, database migrations, and validation.
