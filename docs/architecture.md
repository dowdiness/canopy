# Canopy Architecture

Single-page summary of Canopy's stable architectural principles and seams.
Implementation inventory belongs in the live manifests and generated package
overview; longer design reasoning lives under
[docs/architecture/](architecture/).

> If a claim here disagrees with the code, the code wins. Update this file
> rather than the code.

## Pipeline

```
Text CRDT ─► Incremental parse ─► Projection ─► View patches ─► Frontend
   ▲                                                                 │
   └────────────── structural edits feed back ───────────────────────┘
```

1. Durable text state is the source of truth.
2. Incremental parsing derives reusable syntax structure from text changes.
3. Projection derives stable editor identity and language-specific structure.
4. The editor derives view changes; protocol modules serialize the frontend
   boundary.
5. Structural actions become text edits before entering durable state, closing
   the loop.

## Responsibility seams

- The CRDT substrate owns replicated document semantics; Canopy composes it
  rather than reimplementing it.
- The parser substrate owns lossless, incrementally reusable syntax structure.
- Canopy owns projection identity, language behavior, editor state, and the
  protocol-facing view boundary.
- Frontend adapters own rendering and input translation, not parsing or
  replicated-state semantics.
- Language packages own syntax-specific projection and edit calculation, not
  transport or global editor state.

For concrete ownership and placement, use the
[module/package map](development/module-package-map.md). For exhaustive current
inventory, read [`moon.work`](../moon.work), [`.gitmodules`](../.gitmodules),
and `.github/workflows/ci.yml`, or run
[`scripts/package-overview.sh`](../scripts/package-overview.sh).

## Invariants

- **Text is ground truth.** Structural actions are translated into text edits
  before they enter durable replicated state.
- **Derived identity is stable across reparses.** Unchanged structure retains
  identity so interface state does not flicker when nearby text changes.
- **Syntax structure is position-independent.** Relative widths permit
  unchanged subtrees to be reused after edits.
- **The serialized view boundary is explicit.** Frontends consume protocol
  output rather than parser internals or language-specific syntax nodes.
- **Package interfaces protect construction invariants.** Cross-package
  creation goes through intentionally exposed constructors.

## Extension principles

- A new language supplies parsing, projection, and edit behavior while reusing
  the shared editor and protocol seams.
- A new frontend consumes protocol output and translates user input without
  taking ownership of parsing or replicated state.
- A new representation extends language behavior without introducing a
  parallel document model.

See [Adding a Language](development/ADDING_A_LANGUAGE.md) for the current
integration procedure and
[Multi-Representation System](architecture/multi-representation-system.md) for
the representation model.

## Non-goals

- Canopy does not replace its parser, CRDT, or incremental-runtime substrates.
- The core editor is not a general-purpose IDE platform.
- Product transport, provider integration, and frontend rendering remain
  outside the core document and projection semantics.
- Collaborative presence is ephemeral interface state, not predicted durable
  document content.

## Where to read next

- [`docs/architecture/ARCHITECTURE_DIAGRAM.md`](architecture/ARCHITECTURE_DIAGRAM.md)
  — pipeline diagram.
- [`docs/architecture/Incremental-Hylomorphism.md`](architecture/Incremental-Hylomorphism.md)
  — the compositional engine underneath.
- [`docs/architecture/multi-representation-system.md`](architecture/multi-representation-system.md)
  — the `Printable` trait family.
- [`docs/development/ADDING_A_LANGUAGE.md`](development/ADDING_A_LANGUAGE.md)
  — step-by-step to integrate a new language.
- [`docs/development/monorepo.md`](development/monorepo.md) — submodule daily
  workflow.
