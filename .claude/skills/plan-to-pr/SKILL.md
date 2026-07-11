# Plan-to-PR Workflow

Autonomous execution of a multi-phase implementation plan through to a merged PR.

## Usage
`/plan-to-pr` — then specify the plan file.

## Prompt Template
```
Read the implementation plan at docs/plans/[plan-name].md. For each phase:
1) Create a git worktree for a feature branch,
2) Implement all tasks in that phase,
3) Run the full test suite after each file change and fix any failures,
4) When all tests pass, commit with a descriptive message.
After all phases are complete, open a PR with a summary of changes and test
results. If any phase has more than 3 consecutive test failures on the same
issue, stop and report what you've tried.
```

## Steps

1. Read the plan at `docs/plans/<name>.md` — confirm phases and scope before touching code
2. For each phase:
   a. Create a git worktree: `git worktree add .claude/worktrees/<branch> -b <branch>`
   b. Implement all tasks in the phase
   c. After **every file edit**, run `moon check` — fix errors immediately before the next edit
   d. After all edits in the phase, run `moon test` — fix any failures before continuing
   e. When all tests pass, commit with a descriptive message scoped to the phase
3. After all phases complete, open a PR:
   - Title: concise description of the overall change
   - Body: per-phase summary + final test results (`moon test` output)
4. If the same issue causes 3+ consecutive test failures, stop and report:
   - What the issue is
   - What you tried
   - Where you are in the plan

## Guardrails

- Never skip `moon check` between file edits
- Never commit with failing tests
- Never represent CI as green if any checks are skipped or failed
- Archive the plan to `docs/archive/` only after the PR is merged (via `/merge-cleanup`)
