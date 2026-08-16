# CI / CD

How continuous integration and deployment are wired up for Canopy. The
`.github/workflows/*.yml` files are the source of truth; this document
summarises them.

## Workflows

There are five workflow files in `.github/workflows/`:

| File | Triggers | Purpose |
|------|----------|---------|
| `ci.yml` | push to `main`, pull requests, manual dispatch | All gating checks |
| `benchmark.yml` | pull requests | Benchmark comparison with the base branch |
| `deploy-cloudflare.yml` | push to `main`, manual dispatch | Deploy the example apps to Cloudflare |
| `release.yml` | release tags, manual dispatch | Build versioned release artifacts |
| `copilot-setup-steps.yml` | (assistant tooling) | Environment setup steps used by remote agents |

### `ci.yml`

The main gating workflow. Job names match the file:

`canvas-e2e` has a dedicated `run_canvas_e2e` path filter because the canvas
runtime depends on `modules/canvas-graph`. A module-only canvas-graph change
therefore runs the Canvas browser suite without enabling unrelated web, Ideal,
or demo E2E jobs. The aggregation gate accepts a skipped Canvas job only when
that filter is false. The exact path membership is maintained in the `changes`
job of `.github/workflows/ci.yml`; this document describes the contract rather
than duplicating its globs.

| Job | What it runs |
|-----|--------------|
| `dep-check` | `./scripts/check-deps.sh` (module-scope rules [A]–[E] + canopy package-layering rules [F]–[I]; the rules table lives in the script header), `./scripts/check-shared-substrate.sh`, `./scripts/check-egw-resolver-identity.sh`, `nu ./scripts/check-moon-update-wrapped.nu` (registry-bootstrap wiring and manifest contract), `nu ./scripts/test-moon-registry-bootstrap.nu`, `node ./scripts/check-export-manifest.mjs`, `./scripts/test-moon-update-wrapper.sh`, `./scripts/test-pr-ready-validation.sh` |
| `pr-ready-bash3` | Path-filtered macOS check that asserts `/bin/bash` 3.2, exercises local submodule failures, and runs the real PR-ready shell graph with only compiler work faked |
| `tooling-validation` | Path-filtered Ubuntu validation for GitHub Actions YAML, the pinned justfile, Cursor bootstrap shell, registry-bootstrap contract, Cloudflare build bootstrap scripts, Nushell installer script, and Lefthook configuration |
| `release-version-validation` | Path-filtered Ubuntu release-contract syntax and regression tests for version resolution, changelog ranges, and remote target resolution |
| `test-main` | setup-moonbit registry bootstrap, `./scripts/check-agent-doc-links.sh`, `./scripts/run-moon-module.sh check modules/canopy`, `./scripts/run-moon-module.sh test modules/canopy`, `moon build --release` |
| `test-submodules` | Matrix over `deps/event-graph-walker`, `deps/loom/loom`, `deps/svg-dsl`, `deps/graphviz` — each runs `./scripts/run-moon-module.sh ci <path>` |
| `test-examples` | Matrix over `apps/ideal`, `apps/block-editor`, `apps/canvas` — each runs `./scripts/run-moon-module.sh ci <path>` |
| `prove` | `moon prove` in `modules/semantic/proof` after installing Why3 1.7.2 + Z3 via opam (cached) |
| `benchmark` | PR only: `moon bench --release` at the root and in `deps/event-graph-walker` |
| `format-check` | `./scripts/check-agent-doc-links.sh`, `./scripts/check-documentation-lifecycle.sh`, `NEW_MOON_MOD=0 moon fmt`, and a diff check that rejects Canopy-owned formatting changes |
| `build-js` | setup-moonbit registry bootstrap, `./scripts/build-js.sh`; uploads the generated JS/d.ts/mbti artifacts listed below |
| `web-build` | Default Waku build plus TypeScript/boundary checks for `apps/web`, then the ProseMirror typecheck |
| `waku-build` | Builds the production Worker from downloaded MoonBit artifacts, verifies bundle/type boundaries, runs preview/production Wrangler dry-runs and startup analysis, and uploads the release artifacts |
| `waku-e2e` | Canonical route, lifecycle, compatibility, and production-preview Playwright suites for `apps/web` |
| `waku-workerd` | Built Worker and same-origin Signaling smoke under local workerd |
| `ideal-web-e2e` | Playwright suite for `apps/ideal/web` |
| `demo-react-e2e` | Playwright suite for `examples/demo-react` |
| `canvas-e2e` | Playwright suite for `apps/canvas/web`; selected by the `run_canvas_e2e` output from the `changes` job |
| `all-checks-passed` | Aggregation gate; fails unless every required job succeeds or is an accepted path-filtered skip |

The local `setup-moonbit` composite action owns MoonBit registry bootstrap for
CI. Its registry cache is keyed by a schema version, runner platform, exact
MoonBit toolchain/core pair, `moon.work`, and every workspace `moon.mod` or
`moon.mod.json`. An exact cache hit performs no registry refresh; a cold or
partial restore invokes the bounded-retry wrapper once, and the resulting state
is saved under the exact key. Build, test, benchmark, proof, release, and deploy
operations in prepared CI environments do not refresh the registry themselves.
The self-contained Cloudflare Workers Builds scripts bootstrap once after their
own toolchain/submodule setup, and `just registry-refresh` remains the explicit
local refresh entry point.

#### Uploaded artifacts (`build-js`)

`actions/upload-artifact@v7` uploads the following paths under the name
`moonbit-js-build`:

```
_build/js/release/build/dowdiness/canopy/ffi/lambda/lambda.js
_build/js/release/build/dowdiness/canopy/ffi/lambda/lambda.d.ts
_build/js/release/build/dowdiness/canopy/ffi/lambda/moonbit.d.ts
_build/js/release/build/dowdiness/canopy/ffi/json/json.js
_build/js/release/build/dowdiness/canopy/ffi/json/json.d.ts
_build/js/release/build/dowdiness/canopy/ffi/json/moonbit.d.ts
_build/js/release/build/dowdiness/canopy/ffi/markdown/markdown.js
_build/js/release/build/dowdiness/canopy/ffi/markdown/markdown.d.ts
_build/js/release/build/dowdiness/canopy/ffi/markdown/moonbit.d.ts
_build/js/release/build/dowdiness/graphviz/browser/browser.js
_build/js/release/build/dowdiness/graphviz/browser/browser.d.ts
```

Retention: default for the workflow (7 days at time of writing — check
`ci.yml` for the live value).

### `benchmark.yml`

Runs on pull requests. Compares benchmark output against the merge base and
posts the comparison as a PR comment. Reports are also uploaded as artifacts.
The comparison covers the root module and `event-graph-walker`.

### `deploy-cloudflare.yml`

Deploys on every push to `main` (and on manual dispatch). The matrix has six
entries — five Cloudflare Pages projects and one Cloudflare Workers deployment:

| Matrix name | Cloudflare project | Type | Source directory |
|-------------|--------------------|------|------------------|
| `ideal` | `canopy-ideal` | Pages | `apps/ideal/web/dist` |
| `prosemirror` | `canopy-prosemirror` | Pages | `examples/prosemirror/dist` |
| `demo-react` | `canopy-demo-react` | Pages | `examples/demo-react/dist` |
| `block-editor` | `canopy-block-editor` | Pages | `apps/block-editor/web/dist` |
| `canvas` | `canopy-canvas` | Pages | `apps/canvas/web/dist` |
| `relay-server` | `canopy-relay` | Workers | `apps/relay-server` |

Requires the secrets `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID`.

`apps/web` is intentionally absent from this workflow. Cloudflare Workers
Builds connects directly to GitHub and deploys `apps/web` to the
`canopy-examples` Worker after every push to `main`; its build and deploy
settings are documented in
[`apps/web/CLOUDFLARE_DEPLOYMENT.md`](../apps/web/CLOUDFLARE_DEPLOYMENT.md).

> Earlier revisions of this doc described deployment via GitHub Pages to
> `dowdiness.github.io/crdt/`. That path is no longer used.

### `release.yml`

Packages release artifacts using `./scripts/package-release.sh`. Currently
covers **native** and **JavaScript**; WebAssembly is not part of the release
workflow.

The release checkout uses full history (`fetch-depth: 0`) so the changelog
 generator can inspect tags reachable from the explicit `SOURCE_SHA`. It
accepts only strict stable Canopy tags (`vMAJOR.MINOR.PATCH` without leading
zeroes), peels annotated tags, excludes the current version, and selects the
nearest previous reachable tag by commit history. A shallow repository fails
rather than producing incomplete notes. If no previous tag is reachable, the
generator falls back to the latest 10 commits through `SOURCE_SHA`.

The generated `CHANGELOG.txt` is the sole release-note source: the GitHub
Release action uses `body_path` and does not request auto-generated release
notes. Releases with a previous tag link to its compare range; first releases
link to the version's commits page.

## Running locally

Common entry points (just recipes that wrap `scripts/`):

`just` is the canonical command runner and owns the repository recipes.

```sh
just help                  # List all recipes
just test                  # Tests for the main Canopy module
just test-all              # Tests for the root workspace
just check                 # moon check
just check-all             # check + fmt-check across modules
just fmt                   # moon fmt && moon info
just fmt-check             # CI's format gate
just build                 # moon build --release
just build-js              # Build the FFI JS artifacts CI uploads
just build-web             # build-js + default Waku build in apps/web
just test-web-e2e          # canonical Waku and production-preview Playwright suites
just test-demo-react-e2e   # Playwright suite for examples/demo-react
just test-canvas-e2e       # Playwright suite for apps/canvas/web
just bench                 # moon bench --release (root + event-graph-walker)
just ci                    # check-all + test-all
just web-dev               # build-js then start the apps/web Waku dev server
just install-hooks         # Install the pre-commit hook
just registry-refresh      # explicitly refresh the local MoonBit registry
just release-artifacts v0.2.0 # Package release artifacts (positional version)
```

The shared module helper is `./scripts/run-moon-module.sh <subcommand> <path>`
where `<subcommand>` is `check`, `test`, `ci`, `fmt-check`, or `bench`. It
validates that `<path>` is a real MoonBit module before invoking `moon`.

### PR-ready validation

After the targeted edit loop and independent review are complete, commit the
candidate result and run the ordered local gate on that clean HEAD:

```sh
git fetch origin main
./scripts/validate-pr-ready.sh --target modules/canopy/lang/markdown/proj --target modules/canopy/lang/markdown/edits
git fetch origin main
./scripts/validate-pr-ready.sh --verify-evidence
```

Use `--no-target "<reason>"` instead of `--target` only when no MoonBit package
is affected. `--list` takes the same target policy and prints the stable phase
order without executing it. The validator checks that HEAD contains the fetched
base, fetches and prunes each submodule origin before checking gitlink
reachability, verifies dependency identity, checks Canopy-owned formatting and
generated interfaces, runs targeted and full release gates, builds JavaScript,
and records the validated HEAD, base, and target policy in an ignored,
worktree-local `_build` file.

Any commit, amend, rebase, cherry-pick, submodule-pointer, manifest, or generated
interface change, or movement of the fetched base ref makes that evidence stale.
Fetch the base again immediately before `--verify-evidence`; if it moved, sync
the branch and rerun the full validator before opening, updating, or merging the
PR. This local gate deliberately does not replace the required CI matrix.

When `scripts/**`, `justfile`, `lefthook.yml`, or `ci.yml` changes, the path-filtered `pr-ready-bash3` job
asserts that the macOS system `/bin/bash` is 3.2, runs the CLI fixture contract,
and executes the real downstream shell graph with a fake `moon` compiler. It
verifies orchestration portability only; it does not claim macOS parity for
MoonBit, JavaScript, proof, or browser gates.

## Pre-commit hook

Lefthook is the current hook manager. Run `just install-hooks` to install the
hook described by `lefthook.yml`. Its path-aware `pre-commit` routing always
runs the repository contract, runs the main-module MoonBit check and format
jobs only when staged MoonBit-related paths match, and runs the tooling
contract only for hook/task/compatibility changes. The MoonBit jobs receive no
staged-file arguments: they retain the existing `modules/canopy` module scope.
`glob_matcher: doublestar` covers root and nested paths, while the piped group
keeps MoonBit `check` before `fmt-check`. The MoonBit route also includes the
just recipe and the scripts that implement its module and vendored checks, so
changing those operations exercises the operations themselves.

A separate `moonbit-rename` job reads staged rename metadata with Git's
pre-image and post-image paths. If a MoonBit source is moved outside the normal
route, it runs the same `check` then `fmt-check` tasks; ordinary staged
additions, modifications, and deletions continue through the glob group.

The public `just check` and `just fmt-check` recipes retain their explicit
repository-contract plus main-module behavior. The `pre-commit` recipe is the
single local entry point into Lefthook, and `.githooks/pre-commit` remains a
compatibility shim that delegates to it. The installer removes the repository's
legacy direct local `core.hooksPath=.githooks` setting, but refuses to replace
any other effective hook path, including included or global configuration.

The shared `scripts/check-submodule-reachability.nu` command is the sole
implementation used by PR-ready validation and the internal
`hook-submodule-reachability` recipe. Lefthook's pre-push job starts the thin
`scripts/run-submodule-reachability.sh` adapter unconditionally: Lefthook
2.1.10 filters gitlinks out of `{push_files}`, so `{all_files}` is retained only
as an execution sentinel and `use_stdin: true` supplies Git's authoritative
ref-update stream. The adapter owns the `.gitmodules` and `deps/` routing policy,
enumerates every newly introduced relevant commit, using the streamed remote
SHA or authoritative `origin` refs for new refs instead of stale local tracking
refs, and deduplicates shared commits across refs. The shared checker materializes each pushed commit's
`.gitmodules` and recursively checks its submodule graph, so non-checked-out
branch pushes and reverted intermediate gitlinks are covered. It invokes the
shared recipe only for relevant updates and does not run workspace-wide MoonBit
checks. The legacy `.githooks/pre-push` shim forwards Git's remote arguments and
ref-update stdin to the same Lefthook hook.
Manual cleanup is needed only for those non-legacy settings; use the reported
scope and origin to locate the configuration. If you need to bypass the hook
(e.g. during a rebase you understand), `git commit --no-verify` is available,
but the applicable CI jobs, including `tooling-validation` for hook and task
changes, will still run on push.

## Adding new gating checks

Add the job to `ci.yml`, then add its name to the `needs:` list and status
predicate under `all-checks-passed`. For path-filtered jobs such as
`pr-ready-bash3` and `tooling-validation`, the aggregate accepts `success`, or
`skipped` only when the corresponding filter output is exactly `false`;
unexpected skips fail the aggregate. A missing entry there silently lets
failures through.

## Troubleshooting

- **`build-js` fails because artifacts are missing.** `scripts/build-js.sh`
  verifies the eleven JS/d.ts/mbti paths listed above. The most common cause is
  running it without `submodules: recursive` checked out, because graphviz is a
  submodule.
- **`prove` fails to find Why3 or Z3.** The cache key includes the OS and
  arch; cache misses re-install via opam. If versions ever change, bump the
  cache key in `ci.yml`.
- **`format-check` fails.** Run `just fmt` locally and commit the result.
- **The hook does not run.** For the legacy local `.githooks` setting, run
  `just install-hooks`; remove a non-legacy local or global `core.hooksPath`
  setting manually first, then rerun the installer.
- **Submodule checkouts.** Every checkout step uses `submodules: recursive`.
  If you add a new workflow, copy that setting.

## References

- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [MoonBit CLI Reference](https://docs.moonbitlang.com)
- [Workflow files](../.github/workflows/) — authoritative
- [Active backlog](https://github.com/dowdiness/canopy/issues)
