# Development

Guides for working on Canopy itself. For the overall docs reading order, see
the main **[Documentation Index](../README.md)** — this page only indexes the
files inside `docs/development/`.

## API / integration (also useful for users of the library)

- **[API Reference](API_REFERENCE.md)** — high-level MoonBit API overview
  (`SyncEditor`, `ProjNode`, etc.).
- **[JS Integration Guide](JS_INTEGRATION.md)** — using the editor from
  JavaScript / the web.
- **[Tree Editing Manual](TREE_EDIT_MANUAL.md)** — structural projectional
  editing reference.
- **[Adding a Language](ADDING_A_LANGUAGE.md)** — integrate a new language into
  the framework (uses Markdown as the reference implementation).

## Day-to-day contributor workflow

- **[Workflow](workflow.md)** — development process and common commands.
- **[Conventions](conventions.md)** — MoonBit coding standards.
- **[MoonBit Conventions — Examples](moonbit-conventions-examples.md)** —
  concrete patterns referenced from `AGENTS.md`.
- **[Testing](testing.md)** — testing guide and best practices.
- **[Monorepo & Submodules](monorepo.md)** — git submodule setup and daily
  cheat sheet.

## Process and maintenance

- **[Task Tracking](task-tracking.md)** — rules for TODOs, plans, and issues.
- **[Technical Debt](technical-debt.md)** — where debt should be fixed and how
  to retire old paths.
- **[Documentation Doctrine](documentation-doctrine.md)** — how docs in this
  repo are written and maintained.
- **[Move Contract](move-contract.md)** — how nodes are relocated across
  Canopy editors.

## Verification

- **[Formal Verification](formal-verification.md)** — Why3 / z3 proof workflow
  for packages marked `"proof-enabled": true`.
