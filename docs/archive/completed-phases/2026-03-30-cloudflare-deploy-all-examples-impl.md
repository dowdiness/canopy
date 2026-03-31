# Deploy All Examples to Cloudflare — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deploy all 8 examples to Cloudflare via a single GitHub Actions matrix workflow, replacing the existing GitHub Pages deployment.

**Architecture:** One `.github/workflows/deploy-cloudflare.yml` with `strategy.matrix.include` — each entry defines its build commands, deploy directory, and Cloudflare project name. 7 entries use `wrangler pages deploy` (static sites), 1 uses `wrangler deploy` (Workers).

**Tech Stack:** GitHub Actions, Cloudflare Pages/Workers, Wrangler CLI, MoonBit, Node.js 20, npm, Vite

**Spec:** `docs/plans/2026-03-30-cloudflare-deploy-all-examples.md`

---

## File Map

| Action | File | Responsibility |
|--------|------|---------------|
| Create | `examples/prosemirror/wrangler.jsonc` | Cloudflare Pages config |
| Create | `examples/demo-react/wrangler.jsonc` | Cloudflare Pages config |
| Create | `examples/block-editor/web/wrangler.jsonc` | Cloudflare Pages config |
| Create | `examples/canvas/web/wrangler.jsonc` | Cloudflare Pages config |
| Create | `.github/workflows/deploy-cloudflare.yml` | Matrix deploy workflow |
| Edit | `examples/web/wrangler.jsonc` | Rename project |
| Edit | `examples/ideal/web/wrangler.jsonc` | Rename project |
| Edit | `examples/rabbita/wrangler.jsonc` | Rename project |
| Edit | `examples/rabbita/package.json` | Remove `packageManager` field |
| Edit | `examples/rabbita/scripts/build.sh` | Replace bun with npm |
| Edit | `examples/ideal/web/package.json` | Fix `prebuild:moonbit` path |
| Delete | `examples/rabbita/bun.lock` | Remove bun lock file |
| Delete | `.github/workflows/deploy.yml` | Remove GitHub Pages workflow |

---

### Task 1: Create missing wrangler.jsonc files

**Files:**
- Create: `examples/prosemirror/wrangler.jsonc`
- Create: `examples/demo-react/wrangler.jsonc`
- Create: `examples/block-editor/web/wrangler.jsonc`
- Create: `examples/canvas/web/wrangler.jsonc`

- [ ] **Step 1: Create `examples/prosemirror/wrangler.jsonc`**

```jsonc
{
  "name": "canopy-prosemirror",
  "compatibility_date": "2026-03-30",
  "assets": {
    "directory": "dist"
  }
}
```

- [ ] **Step 2: Create `examples/demo-react/wrangler.jsonc`**

```jsonc
{
  "name": "canopy-demo-react",
  "compatibility_date": "2026-03-30",
  "assets": {
    "directory": "dist"
  }
}
```

- [ ] **Step 3: Create `examples/block-editor/web/wrangler.jsonc`**

```jsonc
{
  "name": "canopy-block-editor",
  "compatibility_date": "2026-03-30",
  "assets": {
    "directory": "dist"
  }
}
```

- [ ] **Step 4: Create `examples/canvas/web/wrangler.jsonc`**

```jsonc
{
  "name": "canopy-canvas",
  "compatibility_date": "2026-03-30",
  "assets": {
    "directory": "dist"
  }
}
```

- [ ] **Step 5: Verify all four files exist**

Run:
```bash
for d in examples/prosemirror examples/demo-react examples/block-editor/web examples/canvas/web; do
  test -f "$d/wrangler.jsonc" && echo "OK: $d/wrangler.jsonc" || echo "MISSING: $d/wrangler.jsonc"
done
```
Expected: All four print "OK".

- [ ] **Step 6: Commit**

```bash
git add examples/prosemirror/wrangler.jsonc examples/demo-react/wrangler.jsonc \
       examples/block-editor/web/wrangler.jsonc examples/canvas/web/wrangler.jsonc
git commit -m "chore: add wrangler.jsonc for prosemirror, demo-react, block-editor, canvas"
```

---

### Task 2: Rename existing wrangler project names

**Files:**
- Modify: `examples/web/wrangler.jsonc`
- Modify: `examples/ideal/web/wrangler.jsonc`
- Modify: `examples/rabbita/wrangler.jsonc`

- [ ] **Step 1: Update `examples/web/wrangler.jsonc`**

Change `"name": "lambda-editor"` to `"name": "canopy-lambda-editor"`. Full file:

```jsonc
{
  "name": "canopy-lambda-editor",
  "compatibility_date": "2026-01-04",
  "assets": {
    "directory": "dist"
  }
}
```

- [ ] **Step 2: Update `examples/ideal/web/wrangler.jsonc`**

Change `"name": "canopy"` to `"name": "canopy-ideal"`. Full file:

```jsonc
{
  "name": "canopy-ideal",
  "compatibility_date": "2026-01-04",
  "pages_build_output_dir": "dist"
}
```

- [ ] **Step 3: Update `examples/rabbita/wrangler.jsonc`**

Change `"name": "rabbita-projectional-editor"` to `"name": "canopy-rabbita"`. Full file:

```jsonc
{
  "name": "canopy-rabbita",
  "compatibility_date": "2026-03-10",
  "assets": {
    "directory": "./dist",
    "not_found_handling": "single-page-application"
  }
}
```

- [ ] **Step 4: Verify all three names**

Run:
```bash
grep '"name"' examples/web/wrangler.jsonc examples/ideal/web/wrangler.jsonc examples/rabbita/wrangler.jsonc
```
Expected:
```
examples/web/wrangler.jsonc:  "name": "canopy-lambda-editor",
examples/ideal/web/wrangler.jsonc:  "name": "canopy-ideal",
examples/rabbita/wrangler.jsonc:  "name": "canopy-rabbita",
```

- [ ] **Step 5: Commit**

```bash
git add examples/web/wrangler.jsonc examples/ideal/web/wrangler.jsonc examples/rabbita/wrangler.jsonc
git commit -m "chore: standardize Cloudflare project names with canopy- prefix"
```

---

### Task 3: Standardize rabbita on npm

**Files:**
- Modify: `examples/rabbita/package.json`
- Modify: `examples/rabbita/scripts/build.sh`
- Delete: `examples/rabbita/bun.lock`

- [ ] **Step 1: Remove `packageManager` field from `examples/rabbita/package.json`**

Current file:
```json
{
  "packageManager": "bun@1.2.15",
  "scripts": {
    "dev": "vite",
    "build": "sh scripts/build.sh",
    "build:deploy": "CI=true sh scripts/build.sh"
  },
  "type": "module",
  "dependencies": {
    "@rabbita/vite": "^0.1.0"
  }
}
```

Remove the `"packageManager": "bun@1.2.15",` line. Result:
```json
{
  "scripts": {
    "dev": "vite",
    "build": "sh scripts/build.sh",
    "build:deploy": "CI=true sh scripts/build.sh"
  },
  "type": "module",
  "dependencies": {
    "@rabbita/vite": "^0.1.0"
  }
}
```

- [ ] **Step 2: Update `examples/rabbita/scripts/build.sh` to use npm**

Replace the final line `exec vite build` (which relies on bun's PATH) with
`npx vite build`. Full file:

```sh
#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT_ROOT=$(dirname "$SCRIPT_DIR")
EXAMPLES_ROOT=$(dirname "$PROJECT_ROOT")
REPO_ROOT=$(dirname "$EXAMPLES_ROOT")

ensure_moon() {
  if command -v moon >/dev/null 2>&1; then
    return
  fi

  if [ -x "$HOME/.moon/bin/moon" ]; then
    export PATH="$HOME/.moon/bin:$PATH"
    return
  fi

  echo "==> Installing MoonBit CLI..."
  curl -fsSL https://cli.moonbitlang.com/install/unix.sh | bash
  export PATH="$HOME/.moon/bin:$PATH"
}

ensure_submodules() {
  if [ -f "$REPO_ROOT/loom/loom/moon.mod.json" ] \
    && [ -f "$REPO_ROOT/loom/examples/lambda/moon.mod.json" ] \
    && [ -f "$REPO_ROOT/event-graph-walker/moon.mod.json" ]; then
    return
  fi

  echo "==> Initializing git submodules..."
  (
    cd "$REPO_ROOT"
    git submodule update --init --recursive
  )
}

ensure_moon
ensure_submodules

if [ "${CI:-}" = "true" ] || [ ! -d "$REPO_ROOT/.mooncakes" ] || [ ! -d "$PROJECT_ROOT/.mooncakes" ]; then
  echo "==> Resolving MoonBit dependencies (repo root)..."
  (
    cd "$REPO_ROOT"
    moon update
  )

  echo "==> Resolving MoonBit dependencies (examples/rabbita)..."
  (
    cd "$PROJECT_ROOT"
    moon update
  )
fi

echo "==> Building Rabbita app..."
npx vite build
```

- [ ] **Step 3: Delete `examples/rabbita/bun.lock`**

Run:
```bash
rm examples/rabbita/bun.lock
```

- [ ] **Step 4: Verify npm ci works for rabbita**

Run:
```bash
cd examples/rabbita && npm ci
```
Expected: Installs without errors. If `package-lock.json` is stale, run
`npm install` instead to regenerate it, then verify with `npm ci`.

- [ ] **Step 5: Commit**

```bash
git add examples/rabbita/package.json examples/rabbita/scripts/build.sh
git rm examples/rabbita/bun.lock
git commit -m "chore(rabbita): standardize on npm, remove bun dependency"
```

---

### Task 4: Fix ideal prebuild:moonbit path

**Files:**
- Modify: `examples/ideal/web/package.json`

- [ ] **Step 1: Fix the `prebuild:moonbit` script**

In `examples/ideal/web/package.json`, change:
```json
"prebuild:moonbit": "cd ../.. && moon build --target js",
```
to:
```json
"prebuild:moonbit": "cd .. && moon build --target js",
```

`examples/ideal/web/` → `cd ../..` = `examples/` (wrong).
`examples/ideal/web/` → `cd ..` = `examples/ideal/` (correct — has its own `moon.mod.json`).

- [ ] **Step 2: Verify the path resolves correctly**

```bash
cd examples/ideal/web && cd .. && test -f moon.mod.json && echo "OK: resolves to ideal module root"
```
Expected: `OK: resolves to ideal module root`

- [ ] **Step 3: Commit**

```bash
git add examples/ideal/web/package.json
git commit -m "fix(ideal): correct prebuild:moonbit path to resolve to ideal module root"
```

---

### Task 5: Create the Cloudflare deploy workflow

**Files:**
- Create: `.github/workflows/deploy-cloudflare.yml`

- [ ] **Step 1: Create `.github/workflows/deploy-cloudflare.yml`**

```yaml
name: Deploy to Cloudflare

on:
  push:
    branches: [main]
  workflow_dispatch:

concurrency:
  group: "cloudflare-deploy"
  cancel-in-progress: false

jobs:
  deploy:
    name: Deploy ${{ matrix.name }}
    runs-on: ubuntu-latest
    strategy:
      fail-fast: false
      matrix:
        include:
          - name: web
            project-name: canopy-lambda-editor
            type: pages
            moon-update: |
              moon update
              cd graphviz && moon update
            moon-build: |
              moon build --target js --release
              cd graphviz && moon build --target js --release
            npm-dir: examples/web
            deploy-dir: examples/web/dist

          - name: rabbita
            project-name: canopy-rabbita
            type: pages
            moon-update: |
              moon update
              cd examples/rabbita && moon update
            moon-build: moon build --target js --release
            npm-dir: examples/rabbita
            deploy-dir: examples/rabbita/dist

          - name: ideal
            project-name: canopy-ideal
            type: pages
            moon-update: cd examples/ideal && moon update
            moon-build: cd examples/ideal && moon build --target js --release
            npm-dir: examples/ideal/web
            deploy-dir: examples/ideal/web/dist

          - name: prosemirror
            project-name: canopy-prosemirror
            type: pages
            moon-update: moon update
            moon-build: moon build --target js --release
            npm-dir: examples/prosemirror
            deploy-dir: examples/prosemirror/dist

          - name: demo-react
            project-name: canopy-demo-react
            type: pages
            moon-update: moon update
            moon-build: moon build --target js --release
            npm-dir: examples/demo-react
            deploy-dir: examples/demo-react/dist

          - name: block-editor
            project-name: canopy-block-editor
            type: pages
            moon-update: cd examples/block-editor && moon update
            moon-build: cd examples/block-editor && moon build --target js --release
            npm-dir: examples/block-editor/web
            deploy-dir: examples/block-editor/web/dist

          - name: canvas
            project-name: canopy-canvas
            type: pages
            moon-update: cd examples/canvas && moon update
            moon-build: cd examples/canvas && moon build --target js --release
            npm-dir: examples/canvas/web
            deploy-dir: examples/canvas/web/dist

          - name: relay-server
            project-name: canopy-relay
            type: workers
            moon-update: moon update
            moon-build: moon build --target js --release
            npm-dir: examples/relay-server
            deploy-dir: ""

    steps:
      - name: Checkout code
        uses: actions/checkout@v4
        with:
          submodules: recursive

      - name: Set up MoonBit
        if: matrix.moon-build != ''
        run: |
          curl -fsSL https://cli.moonbitlang.com/install/unix.sh | bash
          echo "$HOME/.moon/bin" >> $GITHUB_PATH

      - name: Update MoonBit dependencies
        if: matrix.moon-update != ''
        run: ${{ matrix.moon-update }}

      - name: Build MoonBit modules
        if: matrix.moon-build != ''
        run: ${{ matrix.moon-build }}

      - name: Setup Node.js
        uses: actions/setup-node@v6
        with:
          node-version: "20"
          cache: "npm"
          cache-dependency-path: ${{ matrix.npm-dir }}/package-lock.json

      - name: Install npm dependencies
        run: cd ${{ matrix.npm-dir }} && npm ci

      - name: Build
        if: matrix.type == 'pages'
        run: cd ${{ matrix.npm-dir }} && npx vite build

      - name: Deploy to Cloudflare Pages
        if: matrix.type == 'pages'
        run: npx wrangler pages deploy ${{ matrix.deploy-dir }} --project-name ${{ matrix.project-name }}
        env:
          CLOUDFLARE_API_TOKEN: ${{ secrets.CLOUDFLARE_API_TOKEN }}
          CLOUDFLARE_ACCOUNT_ID: ${{ secrets.CLOUDFLARE_ACCOUNT_ID }}

      - name: Deploy to Cloudflare Workers
        if: matrix.type == 'workers'
        run: cd ${{ matrix.npm-dir }} && npx wrangler deploy
        env:
          CLOUDFLARE_API_TOKEN: ${{ secrets.CLOUDFLARE_API_TOKEN }}
          CLOUDFLARE_ACCOUNT_ID: ${{ secrets.CLOUDFLARE_ACCOUNT_ID }}
```

- [ ] **Step 2: Verify YAML syntax**

Run:
```bash
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/deploy-cloudflare.yml'))" && echo "YAML OK"
```
Expected: `YAML OK`

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/deploy-cloudflare.yml
git commit -m "ci: add Cloudflare deploy workflow for all examples"
```

---

### Task 6: Remove GitHub Pages workflow

**Files:**
- Delete: `.github/workflows/deploy.yml`

- [ ] **Step 1: Delete the file**

```bash
git rm .github/workflows/deploy.yml
```

- [ ] **Step 2: Verify it's gone**

```bash
test ! -f .github/workflows/deploy.yml && echo "OK: deploy.yml removed"
```
Expected: `OK: deploy.yml removed`

- [ ] **Step 3: Commit**

```bash
git commit -m "ci: remove GitHub Pages deploy workflow (replaced by Cloudflare)"
```

---

### Task 7: Run full validation

- [ ] **Step 1: Run the validation script from the spec**

```bash
# Verify all wrangler configs exist
for d in examples/web examples/rabbita examples/ideal/web examples/prosemirror \
         examples/demo-react examples/block-editor/web examples/canvas/web; do
  test -f "$d/wrangler.jsonc" && echo "OK: $d/wrangler.jsonc" || echo "MISSING: $d/wrangler.jsonc"
done
test -f examples/relay-server/wrangler.toml && echo "OK: relay-server/wrangler.toml"

# Verify bun.lock removed
test ! -f examples/rabbita/bun.lock && echo "OK: bun.lock removed"

# Verify deploy.yml removed
test ! -f .github/workflows/deploy.yml && echo "OK: deploy.yml removed"

# Verify rabbita package.json has no packageManager field
! grep -q '"packageManager"' examples/rabbita/package.json && echo "OK: no packageManager"

# Verify ideal prebuild resolves correctly
grep 'cd \.\.' examples/ideal/web/package.json | head -1
```

Expected: All checks print "OK".

- [ ] **Step 2: Verify YAML is valid**

```bash
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/deploy-cloudflare.yml'))" && echo "YAML OK"
```

- [ ] **Step 3: Review git diff for the full changeset**

```bash
git log --oneline -6
git diff --stat HEAD~6..HEAD
```

Verify: 6 commits, only expected files changed.
