# Loomark Documentation Index

Loomark is an easy editor for every day: write in Markdown, read in Preview,
and use Focus Mode to concentrate on the paragraph at hand. Start with the
[product overview](../README.md) or choose a technical guide below.

---

## Documentation Map

Choose the guide that matches your goals:

- **[Product Overview & Vision (apps/loomark/README)](../README.md)**: Product philosophy, writing experience, and interface guide.

```
                  ┌───────────────────────────────┐
                  │       apps/loomark/README     │
                  │  (Product Overview & Vision)  │
                  └──────────────┬────────────────┘
                                 │
         ┌───────────────────────┼───────────────────────┐
         ▼                       ▼                       ▼
┌──────────────────┐   ┌──────────────────┐   ┌──────────────────┐
│    CONTEXT.md    │   │  architecture.md │   │sync-and-account  │
│ Product Language │   │ Technical Design │   │  Replication &   │
│   & Invariants   │   │ & DOM Subsystems │   │  Authentication  │
└──────────────────┘   └─────────┬────────┘   └──────────────────┘
                                 │
                                 ▼
                       ┌──────────────────┐
                       │  production.md   │
                       │ Release, D1, CI  │
                       │   & Validation   │
                       └──────────────────┘
```

---

## Guides

### 1. [Product Language & Behavior Contract (CONTEXT.md)](../CONTEXT.md)
The authoritative glossary of terms, UI invariants, and behavior rules. Read this before modifying UI layouts, document lifecycle states, or terminology.
- **Key topics:** Document identity, Lead extraction, Editor modes, Durability captions, and Deletion safety.

### 2. [Technical Architecture (architecture.md)](architecture.md)
The system architecture of the client application built with Rabbita and MoonBit.
- **Key topics:** Application lifecycle, incremental Markdown preview pipeline, Writing Focus mechanics, `VisualViewport` calculations, and `ResizeObserver` caret tracking.

### 3. [Sync, Authentication, and Replica Storage (sync-and-account.md)](sync-and-account.md)
How Loomark achieves synchronization with explicit conflict recovery without disrupting local-first editing.
- **Key topics:** Google OAuth departure lifecycle, `source/v1` vs. `replica/` IndexedDB records, causal replica state machine, and divergence recovery (atomic forks).

### 4. [Production Release & Validation Runbook (production.md)](production.md)
Operational guide for building, testing, and deploying Loomark to Cloudflare Workers.
- **Key topics:** Cloudflare Workers Builds setup, D1 schema migrations (expand-contract), health check smoke tests, and Playwright E2E verification suites.

---

## Architectural Decision Records (ADRs)

Decisions shaping Loomark's architecture. Read each record's status and
supersession notes before applying it:

- [Current and Saved Text Contract](../../../docs/decisions/2026-08-24-loomark-source-first-interactive-contract.md)
- [Production E2E Boundary](../../../docs/decisions/2026-08-24-loomark-production-e2e-boundary.md)
- [Textarea Edit Boundary](../../../docs/decisions/2026-08-25-loomark-textarea-edit-boundary.md)
- [Document Deletion & Tombstones](../../../docs/decisions/2026-08-31-loomark-document-deletion.md)

## Implementation Plans

- [Standard Rabbita Text App Plan](../../../docs/plans/2026-08-24-loomark-standard-rabbita-text-app.md)
  — active for Text-mode scope; its status notes identify the Preview/Split
  scope moved to another plan and the superseded storage contract.
