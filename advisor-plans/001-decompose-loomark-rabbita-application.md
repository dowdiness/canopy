# Plan 001: Give the Loomark Rabbita application one file per responsibility

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If a STOP condition occurs, stop and report; do not improvise.
> This is a behavior-preserving organizational refactor. Do not introduce new
> state, messages, effects, `Val` nodes, packages, or public functions.
>
> **Drift check (run first)**:
> `git diff --stat 60ef805c..HEAD -- apps/loomark/internal/rabbita apps/loomark/internal/dev_host apps/loomark/examples/vanilla`
> If any in-scope file changed, compare the current symbols and line groups in
> this plan with the live code. A moved, renamed, or semantically changed group
> is a STOP condition until the plan is refreshed.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: MED — declarations move across files in one JS-only MoonBit package; behavior must remain byte-for-byte equivalent at its public and browser seams
- **Depends on**: none
- **Category**: tech-debt
- **Planned at**: commit `60ef805c`, 2026-08-24

## Why this matters

`apps/loomark/internal/rabbita/application.mbt` is 3,572 lines and owns six different Rabbita responsibilities: view construction, update routing, subscriptions, root graph construction, mounting, and the private browser-driver protocol. MoonBit files are organizational units within a package, so moving private declarations can improve locality without adding package interfaces or runtime indirection. This plan makes the application readable in the same terms as Rabbita's documented model—messages, update, commands, subscriptions, view, and root mounting—while preserving the single atomic root reducer.

This is prerequisite structure, not an optimization. Existing presentation evidence does not justify new `Val` islands, and #1353 is being handled independently.

## Current state

### Package and public interface

- `apps/loomark/internal/rabbita/moon.pkg` defines one JS-only package containing all application internals.
- `apps/loomark/internal/rabbita/pkg.generated.mbti` is the public-interface baseline. It includes production mounts, projection-worker dispatch, and private dev-host controls.
- `apps/loomark/internal/dev_host/dev_host.mbt` is the separate JS-link adapter. Plan 001 must not change it.

### Existing responsibility groups

At planned commit `60ef805c`, `application.mbt` contains these groups:

| Current symbols | Current location | Destination |
| --- | --- | --- |
| `read_textarea_value`, example constants, `mode_icon`, `current_preview_source`, Raw/editor/Preview/outer views | `application.mbt:10-184`, `427-885` | `application_view.mbt` |
| `detached_snapshot`, `mode_name`, runtime/error/persistence snapshot helpers, `publish`, `driver_event_name` | `application.mbt:7`, `186-426`, `886-964` | `application_observability.mbt` |
| private wire parsing and `dispatch_driver` | `application.mbt:965-1087` | `dev_host_protocol.mbt` |
| archive, editing, navigation, probe, lifecycle, root update, and runtime synchronization | `application.mbt:1089-2808` | `application_update.mbt` |
| custom subscription loaders and standalone/dev-host subscription declarations | `application.mbt:2810-3008` | `application_subscriptions.mbt` |
| `build_application`, `standalone_application`, `private_dev_host_application` | `application.mbt:3011-3220` | `application_root.mbt` |
| `mounted`, `initial_model`, mount helpers, production/oracle/dev-host mount functions | `application.mbt:1-4`, `3222-3421` | `application_mount.mbt` |
| private browser assertion/control functions from `snapshot` through `fail` | `application.mbt:3423-3572` | `dev_host_api.mbt` |

The exact line numbers are drift aids, not edit ranges. Move declarations by symbol and re-read the source immediately before each edit.

### Architectural constraints

- Keep one `DriverModel` and one `DriverEvent` root. Existing sub-enums already make update routing total.
- Keep worker, Raw Preview, persistence, and browser coordinators owned by the root imperative shell.
- Preserve the current `application_view` graph and `SplitPresentation::switch`; do not add `assoc`, `enumerate`, `switch`, `lazy`, or new projections.
- Preserve standalone and private-dev-host behavior, including their different view and subscription functions.
- Do not split the MoonBit package. Cross-package construction would either expose private types or require new constructors and would turn an organizational refactor into an interface migration.
- Preserve Functional Core / Imperative Shell: feature decision modules remain deterministic where they already are; DOM, timers, Workers, persistence, and mutable refs remain in the Rabbita shell.

## Commands you will need

| Purpose | Command | Expected on success |
| --- | --- | --- |
| Format check | `moon fmt --check apps/loomark/internal/rabbita` | exit 0, no formatting diff |
| Targeted check | `moon check apps/loomark/internal/rabbita --target js` | exit 0, no diagnostics |
| Targeted tests | `moon test apps/loomark/internal/rabbita --target js --release` | exit 0, all selected tests pass |
| Interface regeneration | `moon info` | exit 0 |
| Dev-host browser gate | `./scripts/test-loomark-dev-host-e2e.sh` | exit 0, Playwright suite passes |
| Standalone browser gate | `./scripts/test-loomark-standalone-e2e.sh` | exit 0, direct/release checks and Playwright suite pass |
| Final repository gate | `./scripts/validate-pr-ready.sh --target apps/loomark/internal/rabbita` | exit 0 on clean candidate HEAD |

Use a login shell so `NEW_MOON_MOD=0` and the required Node version are active.

## Suggested executor toolkit

- Read `deps/rabbita/rabbita/README.mbt.md`, `deps/rabbita/doc/component_and_incremental/readme.mbt.md`, `deps/rabbita/doc/004_using_command/readme.mbt.md`, and `deps/rabbita/doc/using_subscriptions/readme.mbt.md` before editing.
- Use the MoonBit refactoring workflow and `moon ide find-references` before moving or renaming a symbol.
- Use `rg` to confirm each declaration has exactly one definition after every move.
- Use one file per edit call as required by repository guidance.

## Scope

**In scope:**

- Delete `apps/loomark/internal/rabbita/application.mbt` only after all its declarations have been moved.
- Add `apps/loomark/internal/rabbita/application_view.mbt`.
- Add `apps/loomark/internal/rabbita/application_observability.mbt`.
- Add `apps/loomark/internal/rabbita/dev_host_protocol.mbt`.
- Add `apps/loomark/internal/rabbita/application_update.mbt`.
- Add `apps/loomark/internal/rabbita/application_subscriptions.mbt`.
- Add `apps/loomark/internal/rabbita/application_root.mbt`.
- Add `apps/loomark/internal/rabbita/application_mount.mbt`.
- Add `apps/loomark/internal/rabbita/dev_host_api.mbt`.
- Regenerate `apps/loomark/internal/rabbita/pkg.generated.mbti`; its semantic content must remain unchanged.

**Out of scope:**

- `apps/loomark/internal/rabbita/driver_types.mbt` and every existing feature-specific file.
- `apps/loomark/internal/dev_host/**`.
- `apps/loomark/main/**`.
- Type or function renames, visibility changes, new helpers, new tests, state grouping, message regrouping, or error changes.
- Rabbita dependency or submodule changes.
- `Val` graph, view HTML, CSS, subscription keys, command kinds/order, timer values, mount semantics, persistence behavior, and performance instrumentation.
- #1351, #1353, #1347, and any operation-based editing work.

## Git workflow

- Create or refresh a dedicated worktree whose HEAD contains current `origin/main`.
- Suggested branch: `refactor/loomark-rabbita-application-files`.
- Use conventional commits; examples in history include `refactor(loomark): split application responsibilities` and `refactor(loomark): decompose update_model into concern sub-dispatchers`.
- Prefer one commit per coherent move group while keeping the package green after every commit.
- Do not push or open a PR unless instructed.

## Reuse check

This plan introduces no function, method, helper, type, or package. It reuses:

- the existing `DriverModel`, `DriverEvent`, and concern sub-enums;
- the existing `update_model` and root Rabbita `create_state_with_init` flow;
- the existing named view, subscription, mount, and private driver functions;
- the package's existing private visibility, avoiding any new cross-package interface.

No MoonBit collection or string manipulation is added. Existing imperative code is moved unchanged because it owns DOM, subscription, Worker, mount, or browser-driver effects.

## Steps

### Step 1: Freeze the baseline

Before moving code:

1. Save `apps/loomark/internal/rabbita/pkg.generated.mbti` outside the repository or record its SHA-256.
2. Record `rg` results for every function listed in the current-state table.
3. Run targeted check and targeted release tests.
4. Run both browser gates if the worktree has not already established a current-main baseline.

**Verify:**

```bash
moon check apps/loomark/internal/rabbita --target js
moon test apps/loomark/internal/rabbita --target js --release
sha256sum apps/loomark/internal/rabbita/pkg.generated.mbti
```

Expected: both MoonBit commands exit 0 and one interface hash is recorded.

### Step 2: Move pure view construction

Create `application_view.mbt` and move only the example constants and view functions listed for that destination. Preserve declaration bodies, comments, names, parameter order, HTML tree order, attributes, style strings, and command construction exactly.

Do not move `application_view` from `split_view.mbt`; that file already owns split-presentation graph construction. `application_view.mbt` owns ordinary `Html` construction consumed by that graph.

**Verify:**

```bash
moon fmt --check apps/loomark/internal/rabbita/application_view.mbt
moon check apps/loomark/internal/rabbita --target js
rg -n '^(fn|const) (raw_editor_view|editor_view|preview_view|standalone_preview_view|private_dev_host_preview_view|HELLO_EXAMPLE_SOURCE)' apps/loomark/internal/rabbita
```

Expected: format/check exit 0; every named declaration has exactly one definition, in `application_view.mbt`.

### Step 3: Move observability and private wire code

Create `application_observability.mbt` for snapshot/publication helpers and `dev_host_protocol.mbt` for `parse_driver_event` plus `dispatch_driver`. Keep the current JSON field names, event-name strings, detached refs, and CustomEvent protocol unchanged.

`record_error` belongs with observability because all update concerns reuse its normalized diagnostic fields. Do not create an observability type or adapter in this plan.

**Verify:**

```bash
moon fmt --check apps/loomark/internal/rabbita/application_observability.mbt apps/loomark/internal/rabbita/dev_host_protocol.mbt
moon check apps/loomark/internal/rabbita --target js
rg -n '^fn (publish|record_error|driver_event_name|parse_driver_event|dispatch_driver)' apps/loomark/internal/rabbita
```

Expected: exit 0; one definition per symbol in the planned destination.

### Step 4: Move update and subscription ownership

Create `application_update.mbt` and move the existing update chain unchanged, from `update_archive_queue` through `update_model_with_raw_preview_runtime`. Create `application_subscriptions.mbt` and move the custom loaders and subscription declarations unchanged.

Keep `update_model` as the total routing table. Do not merge the concern reducers and do not introduce an umbrella lifecycle enum. Keep custom subscription keys, locality, payload types, unload order, and `update_tagger` behavior byte-for-byte equivalent.

**Verify:**

```bash
moon fmt --check apps/loomark/internal/rabbita/application_update.mbt apps/loomark/internal/rabbita/application_subscriptions.mbt
moon check apps/loomark/internal/rabbita --target js
moon test apps/loomark/internal/rabbita --target js --release
rg -n '^fn (update_model|update_editing|update_navigation|update_probe|update_lifecycle|standalone_subscriptions|private_dev_host_subscriptions)' apps/loomark/internal/rabbita
```

Expected: all commands exit 0 and every symbol is defined once in the intended file.

### Step 5: Move root graph and mount ownership

Create `application_root.mbt` for `build_application`, `standalone_application`, and `private_dev_host_application`. Create `application_mount.mbt` for initialization and mount functions. Move the dev-host assertion/control wrappers to `dev_host_api.mbt`.

Preserve the current root order:

1. create session refs and coordinators;
2. construct optional Worker runtimes;
3. compose subscriptions;
4. execute update and recovery handling;
5. synchronize projection and Raw Preview commands;
6. call `create_state_with_init`;
7. create `application_view`;
8. combine model and active view with `view2`;
9. mount once.

Do not replace callback injection or optional profile values here; Plan 002 owns that semantic deepening after the moves are proven behavior-neutral.

**Verify:**

```bash
moon fmt --check apps/loomark/internal/rabbita/application_root.mbt apps/loomark/internal/rabbita/application_mount.mbt apps/loomark/internal/rabbita/dev_host_api.mbt
moon check apps/loomark/internal/rabbita --target js
rg -n '^fn (build_application|standalone_application|private_dev_host_application|initial_model|mount_application|mount_standalone_with_mode)' apps/loomark/internal/rabbita
rg -n '^pub fn (mount_standalone|mount_full_history_oracle|mount|snapshot|request_source|fail)' apps/loomark/internal/rabbita
```

Expected: exit 0; definitions are unique and located in root, mount, or dev-host API files as specified.

### Step 6: Remove the emptied monolith and prove interface identity

Once `application.mbt` contains no declarations, delete it. Run formatter on the package, regenerate interfaces, and compare the generated `.mbti` with the recorded baseline.

**Verify:**

```bash
test ! -e apps/loomark/internal/rabbita/application.mbt
moon fmt apps/loomark/internal/rabbita
moon check apps/loomark/internal/rabbita --target js
moon test apps/loomark/internal/rabbita --target js --release
moon info
git diff -- apps/loomark/internal/rabbita/pkg.generated.mbti
```

Expected: all commands exit 0; the `.mbti` diff is empty. If formatting changes moved declarations, those changes must be formatting-only.

### Step 7: Run browser and clean-HEAD gates

Run both browser suites because the refactor crosses production mount/view/subscription and private-driver mount/protocol paths.

**Verify:**

```bash
./scripts/test-loomark-dev-host-e2e.sh
./scripts/test-loomark-standalone-e2e.sh
git diff --check
git diff --stat
```

Expected: both suites exit 0; no whitespace errors; only the in-scope deletion/additions and unchanged generated interface appear.

After independent review, fetch `origin/main`, sync if required, commit the candidate, and run:

```bash
./scripts/validate-pr-ready.sh --target apps/loomark/internal/rabbita
```

Immediately before PR work:

```bash
git fetch origin main
./scripts/validate-pr-ready.sh --verify-evidence
```

Expected: both validator commands exit 0 against the exact committed candidate.

## Test plan

No new tests are expected because no observable behavior or interface changes. The proof is layered:

- targeted MoonBit release tests cover deterministic reducers, coordinators, projection, recovery, and SSR views;
- the dev-host Playwright suite covers the private wire, typed dispatch, commands, subscriptions, focus, selection, failure injection, and browser timing;
- the standalone suite covers production Warren output, boot, persistence, Raw editing, and absence of private controls;
- the generated `.mbti` must remain semantically unchanged.

If any moved declaration lacks existing coverage and its behavior cannot be proven by the two browser suites, STOP and propose a separate characterization-test plan instead of adding tests during the move.

## Done criteria

- [ ] `application.mbt` no longer exists.
- [ ] Every responsibility group is in its named file and every moved symbol has exactly one definition.
- [ ] No declaration body, name, visibility, parameter order, or effect ordering changed except formatter output.
- [ ] `moon fmt --check apps/loomark/internal/rabbita` exits 0.
- [ ] targeted JS check and release tests exit 0.
- [ ] `moon info` produces no semantic `.mbti` diff.
- [ ] both Loomark browser suites exit 0.
- [ ] no files outside Scope are modified.
- [ ] clean-HEAD PR-ready validation succeeds.

## STOP conditions

Stop and report if:

- any listed symbol has moved or changed since `60ef805c`;
- moving a declaration requires changing visibility, adding a helper, or editing another package;
- MoonBit file ordering affects initialization or JS linking in a way that cannot be preserved by a direct move;
- generated `.mbti` changes semantically;
- either browser suite changes snapshots, event strings, command order, subscription counts, DOM, or timing behavior;
- the working tree contains unrelated edits overlapping the scoped package;
- a validation command fails twice after correcting a mechanical move error.

## Maintenance notes

Plan 002 assumes these responsibility files exist and will deepen the application-construction seam without redistributing them. Reviewers should reject opportunistic cleanup in this plan: the value is a trustworthy behavior-neutral layout that makes later changes local and reviewable. Keep architecture docs principle-only; do not add a document that merely enumerates these filenames.
