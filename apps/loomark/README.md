# Loomark

Loomark is a browser Markdown Text editor built with [Rabbita](https://github.com/dowdiness/rabbita).

Read [the product vocabulary and behaviour contract](CONTEXT.md) before changing Loomark.

---

## Architecture

Loomark is one standard Rabbita application in `apps/loomark/app`. Its private `Model`, `Msg`, `update`, and `view` expose one public function:

```moonbit
pub fn app() -> @rabbita.Val[@rabbita.Html]
```

- **Mount point**: `apps/loomark/main/main.mbt` mounts the application into the DOM.
- **Storage reconciliation**: `apps/loomark/app/internal/source_repository` reconciles exact-text Documents and derives an in-memory Catalog through `open`, `save`, and `delete`.
- **Text editing and preview**: `modules/rabbita-markdown/text_area` converts native textarea input sequences into shared `TextChange` operations and drives the incremental Markdown preview engine. Loomark coordinates both.
- **Demand-driven projection**: Recent documents use a keyed projection where `DocumentLead` extraction is retained per document, while visible row rendering is disposed when the sidebar is collapsed.

---

## Quick Start & Development

### Local Browser Editor

To run the client editor locally:

```bash
./scripts/install-local-warren.sh
cd apps/loomark
npm ci
npm run build:styles
../../_build/tools/bin/warren dev --direct
```

### Full-Stack Server & Sync Development

To run with the local Cloudflare Worker backend (Google sign-in, D1 sync):

```bash
cd apps/loomark
cp .env.example .env
# Set BETTER_AUTH_URL=http://localhost:8787 and configure Google OAuth client
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

## Core Features & Guarantees

### Autosave and Recovery

- **Eligibility**: Latest text becomes eligible for save after 250 ms quiet time, when a 2,000 ms maximum-wait timer expires, or when the page is hidden (`visibilitychange`).
- **Composition safety**: IME composition defers persistence until input is committed.
- **Durable authority**: Each `source/v1/<document-id>` record stores only `document_id` and `text`. Text is the sole durable content authority.
- **Failure handling**: Failed local writes preserve current text and offer explicit Retry. Exact return to the acknowledged Source restores `Saved` without redundant writes.

### Import and Export

- **Import**: Accepts strict UTF-8 files, strips initial UTF-8 BOM, normalizes line endings (CRLF/CR → LF), and preserves all other characters. Automatically creates and activates a fresh document.
- **Export**: Instantly downloads current in-memory text as `<Derived name>.md` (or `untitled.md` as fallback) without waiting for background autosave.

### Cloud Sync and Google Sign-In

- Google authentication via Better Auth in TypeScript Worker dispatch, coupled with typed MoonBit server handlers.
- Causal replica state machine in IndexedDB with atomic conflict recovery (`Diverged` → `Fork`).
- Local editing and autosave remain fully functional offline or while waiting for account network requests.

---

## Documentation Index

- [Product Vocabulary & Contract (CONTEXT.md)](CONTEXT.md) — canonical product language, definitions, and behavioral invariants.
- [Sync and Account Service Guide (docs/sync-and-account.md)](docs/sync-and-account.md) — in-depth specification of Better Auth, replica persistence state machines, conflict recovery, and discovery protocols.
- [Production Release and Validation Guide (docs/production.md)](docs/production.md) — Cloudflare Workers release procedures, D1 migrations, Playwright E2E tests, and demand verification.

### Architectural Decisions (ADRs)

- [Standard Rabbita Text App plan](../../docs/plans/2026-08-24-loomark-standard-rabbita-text-app.md)
- [Current and saved text](../../docs/decisions/2026-08-24-loomark-source-first-interactive-contract.md)
- [Production E2E boundary](../../docs/decisions/2026-08-24-loomark-production-e2e-boundary.md)
- [Textarea edit boundary](../../docs/decisions/2026-08-25-loomark-textarea-edit-boundary.md)
- [Document deletion](../../docs/decisions/2026-08-31-loomark-document-deletion.md)
