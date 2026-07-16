# Vision: the projectional bridge

Why Canopy exists and what projectional editing is for.

See [Human-centered product principles](human-centered-product-principles.md)
for the behavior invariants this vision is designed around.

## The Gap

You write `let double = (x) => x + x`. You know what it means: a
function that doubles its input.

But the editor sees 23 characters. It has no idea what `double` is,
where `x` is bound, or what `double 5` evaluates to. You hold the
meaning; the tool holds text.

Every time you refactor, debug, or explain code, you are translating
between your understanding and the tool's flat character buffer. This
translation is the tax you pay for using a text editor.

The gap is wider than it appears. People often begin with a felt need rather
than a concrete plan, and they may recognize a mismatch before they can describe
the desired form. The interface should help them express and revise intent
gradually instead of requiring a complete specification up front.

Syntax-level editing forces this intention down through multiple
abstraction layers before it reaches the machine:

```
Mental Model  →  Intent  →  Semantics  →  Syntax
  (felt)        (hidden)    (explicit)    (mechanical)
```

Each translation can lose fidelity. The distance between what the person wants
and what they can manipulate in syntax is one source of programming difficulty.
Representations at more useful abstraction levels can reduce that translation
tax without pretending that the machine already knows the person's intent.

## The Bridge

Projectional editing fills these gaps with **representations at each
level**:

```
Syntax        ←→  readable text, formatted code
Semantics     ←→  scope coloring, type annotations, evaluation results
Intent        ←→  structural views, meaningful groupings, named patterns
Mental Model  ←→  direct manipulation, immediate feedback, embodied interaction
```

Each representation brings the user one step closer to the thing they
care about. Multiple representations of the same underlying semantic
enable the user to work at whichever level fits their current thinking.

The machine interpretations at each level — scope analysis, type
inference, clustering, relevance ranking — are provisional, plural,
visible, correctable, and reversible. They may preserve ambiguity
rather than resolving it prematurely. The person chooses which
representations to work with; the system does not claim the person's
mental model.

The goal is not just "multiple views of code." It is a **progressive
bridge** from mechanical program to human understanding — transforming
mere mechanical program into readable syntax, into explicit semantics,
into understandable intention, and finally fitting into the user's
chosen working representation.

## The unity of computer

When the tool meets the user at their level of chosen representation —
when they no longer translate between what they mean and what they
type — the computer becomes part of the body. This feeling, the unity
of computer, is the natural relationship between human mind and
computer program achieved with ease.

This is what Canopy is for. The system offers representations that
bring the user closer to their intent, but it does not claim to hold
the user's mental model. The person remains the authority over
meaning.

## Implications for Design

### Multi-representation system

The four text representations (Show, Debug, Source, Pretty) and the
structure-format family are not features — they are layers of the
bridge. Each representation serves a different distance from the user's
mental model.

### Semantic model over syntax annotation

Representations should render from **program meaning** (semantic model),
not from syntax with ad-hoc annotations. The egglog knowledge base,
type inference, name resolution — these capture fragments of meaning.
The richer the semantic model, the closer projections can get to user
intent.

### The structure-format question

The structure-format IR problem is not "how to annotate trees."

Program meaning must be explicit enough for projections to render it at
multiple levels of abstraction. Building the semantic model (egglog + incr
reactive graph) moves toward that goal; a tree annotation mechanism alone does
not.

### Editing is bidirectional

Every representation that helps users **see** should also help them
**act**.

A type-annotated view should accept type-level edits. A scope-colored
view should accept scope-level restructuring. The projectional bridge
works in both directions.
