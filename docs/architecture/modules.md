# Module Structure

Canopy's repository layout expresses four independent concerns. Treating them
as one directory hierarchy is the main source of topology confusion.

## Ownership layers

1. A **MoonBit module manifest** owns package identity, versioning, publication,
   and external dependencies.
2. A **package manifest** defines a compilation unit inside its nearest
   enclosing module.
3. A **workspace file** selects modules for one command context. Membership
   does not imply repository ownership.
4. A **Git submodule entry** assigns a subtree to another repository. A
   submodule may also be a workspace member.

These layers intentionally overlap. For example, a separately owned parser
module can participate in Canopy's root workspace without becoming part of the
`dowdiness/canopy` module or the Canopy Git repository.

## Sources of truth

| Question | Source |
| --- | --- |
| Which module owns a package? | Nearest `moon.mod` or `moon.mod.json`. |
| Which compilation unit owns source files? | Nearest `moon.pkg` or `moon.pkg.json` within that module. |
| Which modules do root commands cover? | Root `moon.work`. |
| Which repository owns a directory? | `.gitmodules` and the nearest Git root. |
| What does a module import? | Its module manifest and package manifests. |
| What is the current combined inventory? | `./scripts/package-overview.sh`. |

Do not maintain complete package, workspace-member, submodule, or dependency
lists in architecture prose. They drift from the manifests. The generated
overview reports the live paths; the
[module/package map](../development/module-package-map.md) explains operational
placement rules.

## Dependency direction

Reusable parsing, CRDT, rendering, and data-structure modules form the substrate.
The primary `dowdiness/canopy` module composes that substrate into projection,
protocol, editor, language, and collaboration packages. Adapters and runnable
applications consume those interfaces.

Dependencies should point toward reusable substrate and must not grow upward
into application code. Code that needs a product runtime, deployment target, or
specific frontend belongs in an adapter or application rather than a reusable
module.

Representative seams:

- `event-graph-walker/` and `loom/` are separately owned substrate repositories.
- `core/`, `editor/`, `projection/`, and `protocol/` are primary-module package
  families.
- `adapters/editor-adapter/` translates primary-module interfaces for
  TypeScript consumers.
- `examples/ideal/` and `examples/canvas/` are runnable applications with their
  own lifecycle and verification.

These examples explain the layers; they are not an inventory.

## Placement test

Before adding a directory, answer in order:

1. Which repository owns and releases it?
2. Which MoonBit module owns its package identity?
3. Is it reusable substrate, primary product logic, an adapter, or a runnable
   application?
4. Which workspace must execute its checks?

If those answers require different owners, use the corresponding existing
seams rather than inferring ownership from a broad folder name such as `lib/`
or `examples/`.
