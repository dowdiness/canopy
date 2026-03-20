# CI/CD Workflows

This directory contains GitHub Actions workflows for automated testing, deployment, and release management.

## Workflows

### 1. CI (`ci.yml`)

**Triggers:** Push to `main`, Pull Requests, Manual dispatch

Runs comprehensive checks on every push and PR via shared `make` and `scripts/` entrypoints:

- **Test Main Module** - Tests the main Canopy module
- **Test Submodules** - Tests each submodule (`event-graph-walker`, `loom`, `svg-dsl`, `graphviz`) in parallel
- **Format Check** - Ensures root formatting is clean via `make fmt-check`
- **Build JS** - Builds `canopy.js`/`canopy.d.ts` plus Graphviz browser artifacts
- **Web Tests** - Builds `examples/web` through `make build-web` and runs Playwright if tests exist
- **Benchmark** - Runs benchmarks on PRs (optional)

**Status Badge:**
```markdown
![CI](https://github.com/dowdiness/canopy/workflows/CI/badge.svg)
```

### 2. Benchmark Regression (`benchmark.yml`)

**Triggers:** Pull Requests to `main`, Manual dispatch

Compares benchmark performance between PR and base branch using the shared MoonBit module runner:

- Runs benchmarks on PR branch
- Checks out base branch and runs benchmarks
- Posts comparison comment to PR
- Stores results as artifacts (30-day retention)

Helps detect performance regressions before merging.

### 3. Deploy (`deploy.yml`)

**Triggers:** Push to `main`, Manual dispatch

Builds and deploys the web application to GitHub Pages:

1. Builds shared JS artifacts with `make build-js`
2. Builds `examples/web` with `make build-web`
3. Deploys to GitHub Pages

**Requirements:**
- Enable GitHub Pages in repository settings
- Set source to "GitHub Actions"

**Live URL:** `https://dowdiness.github.io/crdt/` (after first deployment)

### 4. Release (`release.yml`)

**Triggers:** Git tags matching `v*.*.*`, Manual dispatch

Creates GitHub releases with artifacts:

- Runs full test suite
- Builds supported targets (native, JS)
- Builds web application
- Creates `canopy-moonbit-<version>.tar.gz` and `canopy-web-<version>.tar.gz`
- Generates changelog from commits
- Creates GitHub Release with artifacts

**Usage:**
```bash
# Create and push a tag
git tag v0.2.0
git push origin v0.2.0

# Or trigger manually from Actions tab
```

### 5. Copilot Setup (`copilot-setup-steps.yml`)

**Triggers:** Changes to this workflow file, Manual dispatch

Provides environment setup for GitHub Copilot agents:

- Checks out code with submodules
- Installs MoonBit CLI
- Updates dependencies

## Dependabot Configuration

The `.github/dependabot.yml` file configures automatic dependency updates:

- **GitHub Actions** - Weekly updates to workflow actions
- **NPM (web)** - Weekly updates to web frontend dependencies
- **NPM (examples/demo-react)** - Weekly updates to demo dependencies
- **NPM (valtio)** - Weekly updates to valtio submodule dependencies

Dependabot will create PRs for dependency updates, which will be tested by the CI workflow.

## Local Development

Use the provided scripts and Makefile for local testing:

```bash
# Run all tests
make test-all

# Run all checks (check + format)
make check-all

# Build web application
make build-web

# Install pre-commit hooks
make install-hooks

# Run full CI locally
make ci
```

## Artifacts

Workflows generate artifacts for inspection:

| Workflow | Artifact | Retention |
|----------|----------|-----------|
| CI | `moonbit-js-build` | 7 days |
| Benchmark | `benchmark-comparison` | 30 days |
| Release | `release-artifacts` | 90 days |

## Secrets and Variables

No secrets are currently required. GitHub automatically provides:

- `GITHUB_TOKEN` - For creating releases, posting comments
- Pages deployment token - For GitHub Pages deployment

## Monitoring

Check workflow status:

1. Go to **Actions** tab in GitHub
2. View recent runs and their status
3. Click on a run to see detailed logs

## Troubleshooting

### CI Fails on Submodule Tests

Ensure submodules are up to date:
```bash
git submodule update --init --recursive
```

### Benchmark Comparison Shows No Difference

Benchmarks can be noisy. Look for:
- Significant changes (>10%)
- Consistent patterns across runs
- Run benchmarks locally to verify

### GitHub Pages Deployment Fails

1. Check repository settings → Pages
2. Ensure source is set to "GitHub Actions"
3. Verify `examples/web/dist` directory is created during build

### Format Check Fails

Run locally:
```bash
make fmt
git diff  # Check what changed
```

Commit formatting changes before pushing.

## Contributing

When adding new workflows:

1. Test locally with `act` if possible
2. Document triggers and purpose
3. Update this README
4. Use concurrency groups to prevent duplicate runs
5. Add appropriate artifact retention periods
