# Canopy Documentation

Canopy is an incremental projectional editor with CRDT collaboration, built in
MoonBit. Choose an entry for your purpose; this index is not a required course.

## Understand or Use Canopy

- [Project overview and quick start](../README.md) — what Canopy does and how
  to try it; also available as a [Japanese introduction](japanese-introduction.md).
- [Architecture overview](architecture.md) — the pipeline and responsibilities.
- [API and integration guides](development/README.md#api--integration-also-useful-for-users-of-the-library)
  — use Canopy from MoonBit or JavaScript, or integrate a language.

## Before Making Changes

Identify the expected result, owning component, relevant constraints, and
validation for the task:

1. Read the affected component's README and existing `CONTEXT.md`, where
   present, plus relevant accepted decisions linked from them. For example,
   [Loomark](../apps/loomark/README.md) links its product vocabulary and decisions.
   If the owner is unclear, start with the
   [Module / Package Map](development/module-package-map.md).
2. Select all applicable rows below. Read a constraint before making the
   decision it governs, and read an operational gate before performing that
   action. Rows are conditional and may overlap.
3. Choose the checks in [Validation Scope](development/workflow.md#validation-scope).
   Start work when the expected result, owner, constraints, and validation are
   clear. Read more when a concrete question remains; do not recursively load
   every linked document.

| When the task involves… | Read for that work |
|---|---|
| MoonBit implementation or API changes | [API reuse](development/api-reuse.md) and [coding conventions](development/conventions.md) |
| State transitions, persistence, or integration | [Functional Core / Imperative Shell](architecture/functional-core-imperative-shell.md) and the owner's relevant decisions |
| Product behaviour or UX | [Human-centered product principles](architecture/human-centered-product-principles.md); [product direction](architecture/personal-knowledge-environment-direction.md) when choosing product scope |
| UI or performance | [UI workflow](development/workflow.md#ui-work) or [performance workflow](development/workflow.md#performance-work) |
| A new language | [Adding a language](development/ADDING_A_LANGUAGE.md), using Markdown as the reference |
| Submodule or Rabbita changes | [Submodule workflow](development/monorepo.md#editing-a-submodule); [Rabbita guidance](development/rabbita-fork.md#development-guidance) when applicable |
| Documentation or task planning | [Documentation Doctrine](development/documentation-doctrine.md); [Task Tracking](development/task-tracking.md) for issues and plans |
| Commit, push, review, or PR | [Development Workflow](development/workflow.md#git-commit-process), including its review scope, implementation PR order, and merge gate |
| Pi or the provisioned Cursor Cloud VM | [Agent Environments](development/agent-environments.md), only for that host |

## Interpret Documents

Accepted requirements and decisions describe intended behaviour. Code and
manifests describe the current implementation; tests check specific properties.
An implementation mismatch does not automatically invalidate a requirement.
Read a decision's status and the scope of any supersession, not just its date.
Resolve conflicting applicable requirements before relying on them; follow
[the document-role rules](development/documentation-doctrine.md#document-roles-and-conflicts).

## Find a Document

- [Development index](development/README.md) — commands, testing, integration,
  ownership, and contribution guides.
- [Architecture index](architecture/README.md) — principles, explanations, and
  separately labelled design explorations.
- [Decision index](decisions/README.md) — architectural decisions; inspect their
  accepted or superseded scope before applying them.
- [GitHub Issues](https://github.com/dowdiness/canopy/issues) — active backlog
  and work status. [Plans](plans/) contain unfinished implementation specifications;
  delete or archive each plan when implementation completes.
- [Research](research/) — investigations and evidence, not automatic requirements.
- [Performance reports](performance/) — measurements tied to dates and conditions.
- [Archive](archive/) — historical material; read or search only when historical
  context is requested.

`AGENTS.md` contains the general agent principles and points here. `CLAUDE.md`
is its compatibility symlink and should not be edited directly.
