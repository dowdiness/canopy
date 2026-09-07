# Agent Environments

This guide owns host-specific configuration. Tool-specific instructions apply
only in their named host; use the active host's available tools and roles.
Repository validation and delegation rules live in [Workflow](workflow.md).

## Local MoonBit Guidance

If your environment provides `~/.claude/moonbit-base.md`, use it as supplementary
MoonBit guidance. It is not a prerequisite for other contributors. Repository
[validation scope](workflow.md#validation-scope) and
[reuse reporting scope](api-reuse.md#record-the-decision-once) replace per-file
checks, blanket workspace validation, and repeated reporting in that guidance.

## Pi Delegation Roles

Use these roles in pi. Other hosts use their own available agent roles:

- `mechanic`: rote edits, renames, import/path migrations, and repeated
  exact-pattern changes.
- `scout`: broad non-MoonBit reconnaissance or unfamiliar non-MoonBit areas.
- `moonbit-scout`: MoonBit/Canopy reconnaissance involving `.mbt`, `.mbti`,
  `moon.pkg`, `moon.mod` (`moon.mod.json` in legacy submodules), package roots, or `moon ide`.
- `planner`: non-MoonBit implementation planning after reconnaissance.
- `moonbit-planner`: MoonBit implementation planning requiring Existing API
  First, package-root validation, `.mbti` drift checks, proof/docs/TS/submodule
  awareness.
- `worker`: clear implementation tasks large enough to benefit from isolated
  execution; review its patch before continuing.
- `reviewer`: risky non-MoonBit changes, pre-merge review, or independent
  validation.
- `moonbit-reviewer`: MoonBit/Canopy API, package-boundary, validation, or
  `.mbti` review.

For current pi model assignments, use `~/.pi/agent/AGENTS.md`. Do not
apply those assignments to other hosts.

## Cursor Cloud specific instructions

These notes apply only to the provisioned Cursor Cloud VM. Check its current
tool versions and environment before relying on snapshot-specific assumptions.

The Cloud VM snapshot already has the toolchain installed and dependencies
refreshed by the startup update script (`git submodule update --init
--recursive`, `scripts/moon-update.sh`, `npm --prefix apps/web ci`). Do not
re-run the MoonBit installer; it is pinned in the snapshot.

Non-obvious caveats for this environment:

- **`NEW_MOON_MOD=0` is exported in `~/.bashrc`** (matches
  `.github/actions/setup-moonbit`). Every `moon` command relies on it — without
  it the `rr_moon_mod` TOML migration drops path fields from cross-repo deps.
  Login shells already have it; a bare non-login shell may not.
- **Node version:** use a version satisfying `apps/web/package.json`'s
  `engines.node`. Login and daemon shells may resolve different installations;
  verify the version in the shell that runs the web command.
- **Web dev server:** standard commands are in `apps/web/package.json`
  (`npm run dev` → Waku on `http://localhost:3000`) and the root `justfile`
  (`just build-js`, `just web-dev`). The Waku dev server runs its own MoonBit
  watcher and rebuilds the FFI (`ffi/{lambda,json,markdown,jsx}`) JS on change;
  a separate `just build-js` is only needed for non-dev consumers.
- `moon check` / `moon test` / `moon build` auto-download registry deps on first
  run, so the pre-warm in the update script is an optimization, not a hard
  prerequisite.
