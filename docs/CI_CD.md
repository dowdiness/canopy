# CI/CD Documentation

Comprehensive guide to the continuous integration and deployment setup for Canopy.

## Overview

The project uses GitHub Actions for CI/CD with workflows for:

- **Automated Testing** - Run tests on every push/PR
- **Code Quality** - Enforce formatting and linting
- **Benchmark Tracking** - Detect performance regressions
- **Automated Deployment** - Deploy to GitHub Pages
- **Release Automation** - Create versioned releases

## Quick Start

### For Developers

```bash
# Run tests locally (like CI does)
make test-all

# Run all checks (formatting, linting)
make check-all

# Run full CI suite locally
make ci

# Install pre-commit hooks
make install-hooks
```

### For Maintainers

```bash
# Create a new release
git tag v0.2.0
git push origin v0.2.0

# Deploy to GitHub Pages (automatic on push to main)
git push origin main
```

## Workflows

### 1. CI Workflow

**File:** `.github/workflows/ci.yml`

Runs on every push and pull request to ensure code quality.

#### Jobs

1. **test-main** - Tests the main Canopy module
   ```bash
   make update
   make check
   make test
   make build
   ```

2. **test-submodules** - Tests all submodules in parallel
   - event-graph-walker
   - loom (`loom/loom` module root)
   - svg-dsl
   - graphviz

3. **format-check** - Ensures consistent formatting
   ```bash
   make fmt-check
   ```

4. **build-js** - Builds JavaScript target
   ```bash
   make build-js
   ```
   Uploads `canopy.js`, `canopy.d.ts`, and Graphviz browser artifacts.

5. **web-build** - Verifies `examples/web` still builds
   - Installs Node.js dependencies
   - Runs `make build-web`

6. **web-e2e** - Runs web Playwright E2E suite (28 tests: lambda, JSON, markdown)
   - Installs `examples/web` dependencies
   - Installs Playwright Chromium
   - Runs `make test-web-e2e`

7. **demo-react-e2e** - Runs demo-react Playwright E2E suite (25 tests: single editor, collaborative)
   - Installs `examples/demo-react` dependencies
   - Installs Playwright Chromium
   - Runs `make test-demo-react-e2e`

8. **benchmark** (on PRs only) - Runs performance tests
   ```bash
   ./scripts/run-moon-module.sh bench .
   ```

#### Status Checks

All jobs must pass before merging. The `all-checks-passed` job provides a single status check.

### 2. Benchmark Regression

**File:** `.github/workflows/benchmark.yml`

Compares benchmark results between PR and base branch.

#### Process

1. Run benchmarks on PR branch
2. Checkout base branch
3. Run root and `event-graph-walker` benchmarks on the base checkout with self-contained `moon update` / `moon bench --release` commands so the workflow does not depend on new helper scripts already existing there
4. Compare results
5. Post comparison as PR comment
6. Upload raw results as artifacts

#### Reading Results

Look for:
- **Time differences** - >10% is significant
- **Consistency** - Verify with local runs
- **Patterns** - Multiple benchmarks degrading

Example comment:
```
## Benchmark Comparison Report

### Main Module Benchmarks

**Base branch:**
Benchmark: 1000_operations - 45.2ms
Benchmark: parse_complex - 12.8ms

**PR branch:**
Benchmark: 1000_operations - 42.1ms  ⬇️ 6.9% faster
Benchmark: parse_complex - 13.5ms   ⬆️ 5.5% slower
```

### 3. Deployment

**File:** `.github/workflows/deploy.yml`

Automatically deploys to GitHub Pages on push to `main`.

#### Build Process

1. **MoonBit Build**
   ```bash
   make build-js
   ```

2. **Web Build**
   ```bash
   make build-web
   ```

3. **Deploy**
   - Uploads `examples/web/dist` to GitHub Pages
   - Publishes to `https://dowdiness.github.io/crdt/`

#### Setup Requirements

1. Go to **Settings** → **Pages**
2. Set **Source** to "GitHub Actions"
3. Save

First deployment may take a few minutes. Subsequent deploys are faster.

### 4. Release Workflow

**File:** `.github/workflows/release.yml`

Creates GitHub releases with build artifacts.

Current supported release targets are native and JavaScript. WebAssembly is not supported yet and is not part of the release workflow.

#### Triggering Releases

**Via Git Tag:**
```bash
# Create and push a tag
git tag v0.2.0
git push origin v0.2.0
```

**Via GitHub UI:**
1. Go to **Actions** → **Release**
2. Click **Run workflow**
3. Enter version (e.g., `v0.2.0`)

#### Build Artifacts

The workflow creates:

1. **MoonBit Package** - `canopy-moonbit-{version}.tar.gz`
   - JavaScript builds
   - Module configuration
   - README and LICENSE

2. **Web Package** - `canopy-web-{version}.tar.gz`
   - Production web build
   - Ready to deploy

#### Changelog Generation

Automatically generates changelog from commits since last tag:

```
## What's Changed

- feat: add undo/redo support (a1b2c3d)
- fix: resolve sync conflict (d4e5f6g)
- chore: update dependencies (g7h8i9j)
```

## Dependency Management

### Dependabot

**File:** `.github/dependabot.yml`

Automatic dependency updates:

- **GitHub Actions** - Weekly updates
- **NPM packages** - Weekly updates (examples/web, examples/demo-react, valtio)
- **Grouped updates** - Playwright and Vite updates grouped

Dependabot creates PRs that are automatically tested by CI.

### MoonBit Dependencies

Update manually:
```bash
make update
```

Add to CI if you need to test against latest dependencies.

## Local Development Scripts

### Makefile Targets

```bash
make help          # Show all available targets

# Testing
make test          # Test main module only
make test-all      # Test all modules + submodules

# Code Quality
make check         # Check main module
make check-all     # Check all modules
make fmt           # Format code

# Building
make build         # Build main module
make build-js      # Build JavaScript target
make build-web     # Build web application
make test-web-e2e         # Run web Playwright E2E (lambda, JSON, markdown)
make test-demo-react-e2e  # Run demo-react Playwright E2E (single, collaborative)

# Development
make web-dev       # Build JS + start dev server
make clean         # Clean build artifacts
make ci            # Run MoonBit CI checks locally

# Setup
make install-hooks # Install git pre-commit hooks
make update        # Update all dependencies
```

### Scripts

Located in `scripts/`:

1. **build-web.sh** - Builds shared JS artifacts and then builds `examples/web`
   ```bash
   ./scripts/build-web.sh
   ```

2. **test-all.sh** - Tests all modules with nice output
   ```bash
   ./scripts/test-all.sh
   ```

3. **check-all.sh** - Runs check + format validation for all modules
   ```bash
   ./scripts/check-all.sh
   ```

4. **install-hooks.sh** - Installs pre-commit hooks
   ```bash
   ./scripts/install-hooks.sh
   ```

5. **run-moon-module.sh** - Shared entrypoint for `check`, `test`, `fmt-check`, `ci`, and `bench`
   ```bash
   ./scripts/run-moon-module.sh ci .
   ./scripts/run-moon-module.sh bench event-graph-walker
   ```
   The helper validates that the provided path is a real MoonBit module root before running commands, so `loom/loom` is used instead of the umbrella `loom/` directory.

6. **build-js.sh** - Builds the canonical JS artifacts for Canopy + Graphviz
   ```bash
   ./scripts/build-js.sh
   ```

7. **package-release.sh** - Creates release archives from the current build outputs
   ```bash
   ./scripts/package-release.sh v0.2.0
   ```

### Pre-commit Hooks

Install with `make install-hooks` or `./scripts/install-hooks.sh`.

The hook runs:
```bash
make check
make fmt-check
```

Prevents committing code that would fail CI.

**Bypass (not recommended):**
```bash
git commit --no-verify
```

## Performance Optimization

### Build Times

**Parallel Testing:**
CI runs submodule tests in parallel using matrix strategy:

```yaml
strategy:
  matrix:
    include:
      - name: event-graph-walker
        path: event-graph-walker
      - name: loom
        path: loom/loom
      - name: svg-dsl
        path: svg-dsl
      - name: graphviz
        path: graphviz
```

**Caching:**
Currently no caching (MoonBit builds are fast). Could add:
- Moon binary caching
- npm dependencies caching

### Artifact Storage

| Artifact | Size | Retention | Cost Impact |
|----------|------|-----------|-------------|
| JS builds | ~500KB | 7 days | Low |
| Benchmarks | ~10KB | 30 days | Very low |
| Releases | ~2MB | 90 days | Low |

Adjust retention periods in workflow files if needed.

## Troubleshooting

### Common Issues

#### Submodule Checkout Fails

**Symptom:** CI fails with "submodule not found"

**Solution:**
```yaml
- uses: actions/checkout@v4
  with:
    submodules: recursive  # ← Must be set
```

#### Format Check Fails

**Symptom:** CI fails on format-check job

**Solution:**
```bash
make fmt
git add .
git commit -m "chore: format code"
```

#### Web Build Fails

**Symptom:** `canopy.js` or `canopy.d.ts` not found in web build

**Solution:** Run the shared JS entrypoint before building the frontend:
```bash
make build-js
make build-web
```

#### Benchmark Results Noisy

**Symptom:** Benchmarks vary wildly between runs

**Facts:**
- GitHub Actions runners have variable performance
- Benchmarks are for **relative** comparison, not absolute
- Look for consistent patterns, not single runs

**Mitigation:**
```bash
# Run locally for accurate numbers
make bench
```

### Debug Workflows

#### View Logs

1. Go to **Actions** tab
2. Click on failed workflow run
3. Click on failed job
4. Expand failed step

#### Run Workflow Manually

Most workflows support `workflow_dispatch`:

1. Go to **Actions** tab
2. Select workflow
3. Click **Run workflow**

#### Test Locally with act

Install [act](https://github.com/nektos/act):
```bash
brew install act  # macOS
# or
curl https://raw.githubusercontent.com/nektos/act/master/install.sh | sudo bash
```

Run workflows locally:
```bash
act pull_request  # Run PR workflows
act push          # Run push workflows
```

Note: Some features (GitHub Pages, releases) won't work locally.

## Security

### Token Permissions

Workflows use minimal permissions:

```yaml
permissions:
  contents: read        # Read repository
  pull-requests: write  # Comment on PRs
  pages: write          # Deploy to Pages
```

No custom secrets required. Uses auto-generated `GITHUB_TOKEN`.

### Dependabot PRs

Dependabot PRs have restricted permissions and must pass CI before merging.

## Monitoring

### Status Badges

Add to README:

```markdown
![CI](https://github.com/dowdiness/canopy/actions/workflows/ci.yml/badge.svg)
![Deploy](https://github.com/dowdiness/canopy/actions/workflows/deploy.yml/badge.svg)
```

### Notifications

Configure in **Settings** → **Notifications**:

- Email on workflow failure
- Slack/Discord webhooks (if desired)

## Future Improvements

Active follow-ups are tracked in `docs/TODO.md`. Current CI/CD-related gaps include:

- [ ] If wasm support is added later, add a dedicated target implementation and CI coverage
- [x] Run one canonical Playwright browser app in CI (`examples/demo-react`)
- [ ] Add code coverage reporting
- [ ] Add Docker builds for reproducible environments

## References

- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [MoonBit CLI Reference](https://docs.moonbitlang.com)
- [Workflow Files](../.github/workflows/)
- [TODO List](TODO.md)
