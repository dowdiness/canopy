# Place validation at lifecycle gates

## Decision

Place repository validation at commit, push, and CI gates, not after individual
edits. GitHub CI validates the exact pull-request commit and remains the only
full-workspace build, test, and end-to-end gate.

| Gate | Responsibility |
| --- | --- |
| After an individual edit | No repository validation. |
| Before commit | Lefthook runs targeted `moon fmt` and `moon info`; stop for review if they change files. |
| Before push | Run only checks selected for the pushed file classes. |
| GitHub CI | Full-workspace build, test, and end-to-end gate. |

## Background

The decision separates local, targeted validation from the full-workspace CI
gate. The original record does not document the motivating incident or measured
cost of per-edit validation: **unconfirmed**.

## Rejected approaches and non-goals

- Repository validation after every individual edit.
- Making a local gate the full-workspace build, test, and end-to-end gate.

These exclusions follow from the decision; a separate comparison of alternatives
is **unconfirmed**.

## Impact

This decision governs the repository validation workflow. Formatting or interface
generation changes require review before committing; local checks do not replace
CI. It does not decide product behaviour, public APIs, or compatibility policy.

## Implementation references

[Lefthook](../../lefthook.yml), the [local validation adapter](../../scripts/local-validation.nu),
and the [CI workflow](../../.github/workflows/ci.yml) define the current gates.
Operational steps belong in [Development Workflow](../development/workflow.md#validation-scope).
The local orchestrator is covered by [ADR 0002](0002-use-lefthook-as-the-local-validation-orchestrator.md).

## Unresolved questions and follow-up

- **Unconfirmed — exact PR commit:** CI uses `actions/checkout@v7` without an explicit
  PR head SHA. The configuration alone does not establish that the checked-out
  commit is the PR head rather than a merge ref; no CI run was inspected for this
  rewrite. The decision above is unchanged.
- **Proposal — verification only:** inspect the checkout SHA in a CI run before
  claiming implementation compliance. No workflow change is proposed here.
- Other outstanding work is not recorded in the original ADR: **unconfirmed**.
