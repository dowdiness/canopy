# lib/semantic — Confidence Lattice and Semantic Annotation

## What this library does

`Confidence[T]` is a join-semilattice for merging annotations from multiple sources. `annotate_symbolic` is the first source — positional rules on the Markdown AST.

## What `Confidence[T]` gives you for free

Any new annotation type gets merge-correctness by construction:

```moonbit
// Today: structural role
FixedArray[Confidence[Role]]

// Tomorrow, same algebra, no new merge logic:
FixedArray[Confidence[Topic]]        // "What is this section about?"
FixedArray[Confidence[Intent]]       // "Is this an instruction, warning, definition?"
FixedArray[Confidence[Audience]]     // "Is this for beginners or experts?"
```

Each one can be filled by symbolic rules, LLM, user override, or all three — `join` merges them. You don't write merge logic per annotation type. The lattice does it.

## Dual-source pattern

The symbolic annotator is deliberately weak — 4 positional rules. The value is in the architecture: two independent sources writing to the same field, merged via `join`, with the lattice guaranteeing convergence.

- **LLM results are additive, not replacing.** The LLM fills `Unknown` slots and either confirms or conflicts with symbolic results. If the LLM is unavailable, you still have something. If the LLM disagrees, you get `Conflict` — an explicit signal that a human should look.
- **Evaluation order doesn't matter.** Symbolic first then LLM, LLM first then symbolic, or in parallel — same result (commutativity + associativity). You can run the LLM lazily while symbolic runs eagerly, and they compose correctly.

## The CRDT connection

`Confidence[T].join` has the same algebraic properties as `VersionVector::merge` in event-graph-walker — both are state-based CRDT merge functions. Two collaborators can independently annotate the same document: Alice runs symbolic annotation, Bob asks an LLM. Their annotations merge via `join`, same as their text edits merge via the CRDT. `Confirmed` means both agree, `Conflict` means they don't. Automatic and deterministic.

This bridges canopy's CRDT layer (structural collaboration) and semantic analysis (meaning collaboration). Same algebra, different layer.

## What this enables in canopy

1. **Semantic rendering.** Role to CSS class to visual distinction. Section intros get different typography than code explanations.
2. **Semantic navigation.** "Jump to next code explanation" or "show all key points" — blocks have typed roles, not just syntactic kinds.
3. **Document quality signals.** A heading without a SectionIntro, a code block without a CodeExplanation — detectable structural quality gaps.
4. **LLM cost gating.** Symbolic fills `RuleBased` slots. LLM only runs on `Unknown`. When loom's damage tracking says a section didn't change, incr's Memo skips the LLM call. You pay for inference only on changed, unclassifiable content.
5. **Generic annotation infrastructure.** Topic modeling, terminology consistency, cross-reference detection — each is a new `T`, not a new system. The lattice, the merge, the incremental propagation, the CRDT collaboration all come for free from the algebra.

## Lattice structure

```
Unknown < Guessed(confidence, value) < RuleBased(value) < Confirmed(value) < Conflict
```

- `Unknown` — bottom (not yet analyzed)
- `Guessed(Float, T)` — LLM inference with confidence score
- `RuleBased(T)` — deterministic rule match
- `Confirmed(T)` — two sources agree
- `Conflict` — top (sources disagree, escalate)

Join rules: `Unknown` is identity, `Conflict` absorbs everything, agreeing sources promote to `Confirmed`, disagreeing sources produce `Conflict`.

Four laws proven via QuickCheck: commutativity, associativity, idempotency, identity.
