---
name: delegate
description: "Standardize delegation from Opus to Sonnet/Haiku agents. Use when about to spawn an Agent() for implementation, debugging, review, or mechanical tasks. Provides routing checklist, handoff format, and task-type templates."
---

# Delegation Skill

Route tasks to the right model. Compose structured Agent prompts.
Review results before integrating.

## Routing Checklist

Before composing an Agent prompt, verify:

1. **Is delegation worth it?**
   - < 50 lines, 1-3 files -> implement directly (no delegation)
   - 50+ lines, clear spec -> delegate to Sonnet
   - Mechanical/rote -> delegate to Haiku
   - Architecture/debugging wrong approach -> keep on Opus

2. **Is the scope clear?**
   - Can you list the exact files to modify? -> Ready to delegate
   - "Somewhere in the codebase" -> Not ready. Research first, then delegate.

3. **Are there parallel opportunities?**
   - 3+ independent sub-tasks -> Dispatch Sonnet agents in parallel
   - Tasks share state/files -> Sequential, single agent

## Handoff Format

Every Agent prompt uses these sections (omit irrelevant ones):

```
## Objective
[One sentence: what the agent must accomplish]

## Scope
- Modify: [file list]
- Read for context: [file list]
- Do NOT touch: [boundary list]

## Context
[Code snippets, API surfaces, recent changes — enough to work without exploring]

## Constraints
- Run `moon check` after every file edit
- Run `moon test` after all edits complete
- [Additional project-specific constraints]

## Unknowns
[Things to flag, not resolve]

## Output
Return: summary of changes, test results, decisions made, flagged unknowns
```

For Haiku (mechanical tasks), use the short form:

```
## Task — ## Files — ## Pattern (show one example) — ## Verify (exact command)
```

## Templates

### Implementation

Use when Sonnet should build a feature or add functionality.

```
Agent({
  description: "[3-5 word summary]",
  model: "sonnet",
  prompt: `## Objective
Implement [feature] in [package].

## Scope
- Modify: [list .mbt files]
- Read: [list files for API context]
- Do NOT modify: [packages outside scope]

## Context
[Paste relevant type definitions, function signatures, patterns to follow.
Include the .mbti interface of packages the agent will call.]

## Constraints
- Run moon check after every file edit
- Follow patterns in [reference file] for style
- Use [specific types/constructors] — do not invent new ones
- Write tests in [package]_test.mbt (blackbox) or _wbtest.mbt (whitebox)

## Output
Return: files changed, test results (moon test output), API changes (moon info diff)`
})
```

### Debugging

Use when Sonnet should find and fix a specific bug.

```
Agent({
  description: "[3-5 word summary]",
  model: "sonnet",
  prompt: `## Objective
Fix: [describe the bug — what happens vs what should happen]

## Reproduction
[Exact steps, test command, or error message]

## Scope
- Likely root cause in: [files/packages]
- Do NOT modify: [unrelated packages]

## Context
[Paste the error output, relevant code around the failure point]

## Constraints
- Find the root cause before changing code
- Run the failing test after fix to verify: [exact command]
- Run full suite: moon test
- Do not "fix" by weakening the test — fix the implementation

## Output
Return: root cause explanation, fix description, test results`
})
```

### Review

Use when Sonnet should review code for quality. For full pre-merge review,
use /parallel-review instead (4 specialized agents).

```
Agent({
  description: "[3-5 word summary]",
  model: "sonnet",
  subagent_type: "superpowers:code-reviewer",
  prompt: `## Objective
Review [branch/PR/files] for [correctness / API design / specific concern].

## Scope
- Review: [file list or git diff range]
- Focus on: [specific aspect — types, error handling, performance, etc.]

## Context
[What the code is supposed to do. What changed and why.]

## Checklist
- [ ] Types correct and minimal (no unnecessary pub(all))
- [ ] Error handling follows project conventions
- [ ] No unintended API surface changes (check .mbti diff)
- [ ] Tests cover the changes
- [ ] No scope creep beyond stated objective

## Output
Return: findings with severity (BLOCKER / WARNING / INFO), one sentence each`
})
```

### Test Writing

Use when Sonnet should write tests for existing code.

```
Agent({
  description: "[3-5 word summary]",
  model: "sonnet",
  prompt: `## Objective
Write tests for [module/function] in [package].

## Scope
- Test file: [package]/*_test.mbt (blackbox) or *_wbtest.mbt (whitebox)
- Code under test: [list files]
- Do NOT modify implementation code

## Context
[Paste the function signatures and type definitions being tested.
Include .mbti interface.]

## Test Strategy
- Happy path: [describe expected normal behavior]
- Edge cases: [list specific edges — empty input, boundary values, etc.]
- Use inspect for snapshot tests, @qc for property tests
- Panic tests: name starts with "panic " for expected aborts

## Constraints
- Run moon test after writing tests — all must pass
- Run moon test --update if snapshots need updating
- Each test must be in a ///| separated block

## Output
Return: test file contents, moon test output, coverage notes`
})
```

## Post-Dispatch Review

After every agent returns, before integrating:

1. **Read the output line by line** — green tests != clean code
2. **Check scope** — did the agent modify files outside its boundary?
3. **Diff .mbti** — did moon info reveal unintended API changes?
4. **Run verification** — `moon check && moon test` from the main context
5. **Flag unknowns** — did the agent report anything from the Unknowns section?
