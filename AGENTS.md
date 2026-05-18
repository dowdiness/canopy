# Canopy — Agent Guidance

Incremental projectional editor with CRDT collaboration, built in MoonBit.

@~/.claude/moonbit-base.md

## Quick Commands

### Setup (after clone)
```bash
git clone --recursive https://github.com/dowdiness/canopy.git
# or if already cloned:
git submodule update --init --recursive
```

### Test & Build
```bash
# Workspace-root commands cover the canopy module + lib/text-change + lib/zipper +
# lib/btree + lib/moji (the five `moon.work` members).
moon test                           # All workspace members
moon check                          # Lint across workspace
moon info && moon fmt               # Format & update interfaces

# Submodules and example modules are NOT workspace members — still need fanout:
cd event-graph-walker && moon test  # CRDT library tests
cd loom/loom && moon test           # Parser framework tests
cd loom/seam && moon test           # CST library tests
cd loom/examples/lambda && moon test # Lambda parser tests
cd loom/examples/json && moon test
cd loom/examples/markdown && moon test
cd lib/semantic && moon test        # Semantic annotation tests (not a workspace member)
cd examples/ideal && moon test      # Ideal editor example (PR-gated in CI)
cd examples/block-editor && moon test
cd examples/canvas && moon test
```

The canonical CI fan-out is described in `.github/workflows/ci.yml`. Use that
file as the source of truth if this list drifts.

JS build artifacts are namespaced under the module path: `_build/js/release/build/dowdiness/canopy/ffi/{lambda,json,markdown}/...`. Vite configs, tsconfigs, `scripts/build-js.sh`, `scripts/package-release.sh`, and CI artifact uploads all reference this namespaced path.

### Web Development
```bash
cd examples/web && npm run dev      # Dev server (localhost:5173)
# Lambda editor:   http://localhost:5173/
# JSON editor:     http://localhost:5173/json.html
# Markdown editor: http://localhost:5173/markdown.html
moon build --target js              # Build for web
```

### Formal Verification
```bash
cd lib/semantic/proof && moon prove  # Requires Why3 + z3 on PATH
```
Proof packages are standalone modules with `"proof-enabled": true`. Run `moon prove` from within the proof package directory. Requires Why3 1.7.2 and z3 4.13.x on PATH (`eval $(opam env)`). See [docs/development/formal-verification.md](docs/development/formal-verification.md) for setup and decision guide.

### Benchmarks
```bash
moon bench --release                # Always use --release
cd event-graph-walker && moon bench --release
cd loom/examples/lambda && moon bench --release
```

## Submodule Workflow

### Updating submodules
```bash
git submodule update --remote        # Pull latest from all submodules
git add event-graph-walker loom      # Stage submodule pointer updates
git commit -m "chore: update submodules"
```

### Making changes to a submodule
```bash
cd event-graph-walker
# make changes, commit, push
cd ..
git add event-graph-walker
git commit -m "chore: update event-graph-walker submodule"
```

## Rabbita Conventions

Rabbita is vendored at `./rabbita/` (fork of `moonbit-community/rabbita`
with the `diff_subs` `update_tagger` patch applied — see
`docs/plans/2026-05-18-codemirror-rabbita-binding-phase2.md` §P2.0).

When designing, implementing, or reviewing code that uses `@sub`,
`@cmd`, `@html`, `@dom`, `@http`, `custom_sub`, `suberror`, or that
authors / modifies a rabbita binding (`lib/rabbita_codemirror`, future
libraries): **the files under `rabbita/doc/*` and
`rabbita/rabbita/*/{README.mbt.md,design.md}` are authoritative.** Read
them before designing. Cite the specific paths you used.

If rabbita docs disagree with older `docs/plans/*.md` or with a spec
the user pasted, the rabbita docs win — revise the plan, not the
implementation.

The `.claude/skills/rabbita` skill auto-invokes on rabbita-related
prompts and contains the doc reading checklist + inline idiom rules +
canonical binding patterns. Invoke manually with `/rabbita` if needed.

## Adding a New Language

See [docs/development/ADDING_A_LANGUAGE.md](docs/development/ADDING_A_LANGUAGE.md) for the full guide (7 steps, with templates and validation checkpoints). Use Markdown as the reference implementation, not Lambda.

## Package Map

The SessionStart hook runs `scripts/package-overview.sh` which provides a live package map at the start of every session. Use `moon ide outline <path>` to explore any package's public API before modifying it. Read `moon.mod.json` for module dependencies.

## Documentation

Browse `docs/` for architecture, decisions, development guides, and performance snapshots. Key rules:

- Architecture docs = principles only, never reference specific types/fields/lines
- Code is the source of truth — if a doc and the code disagree, the doc is wrong
- `docs/TODO.md` = active backlog index; `docs/plans/*.md` = execution specs
- `docs/archive/` = completed work. Do not search here unless asked for historical context.

## Development Workflow

### UI / Visual Feature Rule

**CRITICAL:** Prototype first, plan later. Build the smallest working change, test it in the browser, then iterate. Don't batch-build UI via subagents — tightly-coupled UI needs human-in-the-loop feedback. When the user questions value, stop and validate before continuing.

### Performance Optimization (project-specific addendum)

The base rule (microbenchmark before optimizing) applies. Additionally: stale profiling data from before prior optimizations is not evidence. Check if existing mitigations (batch modes, caching, lazy eval) already neutralize the issue before proposing new ones.

### Quality & Edit Workflow

Hooks enforce `moon check` after every edit and `moon fmt && moon info` before commits. After edits, also run `moon test` and rebuild JS if web is affected. For packages with `"proof-enabled": true`, also run `moon prove` from the proof package directory. After `moon info`, check `git diff *.mbti` for unintended trait bound changes — widening a bound is an API regression even if all current consumers satisfy it. See [docs/development/task-tracking.md](docs/development/task-tracking.md) for tracking workflow.

## Architecture Conventions

- When adding shared content, use symlinks or references to a single source of truth. Never embed copies of shared files — flag the duplication problem first.
- **Cross-package struct construction:** MoonBit's `pub struct` fields are read-only from outside the defining package. To construct or mutate fields cross-package, the struct must be `pub(all)` or have a named constructor. Verify this before planning any cross-package type migration.
- **Test ownership:** Each package tests its own logic only. Trust imported libraries' correctness by interface contract. When migrating code between packages, delete tests that now test the wrong module — track upstream test debt in the imported package's backlog.

## Model Routing

Route tasks based on judgment complexity, not importance.

| Task type | Model | Mechanism |
|-----------|-------|-----------|
| Architecture, novel design, debugging wrong approaches | Opus | Direct (default) |
| Implementation (50+ lines, clear spec) | Sonnet | `Agent(model: "sonnet")` |
| Code review (pre-merge) | Sonnet | `/parallel-review` or `Agent(subagent_type: "code-reviewer")` |
| Mechanical (renames, formatting, rote migration) | Haiku | `Agent(model: "haiku")` |
| Under 50 lines, 1-3 files | Current model | No delegation — implement inline |

**Delegation requires clear scope.** If you can't list the exact files to modify, research first. Vague delegation wastes the agent's time exploring.

**Use `/delegate` skill** before composing Agent prompts for non-trivial delegation. It provides the handoff format and task-type templates.

## Code Review Expectations

- Expect Codex/CodeRabbit reviews on every PR — proactively check for common issues before submitting: correct API usage (e.g., get_result() not read(), get() not peek()), missed callers when refactoring, variant semantics preserved
- Run format checks and full test suite before pushing

## Git & PR Workflow

- After rebase operations, verify files are in the correct directories
- When asked to 'commit remaining files', interpret generously even if phrasing is unclear
- **NEVER merge PRs until CI is fully green.** Run `gh pr checks <NUMBER>` and show the raw output — do not summarize or paraphrase. If any check is `pending`, `fail`, or `skipped`, STOP and report the exact status. Skipped is NOT passing. Do not claim CI is green without verifying.
- After rebasing or refactoring, verify file paths haven't shifted unexpectedly. Run `git diff --stat` to confirm only intended files changed.
- When making changes across submodules, always push submodule commits to remote BEFORE pushing the parent repo or creating parent PRs. CI will fail if submodule commits aren't available on remote.
- Always use PRs for submodule changes — never push directly to main branches of submodules without asking first.

## Design Context

**Personality:** Elegant, Thoughtful, Deep — beauty emerging from structure.

**References:** Zed Editor, Dark/Luna, Strudel (strudel.cc)

**Anti-references:** Generic SaaS, toy/playground aesthetics.

**Design Principles:**
1. **Structure reveals meaning** — color, spacing, nesting communicate relationships before labels
2. **Progressive disclosure** — clean and focused by default, reveal depth on demand
3. **Typography carries weight** — Inter (UI) vs JetBrains Mono (code) creates clear zones
4. **Color is semantic, not decorative** — every color means something, no color without purpose
5. **Calm confidence** — solid and trustworthy, never frantic. Subtle transitions, generous whitespace

**Palette:** Deep navy base (`#1a1a2e`), purple accent (`#8250df`), syntax colors: keyword `#c792ea`, identifier `#82aaff`, number `#f78c6c`, string `#c3e88d`, operator `#ff5370`

See `.impeccable.md` for full design tokens and context.

## References

- [eg-walker paper](https://arxiv.org/abs/2409.14252)
- [MoonBit docs](https://docs.moonbitlang.com)
- [Full documentation](docs/)
