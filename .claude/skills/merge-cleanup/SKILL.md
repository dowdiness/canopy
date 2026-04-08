# Merge & Cleanup Workflow

## Usage
`/merge-cleanup` or `/merge-cleanup <PR number>` — then follow the steps below.

## Steps

### Gate 1: CI verification (HARD GATE — do not proceed if this fails)

Run `gh pr checks <PR_NUMBER>` and display the **raw output** to the user. Do not summarize or paraphrase.

Then verify ALL of the following:
- Every check has status `pass` (not `pending`, `fail`, or `skipped`)
- No checks are missing or skipped — skipped is NOT passing
- If any check is not `pass`, **STOP** and report: "CI is not fully green. Blocking merge." List each non-passing check with its status.

Do NOT proceed to Gate 2 until all checks pass.

### Gate 2: Submodule sync check (HARD GATE)

Run: `git submodule foreach 'git diff --exit-code @{push}.. 2>/dev/null || echo "UNPUSHED: $name"'`

If any submodule has unpushed commits:
- **STOP** and report: "Submodule `<name>` has unpushed commits. Push submodule first, wait for CI, then retry."
- Do NOT proceed.

### Step 3: Merge

```bash
gh pr merge <PR_NUMBER> --squash --delete-branch
```

### Step 4: Switch to main and pull

```bash
git checkout main && git pull
```

### Step 5: Worktree cleanup

If a git worktree exists for this PR's branch, remove it:
```bash
git worktree list  # find the worktree
git worktree remove <path>
```

### Step 6: Archive the plan

If a plan file exists in `docs/plans/` for this work, move it to `docs/archive/` (NOT `docs/plans/archive/`).

### Step 7: Update docs

- Mark the item complete in `docs/TODO.md`
- Update any test counts in docs to match `moon test` output

### Step 8: Commit and push

```bash
git add -A
git commit -m "chore: post-merge cleanup for PR #<PR_NUMBER>"
git push
```

## Rules

- **Never merge with failing or skipped CI.** If the user insists, explain the risk and ask them to confirm explicitly.
- **Never claim CI is green without running `gh pr checks` and showing the output.**
- **Never push parent repo if submodules have unpushed commits.**
- Gates 1 and 2 are non-negotiable. Steps 5-7 are best-effort (skip if not applicable).
