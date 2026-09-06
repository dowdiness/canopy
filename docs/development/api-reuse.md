# API Reuse and MoonBit Implementation

Read this guide when adding or changing code that selects APIs, introduces
abstractions, or manipulates data. Documentation-only and configuration-only
changes do not require an API search or reuse report.

## Search Before Implementing

Before adding a function, method, helper, or type, or writing low-level loops
and data transformations, search project APIs and the MoonBit core APIs for
the actual data shape. Start with [the API map](../api-map.md) and confirm the
relevant definitions in the owning package; the code is authoritative.

Use the discovery tools that answer the question:

```bash
NEW_MOON_MOD=0 moon ide doc "<keyword>"
NEW_MOON_MOD=0 moon ide doc "<CoreType>::*"
NEW_MOON_MOD=0 moon ide doc "@<core-package>"
NEW_MOON_MOD=0 moon ide outline <pkg>
NEW_MOON_MOD=0 moon ide peek-def <symbol>
NEW_MOON_MOD=0 moon ide find-references <symbol>
```

Consider concrete core APIs such as `Map`/`Set`, `String`/`StringView`,
`Bytes`/`BytesView`, `Buffer`/`StringBuilder`, `Option`/`Result`, `cmp`/`math`,
and `Array`/`Iter`, according to the data involved. Reuse existing project
functions and owning-type methods or constructors when their contracts fit.

Perform the search once per distinct responsibility or data shape. Reuse that
evidence across files and edits in the same task. Search again when a changed
dependency, API contract, or requirement makes the earlier result stale.

## Record the Decision Once

Maintain one concise reuse record per logical change, in the PR's **Reuse
check** section or an implementation note linked from it. Without a PR, the
final response can carry the record. A final response may link an existing
record instead of repeating it. This reporting scope replaces the blanket
per-definition and final-report repetition in shared MoonBit guidance.

Record the relevant project and core candidates, where each is defined,
whether it is reused, and why an otherwise plausible candidate was rejected.
Consider alternatives when there is a real choice; do not invent a second
candidate merely to satisfy a count. For new helpers, name the responsibility
boundary and explain the gap in existing APIs.

Include any necessary mutation and its reason in the same record. Group uses
that share a justification; explain exceptional cases individually. Repeat
neither the search transcript nor the unchanged record in progress updates.

## Prefer Declarative MoonBit

- Use `match`, `guard`, and pattern matching to express decisions.
- Use the concrete core APIs above for lookups, optional/error handling,
  slicing, building, comparison, and transformation. Use `map`, `filter`,
  `fold`, `collect`, or list comprehensions when they express the operation.
- Use arrow functions for higher-order callbacks (`x => expr`,
  `(a, b) => { ... }`). Reserve `fn(...) { ... }` for named/local function
  values, explicit `raise`/`async` shape, or recursion.
- Prefer `ArrayView`, `StringView`, and `BytesView` over unnecessary copying.
  At validated core boundaries, do not expose internal mutable collections;
  use immutable views or defensive copies as ownership requires.

Account for every `let mut`, push loop, manual index loop, and `while` loop.
Mutation is appropriate for builders, true state machines, interop, or
measured performance needs. Local builder mutation may stay in a pure
function only when it has no observable external effect.

Use the affected-package validation loop in [Workflow](workflow.md), and
review generated interfaces for unintended API or trait-bound changes.
