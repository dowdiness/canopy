# Loomark Rabbita application structure plans

Generated on 2026-08-24 for the dedicated `docs/loomark-rabbita-improvement-plan` worktree. Execute in order. Each executor must read its plan fully, honor STOP conditions, and update its status here.

This plan set intentionally excludes [#1353](https://github.com/dowdiness/canopy/issues/1353), performance attribution, and operation-based input work. Those belong to another session. The objective here is to make Loomark a better-structured Rabbita application without changing product behavior.

## Execution order and status

| Plan | Title | Priority | Effort | Depends on | Status |
| --- | --- | --- | --- | --- | --- |
| 001 | [Give the Rabbita application one file per responsibility](001-decompose-loomark-rabbita-application.md) | P1 | M | — | DONE |
| 002 | [Deepen the Rabbita root seam](002-deepen-loomark-rabbita-root-seam.md) | P1 | L | 001 | DONE |

Status values: TODO | IN PROGRESS | DONE | BLOCKED | REJECTED.

## Selected structure

```text
application_mount
  └─ application(ApplicationProfile, resources)
       ├─ create_state_with_init
       ├─ application_update
       │    └─ Editing / Navigation / Probe / Lifecycle / Bootstrap / Archive
       ├─ application_subscriptions
       ├─ application_view + split_view
       └─ application_observability

ApplicationProfile
  ├─ standalone(StandaloneBootstrapMode)
  └─ private_dev_host()

internal/dev_host adapter
  └─ compact private wire seam
       └─ typed DriverEvent inside the Rabbita package
```

The root reducer remains atomic. Files provide locality inside one MoonBit package; the private `ApplicationProfile` value provides the real two-adapter seam. Its two private constructors are the only places that bind bootstrap, subscription, and outer-view behavior. Neither plan creates child state machines, new packages, or new rendering branches.

## Why this direction

- Rabbita documents an application in terms of typed messages, update plus commands, declarative subscriptions, ordinary/named view functions, and one graph-building root. Loomark already follows those semantics but hides them inside a 3,572-line file.
- MoonBit files can be reorganized within a package without creating interfaces. A package split would force private type exposure or constructors before a second production adapter exists.
- The current callback-injected `build_application` makes callers learn internal model/event/view/subscription details. A closed profile hides those decisions behind one deeper root interface.
- Production standalone and private dev host are two real adapters. Their difference should be a value at one seam, not function-valued plumbing spread across mount, view, and subscription code.
- The separate `internal/dev_host` JS adapter is real, but its current one-function-per-control forwarding makes the Rabbita package interface shallow. A compact string-wire seam preserves typed decoding inside the application while shrinking the cross-package interface.

## Dependency notes

- Plan 001 must land first because it proves a behavior-neutral responsibility layout and gives Plan 002 local edit targets.
- Plan 002 must not be merged into Plan 001. File movement and interface deepening need separate review evidence.
- If Plan 001 finds missing characterization coverage, stop and add that coverage before Plan 002.

## Findings considered and rejected

- **Run #1353 first:** excluded by user direction; it is active in another session and does not own this structural refactor.
- **Upgrade Rabbita before refactoring:** rejected; the workspace already builds the pinned `0.15.4` fork. A future upstream sync is a separate fork-rebase.
- **Add broad `Val` islands:** rejected for this plan set. Loomark already uses `Val::view2` and `switch`, and retained evidence does not identify view materialization as the structural problem.
- **Split the root into feature child states:** rejected. Shared editor, recovery, persistence, projection, and stale-result decisions currently need one atomic parent transition.
- **Move Worker or persistence ownership into view branches:** rejected because `switch` disposes replaced branches.
- **Use `create_state_with_input` for projection/persistence children:** rejected because parent input changes alone do not run child update or refresh child subscriptions.
- **Split `internal/rabbita` into new MoonBit packages first:** rejected. Current private types and cyclic responsibilities would require interface widening for an organizational gain files already provide.
- **Copy Mooncakes' Vite layout:** rejected. Loomark's deployment interface is Warren direct-mode static output.
- **Rename every `DriverModel`/`DriverEvent` reference immediately:** deferred. Naming churn is easier to judge after product and dev-host construction seams are explicit.

## Supporting evidence

- [Rabbita external second pass](evidence/2026-08-24-external-rabbita-second-pass.md)
- `deps/rabbita/rabbita/README.mbt.md`
- `deps/rabbita/doc/component_and_incremental/readme.mbt.md`
- `deps/rabbita/doc/004_using_command/readme.mbt.md`
- `deps/rabbita/doc/using_subscriptions/readme.mbt.md`
- `apps/loomark/internal/rabbita/application.mbt` at planned commit `60ef805c`
- `apps/loomark/internal/rabbita/driver_types.mbt` at planned commit `60ef805c`
- `apps/loomark/internal/rabbita/split_view.mbt` at planned commit `60ef805c`
- `apps/loomark/internal/dev_host/dev_host.mbt` at planned commit `60ef805c`
- historical refactors `d8883135` and `39554fac`

Context7 has no Rabbita catalog entry as of this review. Rabbita-specific claims were therefore checked against the pinned vendored source, its official docs, and upstream primary sources. Current MoonBit CLI path-selection syntax was checked against Context7 and the installed `moon --help` output.
