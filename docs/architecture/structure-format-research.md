# Structure-Format Projections: Research and Direction

How structure-format rendering relates to the projectional bridge vision,
what PL research offers, and how Canopy should approach this incrementally.

## The Problem

The text-format family is solved: `Layout[SyntaxCategory]` is a universal
IR consumed by multiple renderers. One language implements `Pretty`, all
text-format outputs follow.

The structure-format family has no equivalent. Each structural output
(DOT graph, tree view, inspector) goes directly from AST to output via
its own ad-hoc trait and data path:

```
AST → DotNode impl → Graph AST → DOT string       (needs Resolution)
AST → Renderable impl → ProjNode → ViewNode        (needs SourceMap)
AST → Debug derive → constructor string             (needs nothing)
```

The naive solution — "design an annotated tree IR like Layout" — misses
the deeper issue. The text-format IR works because all text outputs share
the same concern (linearization). Structure-format outputs need
**different semantic data per node** depending on the view:

| View                  | Needs per node                              |
|-----------------------|---------------------------------------------|
| Plain tree            | kind_tag, label, children                   |
| Scope-colored DOT     | + bound/free status, binding edges          |
| Type-annotated view   | + inferred type                             |
| Evaluation view       | + evaluation result                         |
| Source-mapped view    | + source range, token spans                 |

There is no universal annotation type. The annotation varies by what
semantic analysis has been performed.

## Why This Is Hard

The discrepancy is between **what we render from** and **what we want
to render from**.

In practice, we create ad-hoc representations from the AST (syntax
structure). But what we actually want is representations from
**semantics** (program meaning). Program semantics is difficult to
capture, and representations rendered from just superficial syntax
structure are far from what humans need to understand their programs.

This gap — syntax vs. semantics as the source of projections — is the
core difficulty of the structure-format problem. It cannot be solved
entirely, but closing it is the path toward human-friendly, malleable
software with explicit semantics that reflects user intent.

See `vision-projectional-bridge.md` for the full vision: syntax →
semantics → intent → mental model.

## Research Landscape

Five research directions address fragments of this problem. Each offers
a different mechanism for attaching varying semantic data to tree nodes.

### Trees That Grow (Najd & Peyton Jones, 2017)

A single tree type parameterized by a "phase" that controls what
annotations each node carries. GHC uses this for its AST: the parsed
phase has source locations, the renamed phase has resolved names, the
typechecked phase has types — all in the same `HsExpr` type. Extension
points are type families indexed by phase.

**Contribution:** Type-safe, compile-time extensibility. Each phase
gets exactly the data it needs. Adding a phase requires declaring all
extension points.

**Limitation:** Phases are fixed at compile time. The mechanism is
Haskell-specific (type families). Not suited for dynamically composed
semantic analyses.

Reference: https://arxiv.org/abs/1610.04799

### Cofree Comonad (annotated fixpoints)

`Cofree f a` is an `f`-branching tree where every node carries an
annotation of type `a`. The comonadic `extend` operation re-annotates
the tree from local context: `tree.extend(infer)` annotates every
subexpression with its inferred type.

**Contribution:** Clean separation of tree shape and annotation.
Re-annotation is principled (comonadic extend). Composable via
tupling: `Cofree f (Type, VarStatus)`. Histomorphisms build bottom-up
annotations naturally.

**Limitation:** One annotation type per tree (composition via tupling
is manual). Requires a base functor separate from the recursive type.

Reference: https://brianmckenna.org/blog/type_annotation_cofree

### Finally Tagless / Object Algebras

Already used in Canopy via `TermSym`. Each "interpretation" is an
algebra. Pretty-printing (`PrettyLayout`), evaluation, DOT rendering
could all be interpretations of the same algebra. Adding a renderer =
adding an interpretation. No intermediate tree needed.

**Contribution:** Solves the expression problem. Already proven in the
project. Each renderer computes during traversal without a shared IR.

**Limitation:** No reified intermediate tree to store, diff, cache,
or pass to multiple renderers. Semantic data (Resolution, types) must
be threaded through the interpretation manually. Not suitable when
multiple renderers need the same computed data.

Reference: https://okmij.org/ftp/tagless-final/course/lecture.pdf

### MLIR Dialects (operations + attributes + interfaces)

MLIR's "little builtin, everything customizable" philosophy.
Operations carry extensible attributes (compile-time constants).
Interfaces let passes query for specific attributes generically
without knowing all possible attributes. Dialects group related
extensions into namespaces.

**Contribution:** Most pragmatic approach to extensible per-node data.
Interfaces decouple consumers from producers. The "dialect" concept
enables modular semantic extensions.

**Limitation:** Attributes are dynamically typed (key-value). Heavy
infrastructure. Designed for compilers, not interactive editors.

Reference: https://arxiv.org/pdf/2002.11054

### Attributed Grammars (Knuth, 1968; Silver, JastAdd)

Formalize semantic attributes flowing up (synthesized) and down
(inherited) trees. Each attribute is independently defined with
computation rules. Modern implementations (Silver, JastAdd) support
modular attribute definitions and separate compilation.

**Contribution:** Most modular — each semantic analysis is an
independent attribute set. Well-studied theory. Composable by
definition. The formalism precisely names what Resolution (inherited)
and type inference (bidirectional) are.

**Limitation:** Requires an attribute grammar engine. More
infrastructure than the other approaches. Traditionally batch-oriented,
not incremental.

Reference: https://melt.cs.umn.edu/silver/tutorial/4_attribute_grammars/

### Ornaments (McBride, 2011)

Formalize the relationship between related data types — "lists are
natural numbers with extra labels." Each ornament adds information
and comes with a forgetful function back to the plain type. Algebraic
ornaments derive indexed types from specifications involving folds.

**Contribution:** Principled decoration of data types. The forgetful
function ensures decorated and plain types stay related. Relevant to
the relationship between bare AST and enriched AST.

**Limitation:** Requires dependent types for full expressiveness.
Theoretical, not widely implemented in practical languages.

Reference: https://personal.cis.strath.ac.uk/conor.mcbride/pub/OAAO/Ornament.pdf

## Synthesis: What Canopy Needs

No single approach is sufficient. The approaches address different
aspects of the problem:

| Aspect                         | Best addressed by       |
|--------------------------------|-------------------------|
| Language definition            | Finally Tagless (TermSym) — already in project |
| Reified annotated tree         | Cofree comonad pattern  |
| Phase-dependent annotations    | Trees That Grow         |
| Modular semantic analyses      | Attributed Grammars     |
| Extensible per-node metadata   | MLIR dialects/interfaces |
| Type-safe decoration           | Ornaments               |

The key insight from this conversation: **the structure-format IR
problem is not fundamentally about tree annotation.** It is about
representing program meaning explicitly enough that projections can
render from it.

The egglog knowledge base (relational facts about scope, types,
evaluation) is the closest thing Canopy has to a semantic model.
Projections become queries over this model:

```
DOT coloring     = query: "for each Var, is it Bound or Free?"
Type annotation  = query: "for each node, what is its HasType fact?"
Eval display     = query: "for each node, what is its Eval result?"
```

This reframes the problem from "design an annotated tree IR" to
"build a queryable semantic model and let projections query it."

## Execution Strategy: Bottom-Up with Top-Down Vision

We can only build by bottom-up, step by step — but without top-down
vision we easily stray into a meaningless maze. In practice, we go
back and forth between them.

**Top-down vision** (from `vision-projectional-bridge.md`):
Syntax → Semantics → Intent → Mental Model. Every projection closes
a gap in this bridge. The semantic model (egglog + incr) is the
substrate that enables semantic-level projections.

**Bottom-up execution:** Ship concrete projections that incrementally
enrich the semantic model. Each projection teaches us what semantic
facts matter. After several projections, the pattern becomes clear
enough to formalize.

```
Concrete projection                     What it teaches
─────────────────────────────────────────────────────────────
Pretty-printer (done)                   Text-format IR works via Layout[A]
Evaluator (done)                        Eval results are semantic facts
Scope-colored tree (next)               Resolution flows through protocol
Live inline evaluation (next)           Semantic overlay on text-format view
Type annotations (after egglog Ph.1)    First projection from egglog model
                                        ↓
                          Pattern emerges: queryable semantic model
                          → then formalize the structure-format layer
```

The research approaches inform design decisions along the way:
- When we need to annotate a tree for rendering → Cofree pattern
- When we need phase-dependent data → Trees That Grow thinking
- When we need modular semantic analyses → AG-inspired attribute sets
- When we need generic interfaces over varied data → MLIR interface pattern

But we do not commit to one approach upfront. We let the concrete
projections reveal which patterns are actually needed.

## Related Documents

- `vision-projectional-bridge.md` — the "why": bridging syntax to mental model
- `multi-representation-system.md` — the text-format family (solved) and expression problem
- `docs/plans/2026-04-02-lambda-evaluator-design.md` — evaluator as semantic model foundation
- `docs/TODO.md` §13 — concrete semantic projection candidates

## References

- Najd & Peyton Jones, "Trees That Grow" (2017) — https://arxiv.org/abs/1610.04799
- McKenna, "Bottom-up Type Annotation with the Cofree Comonad" — https://brianmckenna.org/blog/type_annotation_cofree
- Kiselyov, "Typed Tagless Final Interpreters" — https://okmij.org/ftp/tagless-final/course/lecture.pdf
- Lattner et al., "MLIR: A Compiler Infrastructure" (2020) — https://arxiv.org/pdf/2002.11054
- McBride, "Ornamental Algebras, Algebraic Ornaments" (2011) — https://personal.cis.strath.ac.uk/conor.mcbride/pub/OAAO/Ornament.pdf
- Knuth, "Semantics of Context-Free Languages" (1968) — attributed grammars
- Silver extensible AG system — https://melt.cs.umn.edu/silver/tutorial/4_attribute_grammars/
- Mokhov, "Algebraic Graphs with Class" (2017) — https://www.cs.tufts.edu/comp/150FP/archive/andrey-mokhov/algebraic-graphs.pdf
- O'Connor, "Functor is to Lens as Applicative is to Biplate: Multiplate" (2011) — https://arxiv.org/pdf/1103.2841
