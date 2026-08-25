# Context Map

Canopy is a multi-context repository. Each owned context has its own glossary.

## Contexts

- [Loomark](./apps/loomark/CONTEXT.md) — document text, Autosave, browser storage, and Recovery
- [Loom](./deps/loom/CONTEXT.md) — parser core and CST metadata boundaries
- [Event Graph Walker](./deps/event-graph-walker/CONTEXT.md) — event-graph collaborative editing, local undo, and shared-document convergence

## Relationships

The current Loomark application does not depend on Loom or Event Graph Walker.
Loom and Event Graph Walker remain separate framework contexts.
