# Agent history as thinking environment

**Status:** In progress. Independent chat prototype implemented; awaiting direct use with a genuinely unfinished non-Canopy work session.

## Why

People already leave substantial traces of thought and work in the tools they use every day. Agent histories contain intent, alternatives, corrections, actions, tool evidence, failures, and outcomes without requiring a second note-taking habit.

The broader PKE goal is not merely resumption. Past activity should become material for present reflection, work improvement, and thinking. The earlier Resume experiment and subsequent semantic briefing study proved bounded import, branch selection, conversation rendering, tool correlation, source inspection, and deterministic projection. Both also exposed product mistakes:

- Static resumption summaries do not create a useful personal knowledge environment
- Source-bounded chat—the workbench as primary interaction form—failed in direct use
- Direct long-context semantic study failed because cardinality and content complexity defeated byte-only chunking; no Cloudflare or study runtime remains in this PR

## Current independent chat defaults

Ordinary chat defaults to **no history**. Selected history and the current recorded path attach only as explicit per-turn choices with:

- exact outbound preview before sending;
- bounded normalized text-only projection that strips AI SDK control, provider, file, and tool parts;
- per-turn context snapshots (no cross-turn memory beyond the conversation);
- citations linking model responses to explicitly attached sources;
- same-origin loopback to DeepSeek `deepseek-v4-flash` (fixed model, fixed origin);
- memory-only lifecycle (Forget or reload clears everything).

Import and read authority are separate from model-egress authority. The system may read and normalize history for inspection, but it may send to the model only what the person explicitly attaches per turn. Retained source warnings do not censor explicit chat; they inform the person before sending.

`automaticOutputAllowed` metadata remains in the codebase, but this PR includes **no automatic model workflow**. No persistence, retrieval, suggested prompts, automatic scanning, capture, or multi-session memory is authorized.

## Current state

The current prototype can:

- import one explicitly selected pi v3 JSONL file into current-tab memory;
- require an explicit terminal path and preserve branch boundaries;
- render the complete selected conversation with paired tool calls and results;
- synchronize Timeline, Conversation, and Evidence selection;
- open exact bounded source text and normalized metadata;
- distinguish human messages, assistant claims, tool observations, accepted checkpoints, and named deterministic UI derivations visually;
- project selected-path activity into immutable items with separate origin, derivation, review state, and source references;
- validate source presence and epistemic combinations in a pure core boundary;
- clear imported state through Forget or page reload;
- open an independent chat that defaults to no history;
- attach selected history and the current recorded path as explicit per-turn choices with exact outbound preview;
- send attached context to DeepSeek `deepseek-v4-flash` through a same-origin local relay;
- show citations linking model responses to explicitly attached sources.

It cannot yet:

- establish through direct use that the chat interaction supports present thinking;
- let the person correct or connect system-proposed structure without rewriting its sources;
- make reviewed history participate visibly in current thought or work.

## Authority, provenance, and review model

Epistemic metadata is domain data, not copy or color added by the renderer. Origin, derivation, and review are separate fields:

```typescript
type EpistemicOrigin =
  | { readonly kind: 'recorded-human' }
  | { readonly kind: 'human-accepted-source' }
  | {
      readonly kind: 'observed-tool';
      readonly outcome: 'success' | 'failure';
      readonly toolCallId?: string;
    }
  | { readonly kind: 'assistant-claim' }
  | { readonly kind: 'person-authored' }
  | { readonly kind: 'canopy-system' };

type Derivation =
  | { readonly kind: 'recorded' }
  | {
      readonly kind: 'deterministic';
      readonly ruleId: string;
      readonly ruleVersion: string;
    }
  | {
      readonly kind: 'model-inference';
      readonly modelIdentity: string;
      readonly analysisVersion: string;
    };

type ReviewState =
  | { readonly kind: 'unreviewed' }
  | { readonly kind: 'accepted' }
  | { readonly kind: 'corrected'; readonly replacement: PersonAuthoredRevision }
  | { readonly kind: 'dismissed' };
```

Invariants:

- every item has an origin, a derivation, and at least one source;
- `recorded` denotes content preserved directly from source history or authored directly in Canopy;
- deterministic and model-derived items retain `canopy-system` origin and name the rule or model;
- tool observation establishes only what the named tool emitted and whether the recorded action succeeded or failed;
- review state is independent from origin and derivation;
- acceptance never disguises model inference or assistant content as recorded human content;
- correction retains the original text, origin, derivation, and sources;
- corrected replacement text carries `person-authored` origin;
- dismissal changes presentation, not history;
- source records are immutable from the thinking surface.

`model-inference` is part of the long-term derivation model but cannot be constructed in this slice without a separate automatic-workflow authorization.

## Implementation structure

Follow feature-oriented dependency direction. Shared code must not import from a feature, and one feature must not reach into another feature's internals.

TypeScript split:

- `app` owns route/entry composition only;
- `features/session-history` owns import, recorded-sequence, Timeline, Conversation, Evidence, and selection state;
- `features/independent-chat` owns the chat surface, per-turn attachment, outbound preview, and citations;
- only genuinely reusable, feature-agnostic code moves into shared `components`, `hooks`, `lib`, or `types` directories;
- use direct imports rather than broad barrel files;
- keep pure reducers and projections in the owning feature and side effects in its UI shell.

## Steps

### Step 1 — Establish the epistemic boundary [done]

Define the smallest pure TypeScript boundary that can wrap existing selected-path messages, checkpoints, tool outcomes, and deterministic derivations with `EpistemicOrigin`, `Derivation`, `ReviewState`, and source references.

Tests show that:

- source origin comes from host-normalized records, never display text;
- source-recorded acceptance remains distinct from later Canopy review;
- tool success and failure remain narrow observations;
- assistant text remains a claim even when later evidence corroborates it;
- person-authored corrections use `person-authored` origin with `recorded` derivation;
- review transitions cannot mutate origin, derivation, or source references;
- invalid or source-less thinking items cannot be constructed.

### Step 2 — Independent chat with explicit per-turn attachment [done]

Prototype the chat surface that defaults to no history and permits explicit Selected/Current path per-turn attachment.

Implementation:

- chat opens with no attached context;
- the person may attach selected history or the current recorded path before sending a turn;
- each attachment shows an exact outbound preview of what will be sent;
- bounded normalized text-only projection that strips AI SDK control, provider, file, and tool parts;
- per-turn context snapshots (no cross-turn memory beyond the conversation);
- citations link model responses to explicitly attached sources;
- same-origin loopback to DeepSeek `deepseek-v4-flash`;
- memory-only lifecycle.

Direct use with the Canopy-development session showed that the chat interaction works mechanically. The open question is whether it supports present thinking when used with a genuinely unfinished non-Canopy work session.

### Step 3 — Use it during real thinking

Use the slice with an explicitly selected real agent history from a genuinely unfinished non-Canopy work session. The activity is not a questionnaire and does not require blind conditions or a fixed answer sheet. The person should use the environment while reflecting on or continuing real work.

Observe concrete friction in the interaction:

- whether the person naturally attaches history when it helps;
- whether citations make the basis of model responses clear;
- whether the person can move between no-history conversation and explicitly attached context without confusion;
- whether the interaction changes or advances current thought or work;
- where they lose position or source context.

Iterate only on friction observed in this use. Do not infer product value from schema validity, test coverage, or this Canopy-development session.

**The next clean test must use a genuinely unfinished non-Canopy work session.** Evaluate no-history and current-path chat without inferring value from tests, schema, or this Canopy-development session. Value must be observed in changed present thinking or work, not in schema correctness or test passage.

### Step 4 — Decide the next gate

After direct use, record one of these decisions:

- continue the independent chat with explicit per-turn attachment;
- change the attachment mechanism or chat interaction;
- plan explicitly selected multi-session input for patterns that require time;
- plan a separately authorized automatic workflow (distinct from the current explicit-per-turn model), subject to the retained semantic-generation constraint in the direction document (separate plan, explicit authorization, reliability evidence from representative history);
- narrow or stop the agent-history hypothesis.

Do not authorize the next gate inside this plan.

## Acceptance criteria

- [ ] Origin, derivation, review state, and provenance are first-class domain data for every source-bearing or interpretive item.
- [ ] Recorded human content, source-recorded commitments, tool observations, assistant claims, and deterministic derivations cannot be confused by construction or presentation.
- [ ] Tool observations establish recorded output, not the truth or determinism of that output.
- [ ] The person can attach selected history or the current path as an explicit per-turn choice with exact outbound preview.
- [ ] Citations link model responses to explicitly attached sources.
- [ ] All imported and chat state remains in current-tab memory. Forget and reload clear it.
- [ ] No provider request, automatic scan, capture path, browser persistence, or repository write contains selected session content beyond what is explicitly sent per turn.
- [ ] Keyboard and screen-reader paths preserve equivalent movement and review actions.
- [ ] Direct use of real selected history from a non-Canopy work session produces a concrete observation about how the environment helped or obstructed thinking.

## Validation

```bash
cd examples/web
npx tsc --noEmit
npm run build
node --test src/*.test.mjs scripts/*.test.mjs
npx playwright test tests/pi-resume.spec.ts
cd ../..
git diff --check
```

The retained Playwright suite covers import, workbench synchronization, per-turn attachment, citations, relay boundaries, lifecycle clearing, and responsive behavior. Run workspace-root MoonBit validation only if a later slice changes MoonBit packages.

Visual and direct-use inspection is mandatory. Automated tests cannot establish that the environment supports thinking.

## Stop or rethink conditions

Stop and reconsider the slice when any of these occurs:

- the person spends their time managing attachments rather than thinking with their history;
- citations are not understood or not used;
- the chat interaction does not change or advance current thought or work;
- the only visible consequence is a status label or attachment count;
- product value is argued from technical safety instead of direct use;
- a broader data or model boundary is introduced before its own authorization.

Each stop condition requires a short written decision: change the attachment mechanism, choose a different source, or propose a separately gated capability.

## Risks

- **Attachment overhead:** per-turn attachment decisions can become tedious rather than helpful.
- **Citation invisibility:** citations may be present but not understood or used.
- **Single-session ceiling:** daily improvement and recurring patterns may require explicitly selected multi-session history; this slice cannot prove them.
- **Prototype constraints becoming product doctrine:** memory-only, single-session operation protects this slice but cannot support the complete long-term PKE.

## References

- [Personal knowledge environment direction](../architecture/personal-knowledge-environment-direction.md)
- [Human-centered product principles](../architecture/human-centered-product-principles.md)
- [Product vision](../architecture/product-vision.md)
- [Pi session activity → Resume view prototype](2026-07-16-pi-activity-capture-resume-prototype.md)

## Notes

- The WorkBench is the Trace-scale source inspector, not the PKE home.
- Resume remains one possible projection over selected history, not the product definition.
- The failed semantic briefing study is summarized here and in the direction document; its plan and runtime are not part of this PR.
