# Development Workflow

## Making Changes to MoonBit Code

1. Make your edits
2. Run `moon check` to lint
3. Run `moon test` to verify tests pass
4. If behavior changed intentionally: `moon test --update` to update snapshots
5. Run `moon info` to update `.mbti` interface files
6. Check git diff on `.mbti` files to verify expected changes
7. Run `moon fmt` to format
8. If the web interface is affected, rebuild the shared JS artifacts

## Working with Submodules

See [Monorepo & Submodules](monorepo.md) for the full guide on the git submodule setup, daily workflows, and common pitfalls.

## Paying Technical Debt

Before patching around a design problem locally, check
[Paying Technical Debt](technical-debt.md).

The short version:

- fix missing CRDT/parser APIs in the owning submodule,
- keep only one active editor architecture,
- centralize shared logic once,
- isolate any unavoidable workaround in a single helper with a comment naming
  the missing upstream API.

## Tracking Work

GitHub Issues is the canonical active backlog:

- follow [Task Tracking](task-tracking.md) for issue and plan ownership,
- search [open and closed issues](https://github.com/dowdiness/canopy/issues)
  before claiming work,
- create a plan in [`docs/plans/`](../plans/) from
  [TEMPLATE.md](../plans/TEMPLATE.md) when implementation is non-trivial, then
  link the issue and plan in both directions.

## Working with the Parser

The parser lives in `deps/loom/examples/lambda/`. The framework is in
`deps/loom/loom/`. When modifying:

- Check error recovery behavior with malformed input
- Test incremental parsing with loom's test suites
- Benchmark performance with `cd deps/loom/examples/lambda && moon bench --release`

## Working with the CRDT

The CRDT implementation is split across two modules:

**Core CRDT library (`deps/event-graph-walker/`):**
Causal graph (graph ops, eg-walker traversal, version vectors), operation log,
FugueMax sequence CRDT, branch system with merge, and document model.
See `deps/event-graph-walker/README.md` for the full package map.

**Application layer (`modules/canopy`):**
- `modules/canopy/editor/sync_editor*.mbt` - Active editor facade and parser/sync/undo orchestration
- `modules/canopy/editor/text_diff.mbt` - Text diffing utilities
- `deps/loom/text-change/` - Shared leaf contiguous text-change module

The shared `text-change` module now lives in the `deps/loom` submodule so parser
and editor packages resolve the same leaf dependency.

When adding features, consult:
- [event-graph-walker/README.md](../../deps/event-graph-walker/README.md)

## Web Development

The web demo is a Waku application served through Cloudflare Workers.
Canonical routes: `/`, `/ml`, `/json`, `/markdown`, `/journey`, `/posts`, `/memo`, `/resume`, `/genui`.
Legacy `.html` URLs return permanent redirects to their canonical route (except `/index.html`, which renders the Hub without redirect).

```bash
# From the apps/web/ directory
cd apps/web
npm install
npm run dev        # Start Waku dev server (http://localhost:3000)
npm run build      # Build Waku for production
npm run preview    # Preview production build
```

### Updating Web JavaScript

After making changes to MoonBit code that affects the web interface:

```bash
# From the repo root
just build-js
```

## Git Commit Process

Only create commits when requested by the user. When asked to commit:

1. Run `git status` and `git diff` to see changes
2. Review changes and draft commit message
3. Add relevant files to staging area
4. Create commit with message ending in:
   ```
   Co-Authored-By: Claude <model> <noreply@anthropic.com>
   ```
5. Run `git status` after commit to verify

**Important:**
- Never use `git commit --amend` unless user explicitly requests it
- Never push unless explicitly requested
- Never use `-i` flag (interactive mode not supported)

## Pull Request Process

When creating a pull request:

1. Run `git status` and `git diff` to understand changes
2. Check branch divergence from main with `git log`
3. Draft PR summary based on all commits (not just latest)
4. Push to remote with `-u` flag if needed
5. Create PR using `gh pr create` with HEREDOC format
6. Return PR URL

## Common Commands

### Build & Test
```bash
moon build                  # Build all
moon build --target js      # JavaScript build

moon test                   # Test Canopy and all root workspace members
moon test --update          # Update test snapshots
moon coverage analyze > uncovered.log  # Coverage
```

### Formatting & Linting
```bash
moon fmt                    # Format code
moon check                  # Lint code
moon info                   # Update .mbti interfaces
moon info && moon fmt       # Recommended before commit
```

### Benchmarking
```bash
# Always use --release for accurate measurements
moon bench --release
cd deps/event-graph-walker && moon bench --release

# Specific packages
cd deps/loom/examples/lambda && moon bench --release
cd deps/event-graph-walker
moon bench --package causal_graph --release
moon bench --package branch --release
```

See [benchmarks documentation](../performance/BENCHMARK_REDESIGN.md) for details.
