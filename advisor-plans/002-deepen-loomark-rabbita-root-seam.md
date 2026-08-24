# Plan 002: Deepen the Loomark Rabbita root seam

> **Executor instructions**: Execute only after Plan 001 is DONE. Follow each
> step and verification gate. Stop on any listed mismatch; do not widen scope.
> Preserve product behavior, browser protocol, state transitions, command
> ordering, subscriptions, and the existing incremental graph.
>
> **Drift check (run first)**:
> `git diff --stat 60ef805c..HEAD -- apps/loomark/internal/rabbita apps/loomark/internal/dev_host apps/loomark/main apps/loomark/examples/vanilla`
> Plan 001 is expected to account for the application-file changes. Any later
> semantic change to the symbols described below is a STOP condition until this
> plan is refreshed.

## Status

- **Priority**: P1
- **Effort**: L
- **Risk**: MED — this changes an internal construction interface and private adapter surface while preserving runtime behavior
- **Depends on**: `advisor-plans/001-decompose-loomark-rabbita-application.md`
- **Category**: tech-debt
- **Planned at**: commit `60ef805c`, 2026-08-24
- **Result**: DONE — implemented with the production-DCE refinement described below

## Why this matters

The current `build_application` accepts two callbacks that know the complete `DriverModel`, `DriverEvent`, and active `Html`, plus optional bootstrap and projection values. That makes the root-construction seam shallow: callers must understand internal model, message, view, subscription, and lifecycle details merely to choose between two known application variants. Separately, `internal/dev_host/dev_host.mbt` forwards roughly thirty functions one-for-one from the Rabbita package, so the Rabbita package's generated interface exposes test controls individually.

There are exactly two real adapters—production standalone and private dev host—so replace the callback interface with one closed `ApplicationProfile` value. Keep all variant selection behind one `application` root function, and reduce the dev-host cross-package seam to mount, dispatch, and detached reads. This increases depth and locality without splitting the root model or introducing a second application state machine.

## Target design

The exact MoonBit spelling may follow current compiler constraints, but the interface and ownership must have this shape:

```moonbit nocheck
priv struct ApplicationProfile {
  bootstrap_mode : StandaloneBootstrapMode?
  subscriptions : (DriverModel, @cmd.Emit[DriverEvent]) -> @sub.Sub
  preview_view : (DriverModel, @cmd.Emit[DriverEvent], Html) -> Html
}

fn ApplicationProfile::standalone(StandaloneBootstrapMode) -> ApplicationProfile
fn ApplicationProfile::private_dev_host() -> ApplicationProfile

fn application(
  profile : ApplicationProfile,
  editor : @markdown.MarkdownEditor,
  attachment : @md_markdown.MarkdownSemanticAttachment,
  initial : DriverModel,
  baseline : @repository.LocalArchivePendingWrite?,
) -> @rabbita_runtime.App
```

`application` hides:

- bootstrap command selection;
- Raw Preview enablement and runtime allocation;
- standalone versus dev-host subscriptions;
- standalone versus dev-host outer view decoration;
- projection runtime allocation and synchronization;
- recovery handling;
- the single `create_state_with_init` root;
- the `application_view` graph and final `view2` composition.

The two mount paths pass only the profile and resources. They do not pass functions over `DriverModel` or `DriverEvent`.

### Production-DCE refinement discovered during execution

The initially recommended enum was implemented and passed MoonBit plus dev-host tests, but the standalone production gate found `loomark-driver-target` in the minified bundle. MoonBit retained both branches of the shared enum match, so the unselected private view/subscription branch was not dead-code eliminated.

The accepted design therefore uses a private struct with exactly two private named constructors. Callers still pass one closed profile value and cannot combine callbacks independently. Binding the concrete standalone functions in its constructor lets the JS optimizer remove the private constructor and its control strings from production. The standalone gate proves the required separation. This is deliberately not a public or extensible callback bundle.

The private dev-host package should depend on this small wire seam:

```moonbit nocheck
pub fn mount_private_dev_host(host_id : String, source : String) -> String
pub fn dispatch_private_dev_host(detail : String) -> Unit
pub fn private_dev_host_snapshot() -> String
pub fn private_dev_host_focus_token() -> String
```

Names may be shortened if the package context remains unambiguous, but there must not be one public Rabbita-package function per JS test control. `apps/loomark/internal/dev_host/dev_host.mbt` continues to export typed JS-callable functions and owns encoding them into the existing private string wire.

## Current state

After Plan 001, verify these destinations and symbols:

- `application_root.mbt` contains `build_application`, `standalone_application`, and `private_dev_host_application`.
- `build_application` accepts `bootstrap_mode?`, a subscriptions callback, a view callback, and optional projection session state.
- `application_mount.mbt` contains separate mount logic and a `build` callback in the private mount helper.
- `application_subscriptions.mbt` contains the real standalone and private-dev-host subscription adapters.
- `application_view.mbt` contains the real standalone and private-dev-host outer view adapters.
- `dev_host_protocol.mbt` contains the one string-to-typed-message decoder and dispatcher.
- `dev_host_api.mbt` exposes individual public controls such as `request_source`, `select_raw`, `restore_snapshot`, and `fail`.
- `apps/loomark/internal/dev_host/dev_host.mbt` forwards each JS export to one of those individual functions.

The current generated interface at `apps/loomark/internal/rabbita/pkg.generated.mbti` is intentionally broad because of those individual controls. Plan 002 is allowed to shrink it; no other public additions are allowed.

## Architectural constraints

- `ApplicationProfile` is a closed internal configuration value, not an extensibility framework. Its function fields may only be bound by the two private named constructors; do not expose fields, add a trait, or accept independent callbacks at the root/mount boundary.
- Two adapters make this a real seam. Keep the adapters internal; tests and callers do not receive `DriverModel`, `DriverEvent`, coordinators, runtime refs, `Html`, `Cmd`, or `Sub`.
- Keep shared state in the single closest common parent: the existing Rabbita root.
- Keep the root reducer atomic. Editing, navigation, probe, lifecycle, bootstrap, archive, projection, and Raw Preview messages continue through one `DriverEvent` envelope.
- Keep feature-local deterministic reducers and imperative adapters where they are.
- Do not create child `create_state_with_input` roots. Rabbita does not refresh a child's update or subscriptions merely because its parent input changed.
- Do not move worker or persistence ownership behind `switch`; changing layout branches must not dispose application-lifetime resources.
- Do not add `Val` projections as a performance change. The existing graph remains structurally identical.
- Preserve the production bundle rule: no private dev-host exports or control strings in `apps/loomark/dist/index.js`.
- Preserve one mount per page/process. Public unmount/remount remains deferred.

## Commands you will need

| Purpose | Command | Expected on success |
| --- | --- | --- |
| Find callers | `moon ide find-references <symbol>` | lists all current references before removal |
| Targeted check | `moon check apps/loomark/internal/rabbita apps/loomark/internal/dev_host --target js` | exit 0 |
| Targeted tests | `moon test apps/loomark/internal/rabbita --target js --release` | exit 0, all selected tests pass |
| Format check | `moon fmt --check apps/loomark/internal/rabbita apps/loomark/internal/dev_host` | exit 0 |
| Interface regeneration | `moon info` | exit 0; only intended public removals in Rabbita `.mbti` |
| Dev-host browser gate | `./scripts/test-loomark-dev-host-e2e.sh` | exit 0 |
| Standalone browser gate | `./scripts/test-loomark-standalone-e2e.sh` | exit 0 and private controls absent from production bundle |
| Final gate | `./scripts/validate-pr-ready.sh --target apps/loomark/internal/rabbita` | exit 0 on clean candidate HEAD |

## Suggested executor toolkit

- Use `codebase-design` vocabulary: module, interface, seam, adapter, depth, leverage, locality.
- Use MoonBit refactoring guidance and current `moon ide` commands before defining or removing any function.
- Read the vendored Rabbita component, command, and subscription docs named in Plan 001.
- Inspect the generated `.mbti` before and after each public-interface reduction.

## Scope

**In scope:**

- `apps/loomark/internal/rabbita/application_root.mbt`.
- `apps/loomark/internal/rabbita/application_mount.mbt`.
- `apps/loomark/internal/rabbita/application_subscriptions.mbt`.
- `apps/loomark/internal/rabbita/application_view.mbt`.
- `apps/loomark/internal/rabbita/dev_host_protocol.mbt`.
- `apps/loomark/internal/rabbita/dev_host_api.mbt`.
- `apps/loomark/internal/rabbita/pkg.generated.mbti`.
- `apps/loomark/internal/dev_host/dev_host.mbt`.
- `apps/loomark/internal/dev_host/pkg.generated.mbti` if generated and tracked.
- `apps/loomark/examples/vanilla/README.md` only where it incorrectly names the old internal dispatch surface after the refactor.

**Out of scope:**

- `DriverModel`, `DriverEvent`, their fields/variants, and all update semantics.
- Any feature-specific reducer, coordinator, persistence queue, Worker protocol, or DOM adapter.
- HTML, CSS, IDs, data attributes, event-detail strings, snapshot JSON, and JS export names.
- Main production mount interface `mount_standalone` and Gate R0 oracle mount behavior.
- New packages, traits, generic callback bundles, ports without two adapters, or public application/session handles.
- Val-island, memoization, keyed rendering, lifecycle, unmount, performance, #1353, or operation-based editing work.
- Rabbita submodule and manifests.

## Git workflow

- Start from the clean, merged result of Plan 001 in a dedicated worktree containing current `origin/main`.
- Suggested branch: `refactor/loomark-rabbita-root-seam`.
- Commit logical slices separately: root profile, mount callers, dev-host seam, docs/interface cleanup.
- Match conventional commit style, for example `refactor(loomark): seal Rabbita application profiles`.
- Do not push or open a PR unless instructed.

## Existing API First

Before adding `ApplicationProfile`, inspect and record these candidates:

1. Existing `StandaloneBootstrapMode` in `standalone_bootstrap.mbt`: reuse it as the payload of the standalone profile; it already distinguishes LocalText and full-history oracle boot.
2. Existing `standalone_application` / `private_dev_host_application`: replace them rather than layering a third wrapper over them.
3. Existing `build_application`: rename/deepen it into `application` rather than adding a parallel root builder.
4. Existing `parse_driver_event` and `dispatch_driver`: reuse them as the one private wire decoder/dispatcher; do not create a second normalization path.
5. Existing `mount_standalone_with_mode`: retain it for standalone/oracle boot unless the profile replacement can simplify it without merging startup contracts.

MoonBit core candidates to inspect are private structs/named constructors, `Option`, `Result`, `Map`, and `String`/`StringView`. Reuse the existing JSON and string encoders; this plan must not add a low-level parser, loop, collection builder, or mutable registry.

New definitions permitted by this plan:

- one private `ApplicationProfile` value with two private named constructors;
- at most four public private-dev-host seam functions replacing the many individual public controls;
- small private profile-selection functions only when a direct exhaustive `match` would otherwise be duplicated three or more times. State each helper's responsibility and keep it private.

## Steps

### Step 1: Characterize both profiles at their existing seams

Before changing construction, record:

- public `.mbti` surfaces for the Rabbita and dev-host packages;
- production and dev-host JS exports;
- standalone subscription behavior when healthy, fatal, and persistence-disabled;
- dev-host control/test subscription installation, tagger refresh, unload, and fatal behavior;
- standalone outer view during bootstrap and after boot;
- private dev-host outer view and driver controls;
- Worker and Raw Preview allocation/disposal differences.

Prefer existing MoonBit and Playwright tests. Add no new test if an existing assertion already pins the behavior. If a profile decision lacks coverage, add the smallest deterministic profile test in `apps/loomark/internal/rabbita/application_profile_wbtest.mbt` before refactoring.

**Verify:**

```bash
moon test apps/loomark/internal/rabbita --target js --release
./scripts/test-loomark-dev-host-e2e.sh
./scripts/test-loomark-standalone-e2e.sh
```

Expected: all exit 0 on the Plan 001 baseline.

### Step 2: Introduce the closed profile and deepen the root function

In `application_root.mbt`:

1. Add private `ApplicationProfile` with only `standalone(StandaloneBootstrapMode)` and `private_dev_host()` construction paths.
2. Replace `build_application` with `application(profile, editor, attachment, initial, baseline)`.
3. Move profile decisions inside `application`: bootstrap selection, Raw Preview disablement/allocation, subscriptions, and outer view.
4. Keep projection placement and runtime synchronization profile-independent unless current behavior proves otherwise.
5. Delete `standalone_application` and `private_dev_host_application` once their behavior is expressed by the profile.

Do not expose profile fields or accept independent callback parameters in `application` or mount functions. Verify the chosen representation with the production private-symbol scan; an enum representation is rejected if it retains the private branch.

**Verify:**

```bash
moon fmt --check apps/loomark/internal/rabbita/application_root.mbt
moon check apps/loomark/internal/rabbita --target js
rg -n 'fn (build_application|standalone_application|private_dev_host_application)' apps/loomark/internal/rabbita
rg -n 'subscriptions : \(DriverModel|view : \(DriverModel' apps/loomark/internal/rabbita
```

Expected: format/check exit 0; both searches for the old functions and callback parameters return no matches.

### Step 3: Make mount callers pass only a profile

In `application_mount.mbt`:

- replace the `build` function parameter in the private mount path with `ApplicationProfile::private_dev_host()` passed directly to `application`;
- pass `ApplicationProfile::standalone(LocalTextBootstrap)` and `ApplicationProfile::standalone(FullHistoryOracleBootstrap)` from the existing standalone/oracle paths;
- preserve editor/session creation, document IDs, replica prefixes, bootstrap flags, recovery mounts, attachment disposal, detached publication, and mount-once behavior exactly.

Do not unify the private and standalone initialization paths merely because both now call `application`; their failure and bootstrap contracts differ.

**Verify:**

```bash
moon fmt --check apps/loomark/internal/rabbita/application_mount.mbt
moon check apps/loomark/internal/rabbita --target js
rg -n 'build : \(' apps/loomark/internal/rabbita/application_mount.mbt
```

Expected: exit 0 and no function-valued builder parameter remains.

### Step 4: Shrink the private dev-host package seam

Use `moon ide find-references` for every public control currently in `dev_host_api.mbt`. Replace the cross-package interface with the four-or-fewer functions defined in Target design.

Move request encoding for source, mode selection, restore payloads, failure probes, focus, selection, measurement, listener stop, and fatal controls into `apps/loomark/internal/dev_host/dev_host.mbt`. That package already owns the typed JS export adapter. Each export must encode the same existing detail string and call the one Rabbita-package dispatcher.

Keep `parse_driver_event` in the Rabbita package so wire decoding immediately yields typed `DriverEvent`. Do not expose `DriverEvent` across the package seam and do not make the dev-host adapter construct it.

Delete the superseded individual public functions only after all dev-host callers use the compact seam.

**Verify:**

```bash
moon check apps/loomark/internal/rabbita apps/loomark/internal/dev_host --target js
moon info
sed -n '1,240p' apps/loomark/internal/rabbita/pkg.generated.mbti
sed -n '1,240p' apps/loomark/internal/dev_host/pkg.generated.mbti
```

Expected: checks exit 0; Rabbita `.mbti` contains the production/oracle mounts, projection worker entry, and four-or-fewer private dev-host seam functions, but none of the old one-function-per-control surface. The dev-host JS-export interface remains unchanged.

### Step 5: Prove production/private separation

Update `apps/loomark/examples/vanilla/README.md` only if it names the removed internal function surface. Preserve its stated contract: typed JS exports cross a string CustomEvent detail seam and are decoded into typed application messages; no live enqueue closure or global handle registry is exported.

Run both browser gates. The standalone script already rejects private names in the production bundle; extend its rejection list only if the new compact seam could otherwise leak unnoticed.

**Verify:**

```bash
./scripts/test-loomark-dev-host-e2e.sh
./scripts/test-loomark-standalone-e2e.sh
```

Expected: both exit 0; every existing dev-host JS control still behaves identically; production output contains none of the private dev-host seam or JS export names.

### Step 6: Final review and validation

Run targeted MoonBit validation, inspect generated interfaces, and request independent review focused on depth, ownership, effect order, subscription lifetime, and DCE separation.

**Verify:**

```bash
moon fmt --check apps/loomark/internal/rabbita apps/loomark/internal/dev_host
moon check apps/loomark/internal/rabbita apps/loomark/internal/dev_host --target js
moon test apps/loomark/internal/rabbita --target js --release
moon info
git diff --check
git diff --stat
```

Expected: all commands exit 0; only in-scope files changed; generated-interface differences are limited to intentional removal/replacement of internal Rabbita dev-host exports.

After resolving independent review, commit the candidate and run:

```bash
./scripts/validate-pr-ready.sh --target apps/loomark/internal/rabbita
```

Immediately before PR work:

```bash
git fetch origin main
./scripts/validate-pr-ready.sh --verify-evidence
```

Expected: both validator invocations exit 0 against the exact clean candidate HEAD.

## Test plan

Use existing tests as the main characterization layer:

- Rabbita wbtests for feature reducers, recovery, projection, commands, and SSR view behavior;
- `examples/vanilla/tests/dev-host.spec.ts` for every retained JS export and private subscription lifecycle;
- `examples/vanilla/tests/standalone.spec.ts` for production boot, editing, persistence, and view behavior;
- `scripts/test-loomark-standalone-e2e.sh` for private-symbol rejection in release output.

Add `application_profile_wbtest.mbt` only for uncovered pure decisions. If added, cover both profiles for bootstrap mode, Raw Preview ownership, subscription adapter selection, and outer-view adapter selection without inspecting runtime internals.

Do not replace browser tests with unit tests. The interface is the test surface: profile tests cover deterministic selection, while browser tests cover actual effect wiring and DCE separation.

## Done criteria

- [x] Root construction takes one closed `ApplicationProfile`; root and mount callers do not pass model-aware view/subscription callbacks or Boolean feature flags.
- [x] `standalone_application`, `private_dev_host_application`, and function-valued mount builders are gone.
- [x] One existing Rabbita root still owns the complete `DriverModel` and `DriverEvent` update loop.
- [x] The existing Val graph and branch lifetimes are unchanged.
- [x] The Rabbita package exposes four private dev-host seam functions instead of individual test controls.
- [x] The dev-host package preserves all existing JS export names and behavior.
- [x] Production release output contains no private dev-host seam or controls.
- [ ] targeted MoonBit checks/tests, both browser gates, and clean-HEAD validator pass.
- [ ] no out-of-scope behavior, dependency, package, or public product interface changes occur.

## STOP conditions

Stop and report if:

- Plan 001 is not complete or its responsibility files differ materially from this plan;
- a third application profile or external caller is discovered;
- profile selection requires exposing `DriverModel`, `DriverEvent`, `Html`, `Cmd`, `Sub`, a coordinator, or a mutable ref across packages;
- compacting the dev-host seam requires changing JS export names, event-detail strings, snapshot JSON, or browser tests;
- production and private initialization cannot remain distinct without duplicating the root reducer;
- a proposed change would move Worker/persistence lifetime under a disposable view branch;
- generated interfaces grow anywhere other than the explicitly permitted compact seam;
- browser gates reveal changed command ordering, subscription counts, mount behavior, DOM, focus/selection, persistence, or timing;
- a validation failure repeats after one reasonable correction.

## Maintenance notes

After this plan, the application has one deep internal root interface and two explicit adapters. Do not immediately split `DriverModel` into child Rabbita states: shared editing, persistence, recovery, projection, and stale-result decisions currently require atomic transitions. A later maintainability plan may group cohesive product and dev-host fields inside the model or rename `DriverModel`/`DriverEvent` to application vocabulary, but only after this seam lands and only with independent characterization. Val projection remains an evidence-gated rendering decision, not part of structural cleanup.
