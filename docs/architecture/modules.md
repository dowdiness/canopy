# Module Structure

Canopy's repository layout expresses independent concerns through seven zones.
Treating them as one directory hierarchy is the main source of topology
confusion.

## Zones

| Zone | Path | Purpose |
|------|------|---------|
| Modules | `modules/` | Reusable, publishable MoonBit modules; includes the primary `modules/canopy` |
| Applications | `apps/` | Runnable or deployable vertical slices |
| Examples | `examples/` | Removable learning and integration examples |
| Adapters | `adapters/` | Non-MoonBit runtime and interface adapters |
| Dependencies | `deps/` | Separately owned Git submodules |
| Rules | `rules/` | Policy definitions |
| Scripts | `scripts/` | Operations and tooling |

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
module under `deps/` can participate in Canopy's root workspace without
becoming part of the `dowdiness/canopy` module or the Canopy Git repository.

## Sources of truth

| Question | Source |
| --- | --- |
| Which module owns a package? | Nearest `moon.mod` or `moon.mod.json`. |
| Which compilation unit owns source files? | Nearest `moon.pkg` or `moon.pkg.json` within that module. |
| Which modules do root commands cover? | Root `moon.work`. |
| Which repository owns a directory? | `.gitmodules` and the nearest Git root. |
| What does a module import? | Its module manifest and package manifests. |
| What is the current combined inventory? | `moon.work`, `.gitmodules`, and the nearest module/package manifests. |

Do not maintain complete package, workspace-member, submodule, or dependency
lists in architecture prose. They drift from the manifests. The
[module/package map](../development/module-package-map.md) explains how to read
the authoritative manifests and apply the operational placement rules.

## Placement principles

1. **Reusable substrate or product logic?** Reusable, publishable MoonBit
   modules go in `modules/`. The primary `modules/canopy` module composes
   substrate into projection, protocol, editor, language, and collaboration
   packages.
2. **Runnable or deployable?** Vertical slices that run or deploy go in
   `apps/`. Some apps (Canvas) own a nested workspace.
3. **Learning or integration example?** Removable examples go in `examples/`.
4. **Non-MoonBit runtime or interface bridge?** Adapters go in `adapters/`.
5. **Separately owned library?** Git submodules go in `deps/`.

## Dependency direction

Reusable parsing, CRDT, rendering, and data-structure modules form the
substrate. Substrate lives in `deps/` (separately owned) or `modules/`
(Canopy-owned reusable libraries). The primary `modules/canopy` module
composes that substrate into projection, protocol, editor, language, and
collaboration packages. Adapters and runnable applications in `apps/` consume
those interfaces.

Dependencies point toward reusable substrate and must not grow upward into
application code. Code that needs a product runtime, deployment target,
document lifetime, or a specific frontend belongs in an adapter or
application rather than a reusable module. Submodules under `deps/` never
grow upward dependencies on the primary module. How session, collaboration,
and document authority nest is in the
[composition map](ARCHITECTURE_DIAGRAM.md).

Representative seams:

- `deps/event-graph-walker/` and `deps/loom/` are separately owned substrate
  repositories.
- `modules/canopy/core/`, `modules/canopy/editor/`,
  `modules/canopy/projection/`, and `modules/canopy/protocol/` are
  primary-module package families.
- `adapters/editor/` translates primary-module interfaces for
  TypeScript consumers.
- `apps/ideal/` and `apps/canvas/` are runnable applications with their
  own lifecycle and verification.

These examples explain the layers; they are not an inventory.

## Placement test

Before adding a directory, answer in order:

1. Which zone does it belong in?
2. Which repository owns and releases it?
3. Which MoonBit module owns its package identity?
4. Is it reusable substrate, primary product logic, an adapter, or a runnable
   application?
5. Which workspace must execute its checks?

If those answers require different owners, use the corresponding zone rather
than inferring ownership from a broad folder name.
