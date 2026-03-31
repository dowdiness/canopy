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

Before starting medium or large work, decide the canonical tracking surface:

- use [Task Tracking](task-tracking.md) for the repo's tracking rules,
- create a plan in [`docs/plans/`](../plans/) from
  [TEMPLATE.md](../plans/TEMPLATE.md) when the task is non-trivial,
- keep [`docs/TODO.md`](../TODO.md) as the short active backlog index.

## Working with the Parser

The parser lives in `loom/examples/lambda/`. The framework is in `loom/loom/`. When modifying:

- Check error recovery behavior with malformed input
- Test incremental parsing with loom's test suites
- Benchmark performance with `cd loom/examples/lambda && moon bench --release`

## Working with the CRDT

The CRDT implementation is split across two modules:

**Core CRDT library (`event-graph-walker/`):**
- `causal_graph/graph.mbt` - Core graph operations
- `causal_graph/walker.mbt` - Topological traversal (eg-walker)
- `causal_graph/version_vector.mbt` - Version vector implementation
- `oplog/oplog.mbt` - Operation storage and retrieval
- `fugue/tree.mbt` - Sequence CRDT implementation
- `branch/branch.mbt` - Branch system
- `branch/branch_merge.mbt` - Merge operations
- `document/document.mbt` - Document model

**Application layer (crdt module):**
- `editor/editor.mbt` - Basic editor with cursor tracking
- `editor/sync_editor*.mbt` - Active editor facade and parser/sync/undo orchestration
- `editor/text_diff.mbt` - Text diffing utilities
- `lib/text-change/` - Shared leaf contiguous text-change module
- `text_change/` - Root compatibility adapter over the shared leaf

The shared `lib/text-change/` module is monorepo-local for now. Standalone
packaging for submodules that consume it is a follow-up after the API shape
stops moving.

When adding features, consult:
- [event-graph-walker/README.md](../../event-graph-walker/README.md)

## Web Development

```bash
# From the examples/web/ directory
cd examples/web
npm install
npm run dev        # Start development server (http://localhost:5173)
npm run build      # Build for production (multi-page: index.html + json.html)
npm run preview    # Preview production build
```

Two editor pages are available:
- **Lambda editor:** `http://localhost:5173/` — lambda calculus with AST visualization
- **JSON editor:** `http://localhost:5173/json.html` — structural JSON editing with tree view

### Updating Web JavaScript

After making changes to MoonBit code that affects the web interface:

```bash
# From the repo root
make build-js
```

## Git Commit Process

Only create commits when requested by the user. When asked to commit:

1. Run `git status` and `git diff` to see changes
2. Review changes and draft commit message
3. Add relevant files to staging area
4. Create commit with message ending in:
   ```
   Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>
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

moon test                   # Test crdt module
cd event-graph-walker && moon test  # Test CRDT library
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
cd event-graph-walker && moon bench --release

# Specific packages
cd loom/examples/lambda && moon bench --release
cd event-graph-walker
moon bench --package causal_graph --release
moon bench --package branch --release
```

See [benchmarks documentation](../performance/BENCHMARK_REDESIGN.md) for details.
