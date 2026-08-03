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

| Job | What it runs |
|-----|--------------|
| `dep-check` | `./scripts/check-deps.sh` (module-scope rules [A]–[E] + canopy package-layering rules [F]–[I]; the rules table lives in the script header), `./scripts/check-shared-substrate.sh`, `./scripts/check-egw-resolver-identity.sh`, `./scripts/check-moon-update-wrapped.sh`, `node ./scripts/check-export-manifest.mjs`, `./scripts/test-moon-update-wrapper.sh`, `./scripts/test-pr-ready-validation.sh` |
| `pr-ready-bash3` | Path-filtered macOS check that asserts `/bin/bash` 3.2, exercises local submodule failures, and runs the real PR-ready shell graph with only compiler work faked |
| `test-main` | `./scripts/update-moon-deps.sh`, `./scripts/check-agent-doc-links.sh`, `./scripts/run-moon-module.sh check .`, `./scripts/run-moon-module.sh test .`, `moon build --release` |
| `test-submodules` | Matrix over `event-graph-walker`, `loom/loom`, `svg-dsl`, `graphviz` — each runs `./scripts/run-moon-module.sh ci <path>` |
| `test-examples` | Matrix over `examples/ideal`, `examples/block-editor`, `examples/canvas` — each runs `./scripts/run-moon-module.sh ci <path>` |
| `prove` | `moon prove` in `modules/semantic/proof` after installing Why3 1.7.2 + Z3 via opam (cached) |
| `benchmark` | PR only: `moon bench --release` at the root and in `event-graph-walker` |
| `format-check` | `./scripts/check-agent-doc-links.sh` and `./scripts/run-moon-module.sh fmt-check .` |
| `build-js` | `./scripts/update-moon-deps.sh`, `./scripts/build-js.sh`; uploads the generated JS/d.ts/mbti artifacts listed below |
| `web-build` | Default Waku build plus TypeScript/boundary checks for `examples/web`, then the ProseMirror typecheck |
| `waku-build` | Builds the production Worker from downloaded MoonBit artifacts, verifies bundle/type boundaries, runs preview/production Wrangler dry-runs and startup analysis, and uploads the release artifacts |
| `waku-e2e` | Canonical route, lifecycle, compatibility, and production-preview Playwright suites for `examples/web` |
| `waku-workerd` | Built Worker and same-origin Signaling smoke under local workerd |
| `ideal-web-e2e` | Playwright suite for `examples/ideal/web` |
| `demo-react-e2e` | Playwright suite for `examples/demo-react` |
| `canvas-e2e` | Playwright suite for `examples/canvas/web` |
| `all-checks-passed` | Aggregation gate; fails unless every required job succeeds or is an accepted path-filtered skip |

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
graphviz/_build/js/release/build/browser/browser.js
graphviz/_build/js/release/build/browser/browser.d.ts
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
| `ideal` | `canopy-ideal` | Pages | `examples/ideal/web/dist` |
| `prosemirror` | `canopy-prosemirror` | Pages | `examples/prosemirror/dist` |
| `demo-react` | `canopy-demo-react` | Pages | `examples/demo-react/dist` |
| `block-editor` | `canopy-block-editor` | Pages | `examples/block-editor/web/dist` |
| `canvas` | `canopy-canvas` | Pages | `examples/canvas/web/dist` |
| `relay-server` | `canopy-relay` | Workers | `examples/relay-server` |

Requires the secrets `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID`.

`examples/web` is intentionally absent from this workflow. Cloudflare Workers
Builds connects directly to GitHub and deploys `examples/web` to the
`canopy-examples` Worker after every push to `main`; its build and deploy
settings are documented in
[`examples/web/CLOUDFLARE_DEPLOYMENT.md`](../examples/web/CLOUDFLARE_DEPLOYMENT.md).

> Earlier revisions of this doc described deployment via GitHub Pages to
> `dowdiness.github.io/crdt/`. That path is no longer used.

### `release.yml`

Packages release artifacts using `./scripts/package-release.sh`. Currently
covers **native** and **JavaScript**; WebAssembly is not part of the release
workflow.

## Running locally

Common entry points (Makefile targets that wrap `scripts/`):

```sh
make help                  # List all targets
make test                  # Tests for the workspace
make test-all              # Fan out into submodules
make check                 # moon check
make check-all             # check + fmt-check across modules
make fmt                   # moon fmt && moon info
make fmt-check             # CI's format gate
make build                 # moon build --release
make build-js              # Build the FFI JS artifacts CI uploads
make build-web             # build-js + default Waku build in examples/web
make test-web-e2e          # canonical Waku and production-preview Playwright suites
make test-demo-react-e2e   # Playwright suite for examples/demo-react
make test-canvas-e2e       # Playwright suite for examples/canvas/web
make bench                 # moon bench --release (root + event-graph-walker)
make ci                    # check-all + test-all
make web-dev               # build-js then start the examples/web Waku dev server
make install-hooks         # Install pre-commit hook
make update                # moon update across root + maintained submodules
```

The shared module helper is `./scripts/run-moon-module.sh <subcommand> <path>`
where `<subcommand>` is `check`, `test`, `ci`, `fmt-check`, or `bench`. It
validates that `<path>` is a real MoonBit module before invoking `moon`.

### PR-ready validation

After the targeted edit loop and independent review are complete, commit the
candidate result and run the ordered local gate on that clean HEAD:

```sh
git fetch origin main
./scripts/validate-pr-ready.sh --target lang/markdown/proj --target lang/markdown/edits
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

When `scripts/**` or `ci.yml` changes, the path-filtered `pr-ready-bash3` job
asserts that the macOS system `/bin/bash` is 3.2, runs the CLI fixture contract,
and executes the real downstream shell graph with a fake `moon` compiler. It
verifies orchestration portability only; it does not claim macOS parity for
MoonBit, JavaScript, proof, or browser gates.

## Pre-commit hook

`make install-hooks` (or `./scripts/install-hooks.sh`) installs the hook in
`.githooks/`. The hook runs `moon check` for the changed package. If you need
to bypass it (e.g. during a rebase you understand), `git commit --no-verify` is
available, but CI's `format-check` and `test-main` will catch the same issues
on push.

## Adding new gating checks

Add the job to `ci.yml`, then add its name to the `needs:` list and status
predicate under `all-checks-passed`. For `pr-ready-bash3`, the aggregate accepts
`success`, or `skipped` only when `run_pr_ready_bash3` is exactly `false`;
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
- **`format-check` fails.** Run `make fmt` locally and commit the result.
- **Submodule checkouts.** Every checkout step uses `submodules: recursive`.
  If you add a new workflow, copy that setting.

## References

- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [MoonBit CLI Reference](https://docs.moonbitlang.com)
- [Workflow files](../.github/workflows/) — authoritative
- [Active backlog](https://github.com/dowdiness/canopy/issues)
