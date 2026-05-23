# AST as source of truth: the incremental hylomorphism pipeline

## Overview

This document summarizes the design principles that unify text editing, compilation, and collaborative editing into a single conceptual framework. The central thesis is:

> **Treat the AST as the source of truth. Unify construction from input (anamorphism) and projection to output (catamorphism) as a chain of incremental hylomorphisms.**

This principle provides a foundation for understanding parsers, incremental computation, CRDTs, serialization, and UI rendering within the same theoretical framework.

---

## 1. Fundamental concepts: construction and destruction of structure

### Catamorphism (Destruction / Fold)

An operation that collapses an existing recursive structure layer by layer according to an algebra `F A → A`.

```
cata : (F A → A) → μF → A
```

It produces an unstructured value from a structured one. Information flows in **one direction**, and the structure's holder possesses all necessary knowledge, making the operation straightforward.

Examples:
- AST → evaluation result
- AST → screen display
- data type → JSON bytes (serialization)

### Anamorphism (Construction / Unfold)

An operation that builds a recursive structure layer by layer from a seed according to a coalgebra `S → F S`.

```
ana : (S → F S) → S → νF
```

It produces a structured value from an unstructured one. Construction involves consuming external information (parsing) and the possibility of failure, making it inherently more complex than catamorphism.

Examples:
- text → AST (parsing)
- JSON bytes → data type (deserialization)
- user actions → internal state

### Hylomorphism (Construct Then Destroy)

A composite operation that builds structure via anamorphism and then tears it down via catamorphism.

```
hylo : (F B → B) → (A → F A) → A → B
        ^^^^^^^^    ^^^^^^^^^^
        algebra      coalgebra
        (cata)       (ana)
```

The intermediate structure μF is theoretically eliminable (deforestation), but in practice it is retained as an intermediate representation for optimization and inspection.

### The Asymmetry: Why Construction Is Harder Than Destruction

| Property | Catamorphism (Destruction) | Anamorphism (Construction) |
|----------|---------------------------|---------------------------|
| Knowledge location | Data type holds all knowledge | Knowledge is split between producer and consumer |
| Failure | Cannot occur | Occurs when input is malformed |
| Impact of local changes | Tends to remain local | Can cause global structural changes |
| Polymorphism | One axis (output target) | Two axes (input source x target type) |

This asymmetry has practical consequences for both sides. Catamorphisms are simple enough that a general abstraction strategy (Finally Tagless / Church encoding) works uniformly. Anamorphisms require a different discipline — the intermediate structure must be carefully designed so that the knowledge split between producer and consumer does not become a leaky abstraction. Sections 2 and 3 develop these two strategies.

---

## 2. Coalgebra locality: the anamorphism design principle

The coalgebra `S → F S` unfolds structure one layer at a time. Each layer is a local construction decision: "I saw these tokens, I grouped them into a node of this kind." The resulting structure is a record of all such decisions.

For this record to serve as a good intermediate representation in a hylomorphism chain, each layer must be **self-contained** — its identity must not depend on where it sits in the larger structure. This is the principle of coalgebra locality.

### Why Locality Matters

Without locality, incremental reuse is prohibitively expensive. If a subtree's identity depends on its absolute position, reusing it at a different position requires O(n) normalization across the entire subtree. With locality, reuse is O(1) — the subtree is a pure value that means the same thing regardless of where it appears.

This is the concrete mechanism behind the abstract observation that "local input changes can cause global structural changes" (the asymmetry table in section 1). Coalgebra locality is the design discipline that prevents local changes from propagating globally through the intermediate structure.

### The Four Properties

A good anamorphism abstraction produces structure that satisfies four properties. Each property addresses one row of the asymmetry table:

**Completeness.** The intermediate structure preserves everything any downstream catamorphism could need. If a consumer must reach back to the original input, the boundary has leaked. This addresses the knowledge split: the structure must carry all of the producer's knowledge so the consumer never needs to coordinate with the producer.

**Context-freedom.** Each fragment's identity is independent of its position in the larger structure. Achieved by storing only intrinsic properties (kind, relative width, children) and computing positional context lazily in a wrapper. This addresses the local-to-global impact problem: position-independent subtrees are unaffected by changes elsewhere.

**Uniform error representation.** Malformed input produces the same kind of structure as well-formed input, with errors represented as values within the structure rather than through a separate channel. This addresses the failure problem: downstream consumers always receive a complete tree and can fold it uniformly.

**Transparent structure.** The representation's shape is its meaning. No hidden invariants, no internal state that consumers must understand. This addresses the two-axis polymorphism problem: any consumer can interpret the structure by inspecting its public form, without coupling to the producer's construction logic.

The [Anamorphism Discipline Guide](./anamorphism-discipline.md) turns each property into actionable design guidelines.

### Example: CstNode

The CST in this project satisfies all four properties:

- **Complete**: every byte of source is represented, including whitespace, comments, and error tokens.
- **Context-free**: nodes store relative widths rather than absolute positions. The same subtree object can appear at different locations without internal modification.
- **Uniform errors**: `ErrorNode` is a `CstNode` with a different kind. The parser always produces a tree.
- **Transparent**: `{ kind, children, width }`. Shape is meaning.

Absolute positions are computed lazily by `SyntaxNode`, a wrapper that accumulates widths during traversal. This separation — intrinsic properties in the structure, contextual properties in the wrapper — is a direct application of coalgebra locality.

---

## 3. Finally tagless: the catamorphism abstraction

Where anamorphisms need carefully designed concrete structure, catamorphisms benefit from the opposite: abstracting away the structure entirely.

Church encoding represents a data type as "the function that accepts its fold":

```
Church Nat  = ∀r. (r → r) → r → r
Church List = ∀r. (a → r → r) → r → r
```

A natural number encoded this way declares: "Given any algebra (a successor function and a zero), I can fold myself using that algebra." The data type presents its own Church encoding — it holds all the knowledge needed for destruction, and the consumer provides only the interpretation. Serialization follows the same pattern: a `Serialize` trait turns any data type into a Church encoding over a serializer algebra.

This is why catamorphisms are simple (section 1): the structure holder possesses all necessary knowledge. Church encoding / Finally Tagless makes this explicit by turning the fold into a protocol.

### The Trait as Protocol

```
trait ExprSym {
  lit(Int) → Self
  add(Self, Self) → Self
}
```

Each interpreter (evaluator, pretty-printer, compiler) provides a different implementation of this trait. The data type is folded through the trait without committing to a specific interpretation. This achieves:

- **Zero intermediate allocation**: the fold writes directly to the output format.
- **Open extensibility**: new interpreters can be added without modifying existing code.
- **Composability**: interpreters can be composed (e.g., evaluate and pretty-print simultaneously).

### Why This Works for Catamorphisms but Not Anamorphisms

Finally Tagless produces opaque functions — `∀r. ExprSym r => r` cannot be inspected, compared, or partially reused. This is acceptable for catamorphisms because the fold consumes the structure once and produces a flat value.

For anamorphisms, the intermediate structure must be inspected for incremental reuse (the ReuseCursor's four-condition protocol), compared for change detection, and partially shared across time. Opacity is a liability here rather than an asset.

This is the fundamental reason the two sides of the hylomorphism need different abstraction strategies: catamorphisms benefit from hiding structure (Church encoding), while anamorphisms require exposing it (coalgebra locality).

---

## 4. The boundary pattern: hylomorphisms at every system boundary

```
External Representation_1 <-(ana)-> Internal Representation <-(cata)-> External Representation_2
```

This structure recurs at every system boundary.

| System | Input (ana) | Internal Rep | Output (cata) |
|--------|------------|--------------|---------------|
| Compiler | Source code → AST | IR | IR → Target code |
| Serde | JSON bytes → JsonValue | Value / types | types → MsgPack bytes |
| UI (TEA) | User actions → Model | Model | Model → View |
| Editor | Text → AST | AST | AST → Screen display |
| Network | Packets → Message types | Message types | Message types → App logic |

A compiler is not a single hylomorphism but a **chain of hylomorphisms where the functor changes at each stage**.

```
ana₁ → μF₁ → cata₁/ana₂ → μF₂ → cata₂/ana₃ → μF₃ → cata₃
parse   AST   lowering      MIR   codegen        ...
```

---

## 5. The full pipeline: loom + incr + CRDT

### Pipeline Diagram

```
  User A's edits                User B's edits
        │                             │
        ▼                             ▼
  ┌───────────┐      sync      ┌───────────┐
  │ CRDT Ops  │◄──────────────►│ CRDT Ops  │
  └─────┬─────┘                └─────┬─────┘
        │ ① fold                     │ ① fold
        ▼                             ▼
  ┌───────────┐                ┌───────────┐
  │ Document  │                │ Document  │
  │  state    │                │  state    │
  └─────┬─────┘                └─────┬─────┘
        │ ② ana (loom)               │ ② ana (loom)
        ▼                             ▼
  ┌───────────┐                ┌───────────┐
  │    CST    │                │    CST    │
  │(holes +   │                │(holes +   │
  │ errors)   │                │ errors)   │
  └─────┬─────┘                └─────┬─────┘
        │ ③ cata (incr)              │ ③ cata (incr)
        ▼                             ▼
  ┌───────────┐                ┌───────────┐
  │  Typed    │                │  Typed    │
  │   AST     │                │   AST     │
  └─────┬─────┘                └─────┬─────┘
        │ ④ cata                     │ ④ cata
        ▼                             ▼
  ┌───────────┐                ┌───────────┐
  │  Screen   │                │  Screen   │
  │  display  │                │  display  │
  └───────────┘                └───────────┘
```

### Responsibilities at Each Boundary

**① CRDT Ops → Document State** (fold)
- Fold the operation sequence to obtain the document's text state
- eg-walker / FugueMax determines the ordering of concurrent insertions
- Output: text buffer. Damage region (what changed) should ideally be carried forward but is currently rediscovered via text diff.

**② Document State → CST** (anamorphism — loom)
- Tokenize and parse the text to construct a concrete syntax tree
- Error recovery (`expect`, `skip_until`, `skip_until_balanced`) ensures the parser always produces a complete tree
- Incremental parsing via ReuseCursor: only re-parse the damage region, reuse unchanged subtrees at O(1) through position-independent structural sharing
- Output: CstNode tree that satisfies the four properties. May contain error nodes.

**③ CST → Typed AST** (catamorphism — incr)
- Perform semantic analysis: name resolution, type checking, flow analysis
- Track dependencies via an incr/Salsa-style dependency graph for incremental recomputation
- Track cross-tree dependencies (name references, type propagation) that do not follow CST parent-child relationships
- Output: materialized views including type information, diagnostics, completion candidates
- Status: aspirational. Current implementation has name resolution only.

**④ Typed AST → Screen Display** (catamorphism)
- Compute syntax highlighting, indentation, error display from the typed AST
- Use virtual DOM / incremental rendering to redraw only the damage region
- Status: MVP. Full re-render via DOT/Graphviz SVG. Projection module exists in MoonBit but is not wired to the web frontend.

### The Role of incr: Memoizing Hylomorphisms

incr **memoizes** the hylomorphism at each boundary. When the input changes partially, only the affected nodes are recomputed.

```
Without incr: 1 char change → re-parse everything → re-typecheck everything → redraw everything
With incr:    1 char change → re-analyze 3 tokens → re-typecheck 2 functions → redraw affected lines
```

This is the same concept as incremental maintenance of materialized views. The CST corresponds to the base table; type information and screen display correspond to materialized views. Updates to the base table propagate incrementally to the views.

---

## 6. Technical challenges at each boundary

### Boundary ①: CRDT → Document State

**Granularity mismatch.** CRDTs operate at the character level, but the parser needs to know "which tokens were affected." A single character change can alter the token type (e.g., `42` → `4.2` changes Int to Float).

**Non-deterministic arrival order.** In CRDTs, the order of operation arrival is not guaranteed. How concurrent edits from multiple users are ordered depends on FugueMax's ordering decisions, and the result can affect tokenization.

**The completeness gap.** A CRDT knows which position was affected by each operation, but this information is discarded when the document state is materialized as a flat string. Consumers must rediscover it via text diffing — an instance of the "Retrospective Diff" anti-pattern (see [Anamorphism Discipline Guide](./anamorphism-discipline.md)).

### Boundary ②: Document State → CST

**Context-dependent lexer state.** Template literals, heredocs, nested comments, and similar constructs make lexer state depend on surrounding context. A single character change can fundamentally alter the lexer's state machine, potentially affecting all subsequent tokens.

**The context-freedom solution.** CstNode stores relative widths instead of absolute positions. This makes subtrees context-free: the same subtree object can be reused at a different position without any internal modification. The ReuseCursor exploits this by checking four conditions (kind match, leading token match, trailing context match, no damage overlap) before reusing a subtree at O(1).

### Boundary ③: CST → Typed AST (The Hardest Boundary)

**Local changes cause global structural impact.** A single character change in the text can fundamentally alter CST parent-child relationships (e.g., deleting the `e` from `else` collapses the entire if-else structure). The CST handles this through context-freedom; the typed AST must handle it through context-free node identity (arena-based interning).

**Error recovery stability.** Parse results under error conditions must be stable with respect to user edits. The same error situation must always produce the same recovery strategy (idempotency) to guarantee that unrelated parts of the tree do not fluctuate.

**Dependencies that cross tree structure.** The CST is a tree, but semantic dependencies form a DAG. Type-checking function `foo` may depend on the type of function `bar` — a dependency that has nothing to do with parent-child relationships in the tree.

**Damage propagation through semantics.** Changing one function's signature can invalidate type-checking results in another file. Damage can jump to physically distant locations. An incr/Salsa-style query-based dependency graph is needed to track what must be recomputed.

### Cross-Boundary: Granularity Mismatch

The "unit of change" differs at each stage.

```
CRDT       → character level
Lexer      → token level
Parser     → CST node level
Type check → symbol / query level
Rendering  → pixel / line level
```

Converting "what changed" at one stage into "what to recompute" at the next stage has its own computational cost. At each conversion, a completeness gap means the next stage must rediscover change information that the previous stage already had.

---

## 7. Two-Layer Architecture

When both incremental construction and structural observation are needed, separate the anamorphism's output from the catamorphism's input into two layers.

### Layer 1: Concrete (Anamorphism Output)

Produced by the construction process. Must satisfy the four properties from section 2. Designed to be inspected, compared, and incrementally reused.

In this project: `CstNode` — position-independent, lossless, uniform error nodes, transparent `{ kind, children, width }`.

### Layer 2: Abstract (Catamorphism Input)

Consumed by downstream folds. Provides typed, semantic access to the concrete structure without adding information. May use Finally Tagless (section 3) for open extensibility, or typed views for concrete navigation.

In this project: `SyntaxNode` views — typed wrappers like `LambdaExprView` that cast by kind, name children, and skip trivia. `Term` conversion is a catamorphism over views.

### The Boundary Between Layers

Information flows monotonically from concrete to abstract: each step discards information, never adds it.

```
CstNode ──→ SyntaxNode ──→ View ──→ Term
  all          derives        derives    semantic
  info         positions      typed      only
               (from widths)  names      (lossy)
                              (from kinds)
```

Each step derives new presentations from data already in the CstNode — no external information enters the chain. The monotonic flow is what keeps the abstraction non-leaky. A leaky abstraction hides information that consumers eventually need, forcing them to reach behind the boundary. Here, the concrete layer hides nothing (it is complete and transparent), and each abstract layer projects from what it receives. No consumer needs to reach backwards.

The concrete layer is not an implementation detail hidden behind the abstract layer — it is a first-class artifact that the system depends on for incremental reuse. The abstract layer offers a convenience for typed access; it does not replace the concrete layer.

---

## 8. Limits of recursion schemes

### What They Capture

- **Structural transformation:** conversion from one representation to another (parsing, code generation, serialization)
- **Structural traversal:** aggregation and projection over existing structures (evaluation, display, type information extraction)
- **Incremental structural updates:** incremental computation as memoization of hylomorphisms

### What They Do Not Capture

- **Bidirectional information flow:** type inference with unification requires constraint solving rather than simple folds
- **Integration of causally ordered operations:** CRDT operation integration requires causal graph traversal rather than simple folds
- **Reuse across time:** incremental computation can be framed as memoized hylomorphisms, but the decision of what to reuse and what to invalidate lies outside the recursion scheme framework

---

## References

- Meijer, E., Fokkinga, M., & Paterson, R. (1991). *Functional Programming with Bananas, Lenses, Envelopes and Barbed Wire.*
- Carette, J., Kiselyov, O., & Shan, C. (2009). *Finally Tagless, Partially Evaluated.* JFP.
- Omar, C. et al. (2019). *Hazel: A Live Functional Programming Environment with Typed Holes.*
- Arvo, J. et al. (2022). *Grove: A Collaborative Structure Editor.*
- Matklad. (2023). *Resilient LL Parsing Tutorial.*
