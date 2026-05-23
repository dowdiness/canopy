# Vision: the projectional bridge

Why Canopy exists and what projectional editing is for.

## The Gap

You write `let double = λx. x + x`. You know what it means: a
function that doubles its input.

But the editor sees 23 characters. It has no idea what `double` is,
where `x` is bound, or what `double 5` evaluates to. You hold the
meaning; the tool holds text.

Every time you refactor, debug, or explain code, you are translating
between your understanding and the tool's flat character buffer. This
translation is the tax you pay for using a text editor.

The gap is wider than it appears. Users have something in mind when
they write — not always a concrete plan, but a wish, a thirst to
alleviate a pain. They are good at judging bad products but terrible
at articulating what they want in explicit words or images.

Syntax-level editing forces this intention down through multiple
abstraction layers before it reaches the machine:

```
Mental Model  →  Intent  →  Semantics  →  Syntax
  (felt)        (hidden)    (explicit)    (mechanical)
```

Each translation loses fidelity. The distance between what the user
wants and what they can manipulate (syntax) is too far. This is why
programming is hard — not because logic is hard, but because the
interface is at the wrong level.

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

The goal is not just "multiple views of code." It is a **progressive
bridge** from mechanical program to human understanding — transforming
mere mechanical program into readable syntax, into explicit semantics,
into understandable intention, and finally fitting into the user's
mental model.

## The Unity of Computer

When the tool meets the user at their mental model — when they no
longer translate between what they mean and what they type — the
computer becomes part of the body. This feeling, the unity of computer,
is the natural relationship between human mind and computer program
achieved with ease.

This is what Canopy is for.

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

The real question is how to represent program meaning explicitly
enough that projections can render from it at multiple levels of
abstraction. Building the semantic model (egglog + incr reactive
graph) gets us there; designing a tree annotation mechanism does not.

### Editing is bidirectional

Every representation that helps users **see** should also help them
**act**.

A type-annotated view should accept type-level edits. A scope-colored
view should accept scope-level restructuring. The projectional bridge
works in both directions.
