# CI/CD Setup Status

This document summarizes the current CI/CD infrastructure for the Canopy project and the follow-up cleanup completed after the 2026-03-21 automation audit.

## What's Been Implemented

### GitHub Actions Workflows

#### 1. CI Workflow (`.github/workflows/ci.yml`)
**Runs on:** Every push and pull request

**Features:**
- ✅ Tests main module through shared `make` entrypoints
- ✅ Tests all submodules in parallel (event-graph-walker, loom, svg-dsl, graphviz)
- ✅ Code quality checks with `make check`
- ✅ Format verification with `make fmt-check`
- ✅ JavaScript build verification with `make build-js`
- ✅ Web frontend build and testing
- ✅ Benchmark execution on PRs
- ✅ Single "all checks passed" status for easy merge decisions

#### 2. Benchmark Regression (`.github/workflows/benchmark.yml`)
**Runs on:** Pull requests

**Features:**
- ✅ Compares PR performance vs base branch
- ✅ Posts detailed comparison as PR comment
- ✅ Tests both main module and event-graph-walker through `scripts/run-moon-module.sh`
- ✅ Stores results as artifacts (30-day retention)

#### 3. Deploy to GitHub Pages (`.github/workflows/deploy.yml`)
**Runs on:** Push to main

**Features:**
- ✅ Builds shared MoonBit JS artifacts with `make build-js`
- ✅ Builds web frontend with `make build-web`
- ✅ Automatically deploys to GitHub Pages
- ✅ Future URL: `https://dowdiness.github.io/crdt/`

**Setup Required:**
- Go to Settings → Pages
- Set Source to "GitHub Actions"

#### 4. Release Automation (`.github/workflows/release.yml`)
**Runs on:** Git tags matching `v*.*.*`

**Features:**
- ✅ Full test suite execution
- ✅ Builds supported targets (native and JS)
- ✅ Creates `canopy-moonbit-*` and `canopy-web-*` archives
- ✅ Auto-generates changelog from commits
- ✅ Creates GitHub Release with downloadable artifacts

**Usage:**
```bash
git tag v0.2.0
git push origin v0.2.0
```

#### 5. Dependabot (`.github/dependabot.yml`)
**Runs:** Weekly

**Features:**
- ✅ Automatic GitHub Actions updates
- ✅ Automatic npm dependency updates (examples/web, examples/demo-react, valtio)
- ✅ Grouped updates for Playwright and Vite
- ✅ All updates tested by CI before merge

### Development Scripts

All scripts are in `scripts/` and are executable:

#### `build-web.sh`
Automates the web build workflow:
```bash
./scripts/build-web.sh
# Equivalent to:
# ./scripts/build-js.sh
# cd examples/web && npm run build
```

#### `test-all.sh`
Runs tests for all modules with pretty output:
```bash
./scripts/test-all.sh
# Tests: main, event-graph-walker, loom, svg-dsl, graphviz
```

#### `check-all.sh`
Runs quality checks for all modules:
```bash
./scripts/check-all.sh
# Runs shared check + fmt-check helpers per module
```

#### `run-moon-module.sh`
Shared entrypoint for root and submodule CI actions:
```bash
./scripts/run-moon-module.sh ci .
./scripts/run-moon-module.sh bench event-graph-walker
```

#### `build-js.sh`
Builds the canonical JS artifacts used by CI, deploy, release, and the web app:
```bash
./scripts/build-js.sh
```

#### `package-release.sh`
Creates release archives from current build outputs:
```bash
./scripts/package-release.sh v0.2.0
```

#### `install-hooks.sh`
Installs pre-commit hooks:
```bash
./scripts/install-hooks.sh
# Or use: make install-hooks
```

### Makefile

Convenient command wrapper for common tasks:

```bash
make help          # Show all available commands
make test          # Test main module
make test-all      # Test all modules
make check         # Check main module
make check-all     # Check all modules
make fmt           # Format code
make build         # Build main module
make build-js      # Build JavaScript
make build-web     # Build web app
make web-dev       # Start dev server
make clean         # Clean artifacts
make install-hooks # Install pre-commit hooks
make ci            # Run full CI locally
make update        # Update dependencies
make bench         # Run benchmarks
```

### Pre-commit Hooks

Installable with `make install-hooks`:

**Runs before each commit:**
- `make check` - Run root type checks
- `make fmt-check` - Detect formatting drift

**Prevents:**
- Committing unformatted code
- Committing code with linting errors
- CI failures due to formatting

### Documentation

#### New Documentation Files

1. **`.github/workflows/README.md`**
   - Quick reference for all workflows
   - Troubleshooting guide
   - Artifact retention info

2. **`docs/CI_CD.md`**
   - Comprehensive CI/CD documentation
   - Setup instructions
   - Troubleshooting guide
   - Performance optimization tips

3. **`docs/TODO.md`** (Updated)
   - Tracks completed automation cleanup
   - Tracks remaining CI/docs follow-up work

## Quick Start Guide

### For New Contributors

1. **Clone and setup:**
   ```bash
   git clone --recursive https://github.com/dowdiness/canopy.git
   cd canopy
   make install-hooks  # Install pre-commit hooks
   ```

2. **Make changes:**
   ```bash
   # Edit files
   make fmt           # Format
   make test-all      # Test
   ```

3. **Submit PR:**
   ```bash
   git commit -m "feat: add cool feature"
   git push
   # Open PR on GitHub
   # CI will automatically run all checks
   # Benchmark comparison will be posted as comment
   ```

### For Maintainers

**Deploy to production:**
```bash
git push origin main
# Automatically deploys to GitHub Pages
```

**Create a release:**
```bash
git tag v0.2.0
git push origin v0.2.0
# Automatically creates GitHub Release with artifacts
```

**Run full CI locally:**
```bash
make ci
# Runs all checks that CI would run
```

## Coverage of TODO.md Requirements

From `docs/TODO.md` Section 1 (CI/CD & Automation):

| Requirement | Status | Implementation |
|-------------|--------|----------------|
| GitHub Actions for `moon test` | ✅ Done | `ci.yml` |
| `moon check` in CI | ✅ Done | `ci.yml` - format-check job |
| `moon fmt --check` in CI | ✅ Done | `ci.yml` - format-check job |
| Benchmark regression detection | ✅ Done | `benchmark.yml` |
| JS build verification | ✅ Done | `ci.yml` - build-js job |
| **Bonus:** Deployment automation | ✅ Done | `deploy.yml` |
| **Bonus:** Release automation | ✅ Done | `release.yml` |
| **Bonus:** Dependency updates | ✅ Done | `dependabot.yml` |

From `docs/TODO.md` Section 7 (Developer Experience):

| Requirement | Status | Implementation |
|-------------|--------|----------------|
| Single-command test runner | ✅ Done | `Makefile`, `scripts/test-all.sh` |
| Pre-commit hook | ✅ Done | `scripts/install-hooks.sh` |
| Web build script | ✅ Done | `scripts/build-web.sh` |

## File Structure

```
.github/
├── workflows/
│   ├── ci.yml                  # Main CI workflow
│   ├── benchmark.yml           # Benchmark regression
│   ├── deploy.yml              # GitHub Pages deployment
│   ├── release.yml             # Release automation
│   ├── copilot-setup-steps.yml # Existing Copilot setup
│   └── README.md               # Workflow documentation
└── dependabot.yml              # Dependency updates

scripts/
├── build-js.sh                 # Shared JS artifact build
├── build-web.sh                # Web build automation
├── package-release.sh          # Release archive packaging
├── run-moon-module.sh          # Shared module runner
├── test-all.sh                 # Test all modules
├── check-all.sh                # Check all modules
└── install-hooks.sh            # Install git hooks

docs/
├── CI_CD.md                    # Comprehensive CI/CD docs
└── TODO.md                     # Tracks remaining follow-up work

Makefile                        # Development task runner
```

## Next Steps

### Immediate Actions

1. **Enable GitHub Pages:**
   - Go to Settings → Pages
   - Set Source to "GitHub Actions"
   - Save

2. **Test the workflows:**
   ```bash
   # Create a test branch and PR
   git checkout -b test/ci-setup
   git push -u origin test/ci-setup
   # Open PR on GitHub to trigger CI
   ```

3. **Install hooks locally:**
   ```bash
   make install-hooks
   ```

### Optional Enhancements

1. **Add status badges to README:**
   ```markdown
   ![CI](https://github.com/dowdiness/canopy/workflows/CI/badge.svg)
   ![Deploy](https://github.com/dowdiness/canopy/workflows/Deploy/badge.svg)
   ```

2. **Configure notifications:**
   - Settings → Notifications
   - Set up email/Slack for workflow failures

3. **Add baseline benchmark storage:**
   - Currently compares PR vs base branch
   - Could store historical baselines for trends

## Monitoring & Maintenance

**Check workflow status:**
- Go to Actions tab in GitHub
- View recent runs and their status

**Review Dependabot PRs:**
- Dependabot will create weekly PRs for updates
- CI will automatically test them
- Review and merge when tests pass

**Monitor artifact storage:**
- Current retention: 7-90 days depending on workflow
- GitHub provides 500MB free storage
- Current usage should be <100MB

## Troubleshooting

**If CI fails:**
1. Check the Actions tab for error logs
2. Run `make ci` locally to reproduce
3. Fix issues and push again

**If format check fails:**
```bash
make fmt
git add .
git commit -m "chore: format code"
```

**If benchmarks show regression:**
1. Review the benchmark comparison comment
2. Run `make bench` locally
3. Investigate if >10% slower
4. Document intentional trade-offs in PR

**If deployment fails:**
1. Verify GitHub Pages is enabled
2. Check that `examples/web/dist` is created
3. Review deploy.yml logs in Actions tab

## Success Criteria

Core CI/CD requirements from TODO.md are implemented, with follow-up audit items still tracked separately:

- ✅ Automated testing on push/PR
- ✅ Code quality enforcement
- ✅ Benchmark regression detection
- ✅ JS build verification
- ✅ Deployment automation
- ✅ Release automation
- ✅ Developer experience improvements

The project now has an operational CI/CD pipeline with shared entrypoints for CI, deploy, release, and benchmarks. Remaining gaps are tracked in `docs/TODO.md`, primarily around browser CI coverage and future optional wasm support.

## Documentation References

- **Workflow Details:** `.github/workflows/README.md`
- **Comprehensive Guide:** `docs/CI_CD.md`
- **TODO Status:** `docs/TODO.md`
- **GitHub Actions Docs:** https://docs.github.com/en/actions

---

**Setup completed:** 2026-02-01
