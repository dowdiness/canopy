# Loomark

A browser Markdown editor built with [Rabbita](https://github.com/dowdiness/rabbita), designed around one core principle: **the text you type is the only source of truth.**

Loomark pairs a native textarea with an incremental Markdown preview engine. It works completely offline with local-first IndexedDB autosave, and optionally syncs across devices through a Cloudflare Worker backed by D1 and Google sign-in.

Read [the product vocabulary and behaviour contract](CONTEXT.md) before making product or architectural changes.

---

## How It Works

Loomark is structured as a standard Rabbita application in `apps/loomark/app`, exposing a single entry point:

```moonbit
pub fn app() -> @rabbita.Val[@rabbita.Html]
```

- **Editing & Preview:** Native `<textarea>` inputs flow into `modules/rabbita-markdown/text_area`, which produces minimal `TextChange` diffs and drives the incremental preview without lag.
- **Local Storage:** `apps/loomark/app/internal/source_repository` reconciles exact document text against IndexedDB, deriving an in-memory catalog on startup.
- **Demand-Driven Sidebar:** Recent documents extract a lightweight `DocumentLead` (the first meaningful heading or line) on the fly, rendering rows only when the sidebar opens.

---

## Quick Start & Development

### Standalone Web App

Run the editor locally in the browser with local IndexedDB storage:

```bash
./scripts/install-local-warren.sh
cd apps/loomark
npm ci
npm run build:styles
../../_build/tools/bin/warren dev --direct
```

### Full-Stack (With Google Sign-In & D1 Sync)

Run the local Cloudflare Worker backend alongside the editor:

```bash
cd apps/loomark
cp .env.example .env
# Set BETTER_AUTH_URL=http://localhost:8787 and configure your Google OAuth client
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

For release and end-to-end browser validation, see [Production and Validation](docs/production.md).

---

## Core Invariants

- **Text is truth:** Documents are stored simply as `(document_id, text)`. There is no hidden AST metadata, no proprietary JSON blob, and no lossy serialization.
- **Non-blocking autosave:** Edits persist after 250 ms of quiet time, at most every 2,000 ms, or immediately when the browser tab hides (`visibilitychange`). Active IME composition always defers saving until committed.
- **Clean import & export:** Import decodes strict UTF-8, strips BOMs, normalizes line breaks (`\n`), and never alters your characters. Export downloads the current text in memory on demand.
- **Offline-first sync:** You can write freely without an internet connection. When connected, changes sync via causal replica state machines with atomic conflict recovery (`Fork` on divergence).

---

## Deep Dives

- [Product Vocabulary & Contract (CONTEXT.md)](CONTEXT.md) — Canonical definitions, UI states, and behavioral invariants.
- [Sync and Account Architecture (docs/sync-and-account.md)](docs/sync-and-account.md) — Causal replicas, Google OAuth lifecycle, conflict forks, and discovery protocol.
- [Production Release & Validation Runbook (docs/production.md)](docs/production.md) — Cloudflare Workers deployment, D1 schema migrations, and Playwright verification.

### Architectural Decisions (ADRs)

- [Standard Rabbita Text App plan](../../docs/plans/2026-08-24-loomark-standard-rabbita-text-app.md)
- [Current and saved text](../../docs/decisions/2026-08-24-loomark-source-first-interactive-contract.md)
- [Production E2E boundary](../../docs/decisions/2026-08-24-loomark-production-e2e-boundary.md)
- [Textarea edit boundary](../../docs/decisions/2026-08-25-loomark-textarea-edit-boundary.md)
- [Document deletion](../../docs/decisions/2026-08-31-loomark-document-deletion.md)
