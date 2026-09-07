# Documentation navigation: primary-source study

- Date: 2026-09-06
- Scope: deciding how `docs/README.md` should help human contributors and
  coding agents find current project guidance. This is a navigation study, not
  a measurement of Canopy's documentation or of agent performance.

## Question

Should Canopy make a fixed priority list the primary navigation model, use a
short task router, or keep a comprehensive topic index?

The alternatives are not mutually exclusive. The question is which job the
landing page should perform first, and what it must preserve.

## Primary-source findings

### 1. A landing page should begin with the reader's goal, not its internal taxonomy

Google's technical-writing guidance says that navigation and signposting help
readers find both what they seek and what they need to get unstuck. It advises
task-based headings in familiar language rather than headings based on tools or
unfamiliar terms. [Google, *Organizing large documents*](https://developers.google.com/tech-writing/two/large-docs)
also recommends introducing information when it becomes relevant to the task.

**Inference for Canopy:** entries such as “Change MoonBit code”, “Change UI or
product behaviour”, and “Commit or open a PR” are better first choices than a
sequence named after documentation areas. The entry must say what action it
supports and link to only the prerequisites for that action.

### 2. Progressive disclosure is a constraint on the entry point, not evidence for a universal reading order

Google recommends progressive disclosure: introduce new concepts near the
instructions that need them, and begin with simpler material. The same source
also notes that readers differ: some prefer search while others navigate a long
document. [Google, *Organizing large documents*](https://developers.google.com/tech-writing/two/large-docs)

Diátaxis likewise says readers should not read everything before beginning; it
distinguishes tutorials, how-to guides, reference, and explanation because they
serve different needs. Its reference material is for accurate facts used during
work, while explanation provides background and perspective. [Diátaxis, *Start
here*](https://diataxis.fr/start-here/)

**Inference for Canopy:** a page-wide “Priority 1 for every change” is only
defensible for a genuinely universal, short safety or ownership rule. It should
not force project background, API material, or product direction on every edit.
Keep an explicit reference/index path beside the task router, because it serves
competent users who arrive with a concrete question.

### 3. Mature documentation sites combine goal-based routes with stable content types

Kubernetes' official landing page offers separate routes to understand concepts,
try tutorials, set up a cluster, perform common tasks, look up reference, and
contribute. Its task section says that a task page covers one thing through a
short sequence of steps. [Kubernetes Documentation](https://kubernetes.io/docs/home/)
and [Kubernetes Tasks](https://kubernetes.io/docs/tasks/)

GitHub's documentation model makes the same distinction. Its how-to content
focuses on the minimum steps to finish a task and links to concepts or reference
only when those links are necessary. Its get-started section is limited to the
minimum essential entry information, ideally two articles. [GitHub Docs,
*How-to content type*](https://docs.github.com/en/contributing/style-guide-and-content-model/how-to-content-type)
and [*Get started content type*](https://docs.github.com/en/contributing/style-guide-and-content-model/get-started-content-type)

**Inference for Canopy:** a useful `docs/README.md` can offer parallel paths:
an orientation path, a change path grouped by task, a reference path, and a
historical path. It need not make the reader traverse one path before another.
This is a better model than treating all documentation as a curriculum or all
documentation as an alphabetic directory.

### 4. Navigation must expose status and authority where a reader chooses material

Kubernetes labels its documentation in terms of supported versions and clearly
separates reference from tasks and concepts. [Kubernetes Documentation](https://kubernetes.io/docs/home/)
GitHub describes a repository README as the place to communicate important
project information and links to contribution guidance as a distinct artifact.
[GitHub Docs, *About README files*](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-readmes)

Canopy already has the more specific policy: current implementation details are
authoritative in code; architecture documents carry principles; plans are
ephemeral and archived when complete; performance reports are dated snapshots.
([Documentation Doctrine](../development/documentation-doctrine.md))

**Inference for Canopy:** the landing page should not use reading priority as a
proxy for authority. It should put a compact, visible status legend next to its
routes: current project guidance, current implementation reference, active
proposal, dated measurement, and archive. The existing doctrine remains the
source of the detailed rule. A route to plans or research must state that it is
not automatically current behaviour.

### 5. There is no direct evidence that a particular README layout improves coding-agent correctness

Gloaguen et al.'s June 2026 revision evaluates repository context files on
Python issue-resolution tasks. It finds no general success-rate improvement,
with average inference cost increasing by more than 20%. Its length ablation
also does not establish that shorter files improve results. The authors note
that niche languages and nonfunctional outcomes need further investigation.
[Evaluating AGENTS.md, revision 2](https://arxiv.org/html/2602.11988v2)

**Inference and limit:** neither adding instructions nor shortening them is a
validated performance intervention for Canopy. This experiment does not test
our README layouts, MoonBit, or whether the product meets the user's intent.
Retain necessary repository-specific constraints and evaluate task outcomes.

Anthropic describes a hybrid approach: provide some context up front and load
other context when needed. It also warns that unguided exploration can be slow
or miss relevant information. This is engineering guidance, not an experiment
on README layouts. [Effective context engineering](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents)

## Alternatives and trade-offs

| Model | What it optimizes | Failure mode | Assessment |
|---|---|---|---|
| Fixed P1/P2/P3 sequence | A simple instruction for a newcomer | Treats unlike edits alike; turns conditional guidance into mandatory context; hides the fact that authority is independent of reading order | Do not use as the primary model. Retain only a very short universal preflight if one exists. |
| Comprehensive directory index | Coverage and direct lookup | A contributor must infer which items constrain the current task; the entry becomes a large catalogue | Keep as a secondary “browse by subject” path. |
| Short task router only | Fast action and progressive disclosure | Overfits named tasks, omits research/reference users, and can become another stale duplicated rule set | Insufficient on its own. |
| Task router plus orientation, reference, and status labels | Goal-based start while preserving lookup and authority distinctions | Requires disciplined link ownership and occasional route maintenance | Recommended. It combines the strengths observed in Google, Diátaxis, Kubernetes, and GitHub's content model. |

## Recommended landing-page contract

This is a recommendation, not a finding from the sources.

1. Start with one sentence saying what the documentation covers and who the
   index serves.
2. Give a universal preflight: identify the owning component, the expected
   behaviour, the applicable constraints, and the relevant validation. A short
   shared policy may be linked, but keep task-specific material conditional. Do not label a long document set
   “read first for every change.”
3. Offer a compact **Choose your task** table. Each row uses a reader goal,
   names the decision it protects, and links to the owning document. Likely rows
   are MoonBit/package work; UI/product work; stateful/integration work;
   documentation/plans; submodules; and commit/push/PR.
4. Give separate, equally visible routes for **Understand Canopy**, **Use the
   API / reference**, **Browse by subject**, and **Historical records**. These
   are routes, not prerequisite stages.
5. Put a short **How to read claims** note near the routes, linking to
   Documentation Doctrine. State the status categories in that note and mark
   historical, proposal, and dated-measurement destinations at their links.
6. Avoid duplicating commands, rules, or detailed architecture in the index.
   The README owns routing; linked pages own their facts and procedures.

## Strongest counterargument and response

**Counterargument:** an agent or new contributor can miss a critical invariant
if it chooses the wrong task row; a fixed universal list is safer.

This is real. The response should be a short universal preflight and
task-language that names cross-cutting triggers, rather than making every
reader consume every guide. If a constraint is truly universal, give it one clear canonical home and
expose it in the short preflight. If it is conditional, expose the
condition in the task row and keep the detailed rule at its owner. This retains
discoverability while avoiding a false universal hierarchy.

## Source and evidence limits

- Google, Diátaxis, GitHub, and Kubernetes are first-party guidance or the
  maintainers' own documentation. They establish design rationales and examples,
  not experimental proof for Canopy.
- The context-file paper studies Python issue resolution, not README
  navigation, MoonBit, or product-goal compliance. Its results cannot establish
  the best Canopy layout without a local comparison.
- No source tested a mixed human-and-coding-agent documentation landing page.
  The recommendation therefore combines applicable principles with explicit
  uncertainty rather than asserting an empirically optimal layout.


## Canopy audit and selected design

Parent synthesis, 2026-09-06. This section records observations from the current
working tree, including earlier uncommitted documentation cleanup. It is a
recommendation, not an adopted repository policy or an implementation plan.
No existing README or product file was changed during this investigation.

### Observed problems

The current [documentation index](../README.md) has 344 lines and 131 inline
Markdown links, counted with a simple line count and Markdown-link regex.
Those are navigation inventory measures, not tokens, reading time, or a quality
score. Six destinations recur, including Documentation Doctrine three times.
The then-existing `project-guidance.md` added 77 lines and 15
links (its rules have since moved to their owning development guides); [Workflow](../development/workflow.md) contains 273 lines. Reading a
heading target does not technically guarantee that a file-reading agent loads
only that section.

The important defects are semantic:

- Accepted ADRs are listed under **Deep Design (Grand Design)**, whose opening
  describes long-range exploration. For example, [document deletion](../decisions/2026-08-31-loomark-document-deletion.md)
  is explicitly Accepted and partially supersedes an earlier decision. It is
  not equivalent to an exploratory idea. Placement can obscure that difference.
- The entry table names technical activities but has no explicit route to the
  owning application's current product vocabulary. [Loomark CONTEXT](../../apps/loomark/CONTEXT.md)
  describes accepted behaviour and terminology; it has no direct route from
  the root documentation index or the current [Loomark README](../../apps/loomark/README.md).
  The README does link accepted decisions. Existing content is sufficient to
  improve navigation without duplicating its contracts in `docs/`.
- The architecture and development directories already have indexes, but root
  navigation repeats individual entries. Decisions, research, performance,
  and plans do not currently have their own direct README indexes. Moving all
  entries to new mandatory indexes would introduce upkeep, not merely remove it.
- The doctrine's final blanket statement that disagreeing code wins is broader
  than its preceding rule about *implementation details*. Tests and code show
  actual behaviour, not proof that accepted product requirements are met.
- Project Guidance is partly another router. Simply making it mandatory
  preserves a large part of the old AGENTS reading workload under a new name.

### Additional alternatives considered

These assessments are design judgments from the inspected routes, not measured
rankings.

| Alternative | Useful property | Why it is not the selected default |
|---|---|---|
| Force all docs into four Diataxis directories | Distinguishes learning, doing, reference, explanation | Large migration with no evidence that physical reclassification solves today's route failures; Diataxis itself advises improving incrementally rather than imposing structure first. |
| Agent-only README plus human-only README | Each audience gets tailored language | Both need the same product and development contracts; creates two maps that can drift. Keep separate only for host mechanics that actually differ. |
| Nested AGENTS files for each area | May expose local rules during area-specific work | Host-dependent loading and instructions become harder to audit; no current evidence requiring another instruction hierarchy. Ordinary owner READMEs and explicit links address the observed gap first. |
| Search-only entry | Lowest central maintenance | Readers cannot reliably search for an invariant whose name they do not know; unclear accepted/superseded status remains. |
| Per-document priority metadata and generated routing | Can enforce consistent inventories | Requires a schema, classifications, a generator, and maintenance. Current failures can be addressed with ordinary Markdown. Reconsider if repeated measured drift warrants it. |
| Short task entry with bounded preflight, owner context, and browse fallback | Directs work while preserving unknown-topic discovery | Selected, with the limitation that its outcome advantage still needs local evaluation. |

[Diataxis's incremental guidance](https://diataxis.fr/how-to-use-diataxis/)
supports using its distinctions without a directory migration.
[Google's link guidance](https://developers.google.com/style/cross-references)
supports descriptive destinations and avoiding unnecessary repeated links;
useful cross-links are not forbidden duplication. Facts and policy statements
need a single owner; navigation links may appear in more than one useful place.

### Selected entry contract

Keep the user-specified `AGENTS.md` text unchanged. Make `docs/README.md` a
small shared entry with four parts:

1. **Understand or use Canopy:** routes to the project overview and API/integration
   guidance. Learning is an optional route, not a prerequisite for every change.
2. **Make a change:** identify the affected component and the requested outcome.
   Read its existing README and, where present, its CONTEXT and relevant
   accepted decisions. Then select all applicable constraint/validation routes.
   A change may match more than one row.
3. **Interpret documents:** identify each source's role and status. Accepted
   requirements describe intended behaviour, code and manifests describe
   implementation, checks demonstrate specified properties, and issues own work
   status. Read supersession scope; a newer date alone does not confer authority.
   If relevant accepted requirements conflict, resolve the conflict rather than
   automatically treating current code or the newest file as the winner.
4. **Browse or investigate:** reuse the architecture/development indexes; link
   the decisions, research, performance, and history collections with clear
   descriptions of what they contain. Do not turn individual active issues or
   recently completed work into a second root backlog.

A short contributor preflight belongs directly at the entry: find the owner,
expected result, applicable constraints, and validation. Detailed rules remain
at their owners. Narrow Project Guidance to shared non-obvious policy that is
not already canonical elsewhere; merge away its duplicated routing as part of
implementation. Do not remove necessary constraints merely to reach a line limit.

Within a task, order is determined by dependency: read a requirement before
making its design decision and read a gate before performing its action. There
is no useful global numeric rank between, for example, product strategy and a
submodule publication rule.

### Static task walkthroughs

These are manual routing checks against existing files. No agents were run on
implementation tasks, and no speed or success-rate improvement was measured.

| Task | Necessary route in the selected design | Failure to guard against |
|---|---|---|
| Fix a documentation link | Documentation Doctrine + relevant documentation contract in Workflow | Loading MoonBit API or product strategy as compulsory background |
| Change Loomark Recent documents presentation | Owner README + CONTEXT; applicable product principles and design context; browser validation | Implementing a new visible label or interaction inconsistent with accepted vocabulary |
| Fix Markdown span behaviour | Package ownership + API reuse + relevant parser contracts; Workflow's conditional Markdown matrix and targeted tests | Applying the seven-zone overview without reading the actual owning dependency |
| Change save/delete concurrency | Loomark README + accepted deletion/ownership decisions + deterministic-core guidance; affected tests and independent review | Treating a superseded Source/Catalog decision as current or trusting current code as the requirement |
| Update a submodule dependency | Monorepo guide + owning repository rules + local validation/push workflow | Missing the requirement to publish the submodule commit before the parent pointer |
| Learn the architecture without editing | Overview + architecture index | Forcing commit/PR gates on a reader who is not changing anything |
| Explain why an older design existed | Relevant accepted/superseded decision; archive only when historical context is requested | Treating the newest filename or an archive record as an active task |

The owner-context step is the material improvement over the previous generic
four-way “understand/change/API/browse” proposal. Its task routes alone did not
expose component-specific product constraints.

### Concrete implementation scope

- Rewrite `docs/README.md` around the entry contract; preserve useful reference
  discovery while removing fixed Priority 1/2/3 and the duplicate activity feed.
- Reuse `docs/architecture/README.md` and `docs/development/README.md`; move
  root-only useful descriptions to the applicable existing index. For areas
  without indexes, use a directory route initially; create a curated index only
  where it is needed to expose current decisions or distinguish statuses.
- Give Accepted decisions a clearly distinct route from exploratory design.
  Preserve old decisions with their supersession information.
- Make shared Project Guidance a single-home policy page rather than another
  copy of the task table. Keep relevant hooks and CI as executable validation
  authorities; do not reproduce their full command matrices in the root index.
- Qualify Documentation Doctrine's “code wins” wording to current implementation
  facts; distinguish accepted expected behaviour and actual behaviour.
- Add the missing Loomark README-to-CONTEXT link without editing the user's
  existing CONTEXT content. More generally, link already-existing owner context;
  do not generate new CONTEXT files for every package.
- Update affected links to removed headings and verify their target sections.
  Do not add a priority schema, navigation generator, or new agent hierarchy.

### Acceptance and remaining uncertainty

For the navigation change, manually exercise the routes above using only the
new entry and linked sources. Each must reach the applicable current contract,
ownership information, and validation without relying on prior session memory.
Check that no necessary rule was dropped and no new unconditional reading was
introduced. Keep all remaining local targets and anchors valid and run the
existing documentation contract.

Link checks cannot prove a route is semantically correct. For a claim that the
change improves agent results, compare the current and proposed entries on the
same representative tasks with fresh contexts, the same repository snapshot,
model, tools, and settings. Repeat runs to account for variability. Record
constraint omissions, incorrect current/superseded choices, patch correctness,
unnecessary edits, read volume, tool calls, and time. Preserve product-contract
checks: passing old tests alone can reward the wrong behaviour.

No such paired implementation evaluation was performed here. The selected
proposal is justified by concrete navigation defects and low maintenance cost,
not by a claim of proven optimality. Avoid continued broad restructuring once
these failures are resolved unless subsequent tasks reveal another problem.
