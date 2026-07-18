# Generative UI opportunity discovery design

- **Date:** 2026-07-17
- **Status:** Proposed formative research; no participant recruitment or product experiment is authorized
- **Decision owner:** Canopy maintainers

## Purpose

Canopy needs to discover where Generative UI creates user value before it
selects a job, representation, provider, or production architecture.

The question is:

> For which people, intents, contexts, and lifecycles does a generated
> interface create useful capability, and what capability and authority bundle
> is necessary to create that value?

The existing structured-data experiment covers only one part of this research.
JSON/CSV exploration, an allowlisted component tree, provider integration, and
Dynamic generated code remain hypotheses whose value must be tested.

The output is an opportunity map and a ranked set of testable hypotheses. It is
not a production roadmap, renderer contract, provider selection, or permission
to send credentialed requests.

## Relationship to existing work

The [Generative UI direction](../architecture/generative-ui-direction.md)
defines the broad research purpose and Canopy's current incremental-editing
architecture hypothesis.

The [Human-centered product principles](../architecture/human-centered-product-principles.md)
define the non-negotiable authority, legibility, reversibility, cognitive
stability, accessibility, and contestability gates used below.

The [structured-data bounded-provider experiment](2026-07-15-generative-ui-live-provider-experiment-design.md)
is one deferred confirmatory protocol for one job family.

It combines a bounded Declarative surface with Projectional editing, but does
not establish that either capability creates value. Its `FIXED`, `RULES`, and
`GENERATE` labels apply only to that experiment.

The local-LLM feasibility study, provider comparison, and minimal provider E2E
work establish engineering facts about the existing candidate pipeline. They do
not establish user value or rank generation modes.

This design precedes any new product-value experiment. Discovery evidence may
revise or reject the structured-data hypothesis without invalidating its
engineering evidence.

## Research boundaries

### In scope

- Identify recurring moments where a person's needed interface cannot be fully
  anticipated by the host application.
- Compare job families with different sources of value, lifecycles, and
  authority needs.
- Compare representation modes by what they enable and what they cost.
- Observe existing workarounds, including manual coding, spreadsheets,
  dashboards, prompt-only assistants, fixed applications, and abandoned tasks.
- Build disposable, non-provider stimuli only when interviews cannot answer a
  concrete uncertainty.
- Rank hypotheses for later confirmatory experiments.

### Out of scope

- Selecting a provider or model.
- Adding credentials, network transport, retries, or production lifecycle code.
- Freezing a public candidate schema, renderer-neutral API, or execution runtime.
- Treating novelty, visual polish, or model output quality as proof of value.
- Generalizing from one job family to Generative UI as a whole.
- Claiming that a representation is safe merely because its prototype is
  sandboxed.

## Opportunity model

Each opportunity is recorded as a tuple:

```text
person × job × context × strongest alternative × value source × lifecycle
× required capability and authority bundle
```

A hypothesis is incomplete if any element is unspecified. "Generate a UI for
this prompt" is not a hypothesis because it names neither the person, job,
existing alternative, nor useful outcome.

### People and contexts

Discovery must sample concrete contexts rather than demographic abstractions:

- domain specialists working with unfamiliar or changing information;
- developers and analysts building one-off internal tools;
- operators responding to time-sensitive events;
- creators shaping interactive artifacts;
- people completing infrequent, high-friction workflows;
- collaborators maintaining a shared artifact over time;
- people with accessibility or device constraints unmet by a fixed interface.

The listed contexts are recruitment hypotheses. A reviewed study protocol must
establish that they include real Canopy users and define consent, privacy,
compensation, access, and retention before recruitment.

### Job families

The initial sampling frame deliberately spans jobs whose value could come from
different mechanisms:

1. **Information understanding** — explore, compare, explain, and monitor data.
2. **Planning and decision support** — assemble constraints, scenarios, and
   tradeoffs into a manipulable workspace.
3. **Workflow generation** — create task-specific forms, checklists, and action
   sequences around an existing process.
4. **Education and explanation** — adapt an interactive explanation or
   simulation to a learner's question and progress.
5. **Developer and domain tools** — construct small calculators, inspectors,
   transformations, or debugging surfaces.
6. **Creative authoring** — generate an interface or interactive artifact that
   the person can inspect, edit, and reuse.
7. **Personal applications** — support a narrow recurring need that was not
   anticipated by an installed application.
8. **Collaborative workspaces** — let people and AI evolve a persistent shared
   artifact with provenance and conflict awareness.

Discovery should seek disconfirming cases: tasks where a fixed interface,
conversation, or direct manual action is clearly better.

### Sources of value

A generated interface may help through one or more distinct mechanisms:

- selecting and organizing relevant information;
- composing known controls around a new intent;
- adapting presentation to content, device, or accessibility needs;
- creating behavior that the host did not anticipate;
- performing domain-specific computation;
- integrating external capabilities;
- making an output inspectable, editable, and reversible;
- preserving an artifact for reuse or collaboration.

The study must name the proposed mechanism. A visually different layout is not
itself a value source.

### Lifecycle

The same representation can have different value and risk depending on how long
it lives:

- **Ephemeral:** used once and discarded.
- **Session:** evolves during one task but is not retained.
- **Personal persistent:** saved, reopened, and adapted by one person.
- **Shared persistent:** edited, reviewed, and reused by multiple people.
- **Productized:** becomes maintained software with compatibility and support
  obligations.

Persistence increases the importance of identity, migration, provenance,
replay, ownership, and dependency control. Discovery records those needs; it
does not presume that every useful interface must be persistent.

## Representation spectrum

Representation modes are compared as affordance-and-cost bundles, not as a
maturity ladder.

| Mode | Generated authority | Native strength | Principal cost or limit |
|---|---|---|---|
| **Static** | Text, image, or fixed rendered output | Explanation, preview, low execution risk | Little or no interaction |
| **Declarative** | Allowlisted components, properties, and bindings | Inspectability, validation, host control | Cannot express behavior outside the catalog |
| **Open-Ended** | HTML/CSS or document structures beyond a fixed component catalog | Broad presentation and document composition | Harder validation, accessibility, and sanitization |
| **Dynamic** | Executable code or behavior | New stateful behavior, computation, and integration | Strong sandbox, interruption, dependency, and lifecycle requirements |
| **Projectional** | Semantic operations over an identity-bearing model | Editability, replay, provenance, and collaboration | Semantic-model and migration complexity |
| **Hybrid** | Deliberate combination of modes | Can separate durable intent from bounded or executable presentation | Cross-boundary ownership and failure semantics |

Persistence is a lifecycle property, not a representation mode. Static,
Declarative, Open-Ended, Dynamic, Projectional, and Hybrid artifacts may each be
ephemeral, session-scoped, personally persistent, shared, or productized.

The modes form a partial order of capabilities rather than a single strength
axis. Open-Ended presentation, Dynamic execution, and Projectional identity are
incomparable capabilities. Dynamic is neither the final stage nor the default,
and Declarative is neither inherently sufficient nor merely a stepping stone.

A prototype identifies the minimum sufficient capability and authority bundle
for the hypothesized value source, then records every eligible mode that can
provide it.

Multiple incomparable minima remain eligible. If Static or Declarative output
reproduces the useful moment without executable behavior, a Dynamic prototype
cannot claim that execution created the value.

## Discovery sequence

### Initial bounded tranche

The first tranche samples three deliberately contrasting job families:

1. **Information understanding**, because the existing structured-data work
   provides a known comparator while unfamiliar and changing information tests
   selection, explanation, and presentation adaptation.
2. **Workflow generation**, because infrequent and time-sensitive processes
   test whether composed controls and action sequences outperform fixed forms,
   checklists, or conversation.
3. **Collaborative workspaces**, because a shared artifact tests editability,
   identity, provenance, and persistence without presuming that Projectional
   representation is the answer.

Each family samples two context strata:

- Information understanding: domain specialists, and developers or analysts
  building one-off tools.
- Workflow generation: people completing infrequent high-friction processes,
  and operators responding to time-sensitive events.
- Collaborative workspaces: collaborators maintaining a shared artifact, and
  creators shaping an interactive artifact with others.

Each stratum receives at least three and at most six sessions.

After the third session, a stratum reaches saturation when two consecutive
sessions add no new job, value-source, or human-control research code. A
human-control code is a qualitative label for an action or decision that
participants require to remain under their authority.

Sampling stops at six even without saturation; the stratum is then recorded as
`UNCERTAIN`, not silently extended. The tranche therefore contains 18–36
sessions.

The other five job families remain `UNSAMPLED`.

A separately reviewed tranche may add job families when the first tranche
reaches its cap without saturation, or when it exposes a distinct value
mechanism or capability requirement that none of the three families can test
and for which a concrete recruitment stratum exists. Otherwise the study
proceeds to Stage 2 with the bounded map.

### Stage 1: Formative interviews and workflow observation

For each sampled job family, investigate:

- the triggering situation and desired outcome;
- why the current workflow is insufficient;
- which steps are repetitive, unpredictable, or impossible;
- what people create manually to bridge the gap;
- what must remain under human control;
- what needs to be saved, revised, shared, or audited;
- what failure would make the interface unsafe or untrustworthy;
- which existing alternative is strongest.

Evidence consists of redacted notes, workflow diagrams, observed artifacts,
and coded opportunity statements. Interview counts are not a success metric;
new evidence must stop changing the opportunity map before sampling ends.

### Stage 2: Representation-neutral concept tests

Test the job and value mechanism without implying a generation architecture.
Use storyboards, paper sketches, or hand-operated prototypes to compare:

- the existing workflow;
- the strongest realistic alternative;
- an interface that adapts to the participant's intent.

The facilitator may simulate adaptation, but must not imply that a model,
component schema, or executable runtime exists. Record whether participants can
identify a useful moment, complete the job, understand control boundaries, and
state what they would keep or discard.

### Stage 3: Flat-spectrum prototypes

Only hypotheses surviving Stage 2 receive prototypes.

Compare the smallest credible eligible modes side by side rather than
implementing them in a presumed order. A hypothesis may compare Static with
Declarative; another may compare Declarative with Dynamic; a persistent
collaboration hypothesis may compare a Projectional artifact with a persistent
Dynamic artifact.

Prototype source and behavior are fixed before each session. Provider calls are
not required: deterministic fixtures, hand-authored alternatives, and
facilitator-driven behavior isolate the representation question from model
reliability.

### Stage 4: Useful moments and terminal limits

For each job-mode pair, record:

- the useful moment that changes the person's outcome;
- the value mechanism responsible for that change;
- the minimum sufficient capability and authority bundle;
- every eligible mode that can provide that bundle;
- the missing capability that excludes each otherwise plausible mode;
- failure, latency, control, editability, and trust costs;
- retention or collaboration needs;
- the condition under which the hypothesis should be rejected.

This stage separates "a model can emit it" from "this representation creates
value."

### Stage 5: Rank hypotheses for confirmatory experiments

Rank surviving hypotheses using evidence, not architectural fit:

- frequency and severity of the unmet job;
- magnitude of improvement over the strongest alternative;
- whether the value survives outside a facilitated session;
- breadth of people and contexts benefiting;
- minimum sufficient capability and authority bundle;
- safety, privacy, latency, and maintenance burden;
- fit with Canopy's editable, incremental, and collaborative strengths;
- existence of a measurable primary outcome.

Architectural fit is one criterion, not a veto. A high-value Dynamic opportunity
may justify execution-boundary research. A low-value Projectional opportunity
should not be selected merely because Canopy can implement it elegantly.

## Evidence model

### Opportunity record

Every candidate opportunity records:

- concrete person and triggering context;
- job, desired outcome, and strongest realistic alternative;
- current workflow and observed friction or impossible action;
- proposed value source;
- expected lifecycle;
- minimum sufficient capability and authority bundle;
- every eligible representation mode, including incomparable minima;
- legibility, contestability, reversibility, pacing, and accessible-equivalence
  requirements;
- preview, confirmation, ownership, privacy, and safety boundaries;
- supporting and contradicting evidence;
- next uncertainty and cheapest falsification method.

### Cross-opportunity map

The final map is a matrix of:

```text
job family × value source × required capability bundle
× eligible representation × lifecycle
```

Each cell links to evidence and receives one disposition:

- `SUPPORTED`: repeated evidence justifies a confirmatory experiment;
- `UNCERTAIN`: evidence conflicts or the useful moment is not isolated;
- `REJECTED`: the strongest alternative is preferable or the value disappears;
- `UNSAMPLED`: no evidence was collected.

`UNSAMPLED` must remain visible. Absence of evidence is not rejection.

### Signals

Formative signals include:

- previously impossible or abandoned actions made possible;
- successful task completion;
- time to a useful result;
- desired corrections and adaptation requests;
- willingness to keep, reuse, or share the artifact;
- ability to understand and constrain effects;
- reduction in manual authoring or coordination cost;
- representation-specific terminal failures;
- latency, lifecycle, privacy, and maintenance concerns.

No single aggregate score selects a winner during discovery. The purpose is to
explain where value comes from and what authority it requires.

## Bias controls

- Recruit around a job and context, not interest in AI.
- Describe the capability without naming a provider or claiming intelligence.
- Randomize concept and mode presentation order where comparison is involved.
- Separate the facilitator from the person coding the evidence when practical.
- Record negative cases and participant confusion, not only requested features.
- Keep visual polish comparable across modes.
- Do not reveal implementation cost estimates until value judgments are
  recorded.
- Distinguish willingness to try from willingness to retain and rely on the
  result.
- Treat researcher-authored opportunity categories as revisable codes.

## Human-centered product gates, safety, and authority

Discovery prototypes must not execute participant-provided or model-generated
arbitrary code, use participant credentials, mutate external systems, or retain
sensitive source data. A concept requiring those capabilities can be evaluated
through bounded simulation until a separate execution and privacy protocol is
reviewed.

Human-control questions determine product value and belong in the initial
evaluation. Every hypothesis must state:

- what the generator may observe, propose, and execute;
- why a person can understand each generated result or change;
- how the person can inspect, correct, reject, contest, and reverse it;
- what requires preview or explicit confirmation, including every irreversible
  external effect;
- how update pace and spatial change preserve orientation and cognitive
  stability;
- how keyboard and screen-reader users can complete the same job with
  equivalent authority and information;
- who owns persistent artifacts and dependencies.

Early prototypes need not implement production accessibility or every recovery
path. Advancement does require a credible design path for every gate above;
visual success without that path is disqualifying evidence.

## Stop and continuation rules

Stop investigating a hypothesis when any of these holds:

- the strongest existing alternative already satisfies the job;
- participants value the information but not an interface;
- the useful moment depends on facilitator knowledge unavailable to a system;
- the proposed value disappears under the minimum safety boundary;
- the job is too rare or low-impact to justify the lifecycle burden;
- no measurable outcome can distinguish the hypothesis from novelty.

Advance a hypothesis to a confirmatory design only when:

1. a concrete person, job, context, and strongest alternative are named;
2. repeated evidence identifies one useful moment and value mechanism;
3. the minimum sufficient capability and authority bundle is explicit;
4. every eligible mode is listed, including incomparable minima, and exclusions
   name the missing capability;
5. terminal limitations and lifecycle needs are explicit;
6. the human-centered product gates have a credible design path;
7. safety, privacy, ownership, and confirmation boundaries are plausible;
8. a primary outcome and keep/delete decision can be preregistered;
9. contradictory evidence and unsampled contexts remain visible.

A confirmatory experiment freezes only its selected job, representation,
comparator, and evidence contract. Its result must not be generalized to
unsampled jobs or generation modes.

## Deliverables

Discovery concludes with:

1. a redacted evidence corpus and coding guide;
2. the cross-opportunity map with supported, uncertain, rejected, and unsampled
   cells;
3. a ranked hypothesis list with explicit value sources and authority needs;
4. a representation comparison showing useful moments and terminal limits;
5. one or more confirmatory experiment design proposals, or a recommendation
   not to continue;
6. updates to the canonical Generative UI direction where evidence changes its
   hypotheses.

No production code or provider integration is a required deliverable.

## Decision boundary

The maintainers decide which hypotheses, if any, deserve confirmatory work.
Discovery success means reducing uncertainty and rejecting weak opportunities,
not producing a provider-backed demo.

A later experiment may select a bounded Declarative path, an open-ended
document, Dynamic generated software, a Projectional artifact under an
evidence-backed lifecycle, a Hybrid, or no generated interface. The evidence
decides; this design does not.
