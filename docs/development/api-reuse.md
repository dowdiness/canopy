# API Reuse

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

For code style and mutation rules, follow
[Coding Conventions](conventions.md#declarative-code-and-mutation).
