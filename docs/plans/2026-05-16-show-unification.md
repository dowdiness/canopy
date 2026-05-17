# Show Unification — Route Inspector Through `Renderable::kind_tag`

Task 1 of a three-task Renderable/Pretty integration sequence. First
deliverable of the Inspector traceability workstream
([[project_inspector_traceability_workstream]]). Unblocks the Intent +
Patch + Collab panels (TODO §9) by making `ProjNode`/`GenericTreeOp`/`SpanEdit`
debug-friendly and routing the inspector chip through the existing
`Renderable::kind_tag` instead of a label-string parser.

## Status — Task 1 shipped 2026-05-17 (PRs #277, #278)

- PR #277 — `feat(core,projection): real Show on editor-infrastructure
  types`. Real `Show` impls landed for `SpanEdit`, `GenericTreeOp`,
  `ProjNode[T : Renderable]`, and `InteractiveTreeNode[T : Renderable]`
  with the escape helper and inspect-test coverage from Steps 1–5 below.
- PR #278 — `feat(ideal,lang/lambda/proj): route inspector kind chip
  through Renderable`. `term_css_class` plus the `view_outline` /
  `view_inspector` migration and CSS additions from Steps 6–13 below.
- TODO §15 item 1 is checked. The remaining inspector-workstream
  deliverables (Intent + Patch panels, SourceMap wiring, Collab panel)
  are unblocked and tracked in [[project_inspector_traceability_workstream]].
- Tasks 2 (`pretty_unparse` free function) and 3 (`Canonical` companion
  trait) are still open; see "Sequencing context" below.

The trace below describes the plan as written before implementation and
is retained as the design record.

## Sequencing context

Aligned on the invasiveness ladder:

1. **(this PR)** canopy-only: real `Show` on editor-infrastructure types;
   inspector consumes `Renderable::kind_tag`; outline CSS consumes typed
   `term_css_class`. No trait changes.
2. **`pretty_unparse` free function** (loom or canopy): add
   `pub fn[T : Pretty] pretty_unparse(t : T) -> String = pretty_print(t,
   width=1_000_000)`. Implementors with `Pretty` may optionally call it
   from `Renderable::unparse` (`Term::unparse = pretty_unparse(self)`).
   Replaces the original "Task 2: `Renderable: Pretty` supertrait" — the
   supertrait would force every Renderable type to be Pretty, which is an
   over-coupling (per moonbit-traits audit anti-pattern: forcing supertrait
   that only some implementors need). The free function preserves the
   Pretty-as-canonical-layout direction without coupling the trait
   hierarchy.
3. **loom: `Canonical` companion trait** — new
   `trait Canonical { canonical(Self) -> Self }` with invariant
   `same_kind(canonical(self), self)` (enforced by property tests). Default
   `placeholder = pretty_print(Canonical::canonical(self), width=1_000_000)`
   with per-variant overrides where current placeholder strings aren't
   pretty-prints of any canonical instance (`Module`, `Unbound`, `Error` in
   the Term case — three of eleven variants).

   **Note on the signature.** `canonical(Self) -> Self` is Pattern 1
   (Self-closed endomorphism) in shape, but the semantics are *not*
   pure variant-tag routing. The implementor decides which internal
   discriminators to preserve and which to canonicalize. For Term:
   `canonical(Bop(op, _, _)) = Bop(op, Int(0), Int(0))` preserves `op`
   because placeholder differs (`"0 + 0"` vs `"0 - 0"`);
   `canonical(Lam(_, _)) = Lam("x", Var("x"))` discards the param
   because placeholder is invariant in it. `same_kind(canonical(self),
   self)` is the *minimum* enforceable invariant; the load-bearing
   contract is type-specific ("preserves operationally-relevant
   discriminators") and lives in the trait's doc-comment and per-type
   property tests.

   For Term, the carve-outs for hand-written placeholder (vs defaulted
   from canonical+pretty) are `Module`, `Unbound`, `Error` (three of
   eleven) — their placeholder strings don't match any
   `pretty_print(canonical_instance)` output regardless of how
   `canonical` is defined. `Bop` does *not* need to be a carve-out as
   long as `canonical` preserves the `op` field.

Tasks 2-3 are out of scope for this plan; documented here for sequencing
awareness.

Removed from the original four-task plan: a hypothetical `derive(KindTag)`
fourth task. MoonBit has no user-extensible derive mechanism. Keep
`kind_tag` hand-written per type; the `_mechanical.mbt` filename suffix
already marks it as a codegen candidate if loomgen ever takes it on.

## Why

The §7 audit (PRs #272-#275) deliberately kept three `Show` stubs as
scaffolding for this workstream:

- `core/proj_node.mbt:21` — `Show for ProjNode[T : Debug]` delegates to
  `@debug.to_string`.
- `core/types.mbt:99` — `Show for GenericTreeOp` delegates to
  `@debug.to_string`.
- `core/types.mbt:37` — `Show for SpanEdit` delegates to `@debug.to_string`.

Meanwhile `examples/ideal/main/view_outline.mbt:9` defines `kind_of(label :
String) -> String` — a label-string parser that produces both:

- CSS class strings (`"lambda"`, `"app"`, `"let"`, `"if"`, `"unit"`,
  `"error"`, `"binop"`, `"term"`) read by
  `examples/ideal/web/styles/editor.css:299-307` (e.g.
  `.tree-row.kind-lambda .tree-accent`).
- Display strings shown in `view_inspector.mbt:86` (`[text(kind)]`).

Both views consume the kind by *parsing the rendered label*, even though
`InteractiveTreeNode[T]` already carries the typed `kind : T`
(`projection/tree_editor_model.mbt:13`) and `Renderable::kind_tag(kind)`
already returns exactly the variant-tag strings the inspector wants
(`loom/examples/lambda/src/ast/proj_traits_mechanical.mbt:36-50`,
already consumed by projection at `tree_editor_model.mbt:99` and
`tree_editor_refresh.mbt:261`).

## Scope

In:

- `core/proj_node.mbt` — real `Show for ProjNode[T : @loomcore.Renderable]`
  (bound constraint swap from `Debug` → `Renderable`).
- `core/types.mbt` — real `Show for GenericTreeOp`, real `Show for SpanEdit`,
  shared `priv fn escape_for_show` helper.
- `projection/tree_editor_model.mbt` — real
  `Show for InteractiveTreeNode[T : @loomcore.Renderable]`.
- `lang/lambda/proj/` — new `term_css_class : Term -> String` for
  language-driven CSS class derivation. Re-export from `lang/lambda/` if
  needed for example consumption.
- `examples/ideal/main/moon.pkg` — import wiring for `term_css_class` and
  `@loomcore.Renderable::kind_tag`.
- `examples/ideal/main/view_outline.mbt` — delete `kind_of()`; consume
  `term_css_class(node.kind)` for CSS classes; keep `node.label` for the
  tree-row body (already correct).
- `examples/ideal/main/view_inspector.mbt` — consume
  `@loomcore.Renderable::kind_tag(node.kind)` for the display chip and
  drop the `kind-\{kind}` CSS class entirely (it has no matching selector
  today — see Design Notes).
- `examples/ideal/web/styles/editor.css` — add `.tree-row.kind-unit`,
  `.kind-hole`, `.kind-unbound` selectors (the three classes
  `term_css_class` produces that don't have styling today).
- Whitebox tests for the new `Show` impls (snapshot via `inspect`).
- Audit existing snapshots that rendered these types via the stub impl.

Out:

- **`Show for NodeId`**. Currently delegates to `@debug.to_string`
  (`core/types.mbt:9-11`). Touching it changes the output of
  `node_id.to_string()` at many in-tree call sites in
  `lang/lambda/edits/text_edit_structural.mbt:32`,
  `text_edit_wrap.mbt:9`, `text_edit_commit.mbt:8` (per Codex v2 audit) —
  some of which build user-facing error messages. Localize the change
  instead: in `Show for ProjNode` / `Show for InteractiveTreeNode` /
  `Show for GenericTreeOp`, format the node ID integer directly as
  `"#\{self.node_id}"` (`#\{source_id}`, `#\{target_id}`, etc.) without
  going through `Show for NodeId`. The `#N` notation falls out at the call
  sites that want it, leaving the rest of the codebase alone.
- Changes to `Show for Term` (`loom/examples/lambda/src/ast/ast.mbt:44`).
  Intentionally stays as `@debug.to_string`. The compact source form is
  `print_term` / `Renderable::unparse`; the projection-display form is
  `Renderable::label`; width-aware is `pretty_print`. Show's job is
  debug-friendly compact, which Debug already covers for Term.
- Changes to `Renderable` or `Pretty` traits themselves — see Tasks 2-3.
- `Canonical` trait — Task 3.
- The 11 collaboration `Show` stubs (`PeerCursor`, `PeerPresence`,
  `PresenceStatus`, `SyncStatus`, `SyncMessage`, `SyncErrorReason`,
  `DragState`, `EditModeState`, `EphemeralNamespace`, `EphemeralValue`,
  `EphemeralEventTrigger`). They scaffold the Collab panel (TODO §9 third
  item).
- Intent + Patch panel UI itself (TODO §9 first/second items).
- `SourceMap` query wiring (TODO §15 third item).

## Current State

- `Show for NodeId` (`core/types.mbt:9-11`): writes `@debug.to_string(self)`
  → `"NodeId(11)"`. **Stays as-is** (localizing per Codex v2).
- `Show for ProjNode[T : Debug]` (`core/proj_node.mbt:21-23`): recursive
  Debug dump of the whole subtree.
- `Show for GenericTreeOp` (`core/types.mbt:99-101`): same pattern.
- `Show for SpanEdit` (`core/types.mbt:37-39`): same pattern.
- No `Show` impl on `InteractiveTreeNode[T]` (only `derive(Debug)`).
- `Show for Term` (`loom/examples/lambda/src/ast/ast.mbt:44-46`): delegates
  to `@debug.to_string`. **Stays as-is.**
- `Show for Bop` (`loom/examples/lambda/src/ast/ast.mbt:13-15`): same.
  **Stays as-is.**
- `Renderable for Term` is already real and complete
  (`loom/examples/lambda/src/ast/proj_traits.mbt` for the semantic methods,
  `proj_traits_mechanical.mbt` for `kind_tag`). Variants:
  `Int / Var / Lam / App / Bop / If / Module / Unit / Unbound / Error / Hole`
  (11 variants).
- `view_outline.mbt:9-27` `kind_of(label)`:
  - `λ`-prefix → `"lambda"`, `App` → `"app"`, `let`-prefix → `"let"`, `if` →
    `"if"`, `()` → `"unit"`, `Error:`-prefix → `"error"`, `Plus`/`Minus` →
    `"binop"`, else → `"term"`.
- `view_outline.mbt:70`, `view_outline.mbt:100`: `kind` used in row CSS
  class `"tree-row depth-{depth} kind-{kind}…"`.
- `view_outline.mbt` tree row body content is `node.label` (i.e.
  `Renderable::label`). **Stays as-is.**
- `view_inspector.mbt:80,86`: `let kind = kind_of(node.label)`; the same
  string is used for CSS class AND display text. The CSS class today is
  inert — `editor.css` has no `.inspector-value.kind-*` selectors.
- `editor.css:299-307`: selectors keyed on `.tree-row.kind-lambda`,
  `.tree-row.kind-let`, `.tree-row.kind-module`, `.tree-row.kind-app`,
  `.tree-row.kind-int`, `.tree-row.kind-var`, `.tree-row.kind-if`,
  `.tree-row.kind-binop`, `.tree-row.kind-error`. Missing today:
  `.tree-row.kind-unit`, `.tree-row.kind-hole`, `.tree-row.kind-unbound`.

In-tree `ProjNode[T]` consumers and their `T`:

- Production: `T = @lambda.Term`, `T = @json.JsonValue`, `T = @markdown.Block`,
  `T = @markdown.Inline` — all implement `Renderable`.
- Tests: `T = Int` in `core/proj_zipper_wbtest.mbt:7` and
  `core/source_map_wbtest.mbt:46`. These helpers never trigger `Show for
  ProjNode` — they exist only for tree-structure / zipper tests. The bound
  swap (`Debug` → `Renderable`) makes them lose the Show instance; if any
  test asserts via `inspect(proj_node, ...)` on a `ProjNode[Int]`, it
  would need to switch to `@debug.to_string(proj_node)` or get a
  `Renderable for Int` test helper.

## Desired State

A debug-mode reader of the inspector sees node identity, kind, and range
without the framework parsing a rendered string. Adding a language
requires providing a `Renderable` impl (already required) plus an optional
`term_css_class` for language-specific accent colors.

Concretely:

1. `SpanEdit { start=25, delete_len=3, inserted="add" }` renders as
   `"@25 -3 +«add»"`. Escaping rule: backslash escape `\`, `«`, `»`, all
   C0 control chars (NUL, BS, TAB, LF, FF, CR, ESC, etc.) and DEL using
   `\n`/`\r`/`\t` for the common cases and `\u{XX}` for the rest.
2. `GenericTreeOp::Drop(source=#11, target=#12, position=After)` renders as
   `"Drop(#11→#12 After)"`. Verb-first; positional arguments only (drop
   the labelled-argument noise from Debug). `CommitEdit(#N, "v")` renders
   as `"CommitEdit(#N «escaped_v»)"` (guillemets for the string payload,
   matching SpanEdit's convention).
3. `ProjNode { node_id=9, kind=App, start=25, end=47, children=… }`
   renders as `"#9 App [25..47]"`. Children are not recursively inlined.
   The `"App"` comes from `Renderable::kind_tag(self.kind)`. The `"#9"`
   comes from formatting `self.node_id` directly (not through
   `Show for NodeId`).
4. `InteractiveTreeNode` with same fields renders identically.
5. `view_outline` row body remains `node.label` (no change). Row CSS class
   derives from `term_css_class(node.kind)`.
6. `view_inspector` chip text comes from
   `@loomcore.Renderable::kind_tag(node.kind)`. The inert
   `kind-\{kind}` CSS class on the chip is dropped (no selector targets
   it).
7. `view_outline::kind_of` is deleted.

## Design Notes

### Why `T : Renderable` not `T : Show` on `Show for ProjNode`

`Show for ProjNode` describes the *wrapper* (`#9 App [25..47]`) and needs
only the kind's variant tag, not the kind's full Show. Bounding on Show
would make ProjNode's debug rendering recurse through whatever the kind's
Show happens to do (for Term: a recursive Debug dump).

**Principle:** the trait bound should be the *minimum capability required
to produce the output*. `Renderable::kind_tag` is exactly that minimum.

This is Pattern 3 (capability composition) from the moonbit-traits guide
in action — Show consumes Renderable as a capability, not as an alias.
Per the audit, worth pinning explicitly so future contributors don't
"helpfully" generalize the bound to `Show`.

### Why `Renderable: Pretty` supertrait was rejected (Pattern 8 / Solution 6 awareness)

The earlier sequencing draft had `Renderable: Pretty` as Task 2's
supertrait, defaulting `unparse` from `pretty_print`. This was reframed
because of how loom uses `Pretty`.

`Pretty for Term with to_layout(self) -> Layout[SyntaxCategory]`
(`loom/pretty/traits.mbt:11`,
`loom/examples/lambda/src/ast/pretty_traits.mbt:212`) is
**Pattern 8 / Solution 6** (defunctionalized associated types) in the
moonbit-expression-problem framework: `Layout[A]` is the underlying
parameterized container; `Pretty` fixes `A = SyntaxCategory` as the
default annotation. Hypothetical future siblings — `EditorLayout`
(annotations carrying node IDs for editor overlays), `LspLayout`
(annotations carrying semantic-token IDs) — would *not* implement
`Pretty` because their `to_layout` returns `Layout[EditorAnn]` or
`Layout[LspAnn]`, which doesn't unify with `Pretty::to_layout`'s
signature. They would be reached via type ascription on `replay`:

```moonbit
let pretty = term.to_layout()                       // Layout[SyntaxCategory]
let editor = (replay(term) : EditorLayout).layout    // Layout[EditorAnn]   — hypothetical
let lsp    = (replay(term) : LspLayout).layout       // Layout[LspAnn]      — hypothetical
```

Neither sibling exists in canopy today (Pretty is the only `TermSym`
interpretation in this repo as of 2026-05-16), but the framework is
shaped for them. `Renderable: Pretty` would lock every Renderable type
onto the default `SyntaxCategory` annotation, foreclosing the sibling
path — and would force Markdown's `Block`/`Inline` (which implement
Renderable but not Pretty today) to grow Pretty impls. Task 2's free
function `pretty_unparse[T : Pretty](t : T) -> String` opts in per-type
without forcing the supertrait, preserving Solution 6's
"each interpretation fixes A concretely" property.

### Why `Renderable` stays a bundle trait (not split into capabilities)

`Renderable` has 4 methods today and would have 5-6 transitive
capabilities after Task 3. By the moonbit-traits guidance, this is on
the over-sized end. Split candidates:

| Method | Could be its own capability | Used by |
|--------|----|---|
| `kind_tag` | `KindTag` | projection stamp, inspector chip |
| `label` | `Label` | outline row body |
| `placeholder` | `Placeholder` | structural-edit menu |
| `unparse` | `Unparse` | serialization / copy-paste |

**Why we keep them bundled:** no canopy consumer today needs <2 of these
capabilities. Splitting would force every implementor (4 today: Term,
JsonValue, markdown Block, markdown Inline) to write 4 impl blocks
instead of 1, and every consumer to list bounds — for zero current
benefit.

**Revisit trigger:** the first consumer that genuinely needs only one
capability (e.g. a serialization-only path that doesn't want to require
implementors to define `placeholder`). At that point, split out the
needed capability as a separate trait and make Renderable a subtrait
of it.

### Why `Show for NodeId` is not touched

The `#N` notation pervades the new format strings. The straightforward
move — change `Show for NodeId` to produce `"#11"` — also changes the
output of `node_id.to_string()` at production call sites that build
error messages (`lang/lambda/edits/text_edit_structural.mbt:32`,
`text_edit_wrap.mbt:9`, `text_edit_commit.mbt:8`, etc.). That's a
user-visible behavior change for unrelated code paths.

**Localize instead:** in each new `Show` impl, format the underlying
integer directly:

```moonbit
// Show for ProjNode
logger.write_string("#\{self.node_id} \{kind_tag(self.kind)} [\{self.start}..\{self.end}]")
// Show for GenericTreeOp Drop variant
let NodeId(src) = source
let NodeId(tgt) = target
logger.write_string("Drop(#\{src}→#\{tgt} \{position})")
```

The `#N` notation lands where this plan needs it. `Show for NodeId` and
every other call site stays unchanged.

### Helper placement: duplicate the format

`Show for ProjNode` lives in `core/`; `Show for InteractiveTreeNode`
lives in `projection/`. They can't share a `priv fn` across packages.
Options:

- **Duplicate** the one-line format string at two call sites. Inspect
  tests pin both formats, so drift would be caught immediately.
- **Public core helper** `pub fn[T : Renderable] format_proj_label(...)`.
  Adds API surface for trivial gain.

**Decision: duplicate.** One line × two call sites < the API-surface tax
of a public helper.

### CSS class as free function (`term_css_class`)

CSS classes are a UI styling concern, not a debug-rendering concern. A
free function `term_css_class : Term -> String` in `lang/lambda/proj/`
keeps the mapping where the kind variants are defined and gets
exhaustiveness checking. Rejected `KindLabel` trait because views are
already language-specific — Pattern anti-check: "forcing trait where a
function suffices" applies.

`term_css_class` mapping (exhaustive over 11 Term variants):

```
Int(_)        → "int"
Var(_)        → "var"
Lam(_, _)     → "lambda"
App(_, _)     → "app"
Bop(_, _, _)  → "binop"
If(_, _, _)   → "if"
Module(_, _)  → "module"
Unit          → "unit"
Unbound(_)    → "unbound"
Error(_)      → "error"
Hole(_)       → "hole"
```

Note `"let"` (the old `kind_of` output for `let`-prefix labels) does not
appear — there's no `Let` Term variant. Module bindings projection
renders as label `"module [foo, bar]"`, which is why `kind_of` gave
`"let"` for the parse-prefix `"let "` it observed. `term_css_class`
correctly produces `"module"` for `Module(...)` instead.

Of the produced classes, `editor.css` currently styles `int`, `var`,
`lambda`, `app`, `binop`, `if`, `module`, `error`. Missing: `unit`,
`unbound`, `hole` — added in step 7 below.

**Data-axis closure.** This exhaustive match is data-axis-closed by
design — Term is a regular `pub(all) enum`, not an `extenum`. If lambda
ever migrates Term to `extenum` (v0.9.2) to admit plugin-defined
variants, every exhaustive Term-match in canopy + loom would need a
wildcard arm and gain a runtime "unknown variant" failure mode. The
affected Term sites are `term_css_class` (this plan), the existing
`Renderable::kind_tag` / `Renderable::label` / `Renderable::placeholder` /
`Renderable::unparse` impls, `TreeNode::same_kind`, the existing
`Pretty for Term`, and lambda's evaluator / typecheck / projection
builders. (The Show impls *added by this plan* — `Show for ProjNode`,
`Show for InteractiveTreeNode`, etc. — do not match on Term directly
and would not need wildcard arms.) Today the closed enum is preferred
because compile-time exhaustiveness is the safety net for "the
framework handles every variant correctly." The expression-problem
tradeoff is consciously made here: structure-observable closed enum
over extenum's plugin-axis openness.

### Inspector CSS class is dropped (not added)

The inspector chip today is rendered as
`span(class="inspector-value kind-\{kind}", ...)`. `editor.css` has no
`.inspector-value.kind-*` selectors, so the `kind-*` class is inert. The
plan drops it (just `class="inspector-value"`). Reduces noise in the
DOM. If inspector-level kind theming is wanted later, add the selectors
then — but adding them now is feature creep.

### Escaping rule (expanded)

`SpanEdit.inserted` and `GenericTreeOp::CommitEdit.new_value` carry
user-supplied text. The display delimiters `«»` would render
ambiguously if the payload contains the same characters. Control chars
would render invisibly or break the line.

Implementation: `priv fn escape_for_show(s : String) -> String` in
`core/types.mbt`, shared by `SpanEdit::output` and `GenericTreeOp::output`.

Rules (in order of precedence — first match wins):

| Char | Output |
|------|--------|
| `\`  | `\\`   |
| `«`  | `\«`   |
| `»`  | `\»`   |
| `\n` (U+000A) | `\n` |
| `\r` (U+000D) | `\r` |
| `\t` (U+0009) | `\t` |
| Other C0 control (U+0000..U+001F) OR DEL (U+007F) | `\u{XX}` (lowercase hex, ≥2 digits) |
| C1 control (U+0080..U+009F) — includes NEL U+0085 | `\u{XX}` |
| Line/paragraph separator (U+2028, U+2029) | `\u{2028}` / `\u{2029}` |
| Other | unchanged |

Rationale for C1 + U+2028/U+2029: these render invisibly or as line
breaks in many viewers, which would split a single-line `«…»` payload
across lines and break the debug-trace alignment. Other Unicode
(surrogate pairs, non-BMP, emoji, RTL marks) passes through unchanged
— this is a display escape, not a wire-format escape.

### `node.label` stays primary for outline rows

`Renderable::label` is the curated short-form display per variant
(`"App"`, `"λx"`, `"if"`, `"module [foo, bar]"`). It's what outline rows
already show via `node.label`. `Show for InteractiveTreeNode` returning
`"#9 App [25..47]"` is debug material — useful for inspector debug
output and logs, not for the navigation tree.

Outline rows are unchanged. Show is added for debug/logging consumers
and the inspector chip text.

## Steps

1. **`Show for SpanEdit` + escape helper.** Add
   `priv fn escape_for_show(s : String) -> String` in `core/types.mbt`
   covering the rules above. Format: `"@\{start} -\{delete_len}
   +«\{escape_for_show(inserted)}»"`. Inspect tests: pure insert
   (`delete_len=0`), pure delete (`inserted=""`), replace, inserted
   containing `»` and `\\`, inserted with `\n`, inserted with NUL
   (U+0000), inserted with DEL (U+007F), inserted with NEL (U+0085)
   or another C1 control, inserted with U+2028 (LINE SEPARATOR).

2. **`Show for GenericTreeOp`** — verb-first, positional. 14 variants:
   - `Select(NodeId(n))` → `"Select(#\{n})"`
   - `SelectRange(NodeId(a), NodeId(b))` → `"SelectRange(#\{a}..#\{b})"`
   - `StartEdit(NodeId(n))` → `"StartEdit(#\{n})"`
   - `CommitEdit(NodeId(n), v)` →
     `"CommitEdit(#\{n} «\{escape_for_show(v)}»)"`
   - `CancelEdit` → `"CancelEdit"`
   - `Delete(NodeId(n))` → `"Delete(#\{n})"`
   - `StructuralEdit(NodeId(n))` → `"StructuralEdit(#\{n})"`
   - `StructuralEditKeepSelected(NodeId(n))` →
     `"StructuralEditKeepSelected(#\{n})"`
   - `InsertChild(NodeId(p), i)` → `"InsertChild(#\{p}, \{i})"`
   - `StartDrag(NodeId(n))` → `"StartDrag(#\{n})"`
   - `DragOver(NodeId(t), pos)` → `"DragOver(#\{t}, \{pos})"`
   - `Drop(NodeId(s), NodeId(t), pos)` → `"Drop(#\{s}→#\{t} \{pos})"`
   - `Collapse(NodeId(n))` → `"Collapse(#\{n})"`
   - `Expand(NodeId(n))` → `"Expand(#\{n})"`

   Render `DropPosition` variants as `"Before"` / `"After"` / `"Inside"`.
   Inspect tests for every variant (exhaustive `match` pins it).

3. **`Show for ProjNode[T : @loomcore.Renderable]`** —
   `"#\{self.node_id} \{Renderable::kind_tag(self.kind)} [\{self.start}..\{self.end}]"`.
   Children are not rendered. **Bound constraint swap:** `T : Debug` →
   `T : @loomcore.Renderable`. Inspect test with `ProjNode[Term]` and a
   synthetic minimal-kind type used only in the test (with a manual
   `Renderable` impl). Verify the test helpers in
   `core/proj_zipper_wbtest.mbt` and `core/source_map_wbtest.mbt` (which
   use `ProjNode[Int]`) still compile — they shouldn't call `to_string`
   on the node; if any does, switch to `@debug.to_string(...)`.

4. **`Show for InteractiveTreeNode[T : @loomcore.Renderable]`** in
   `projection/`. Format string is the *same* as ProjNode's
   (`"#<n> <kind_tag> [<start>..<end>]"`), but the field paths differ:
   `InteractiveTreeNode` has `id : NodeId` and `text_range : Range`,
   whereas `ProjNode` has `node_id : Int` and inline `start`/`end : Int`.
   Destructure explicitly:

   ```moonbit
   pub impl[T : @loomcore.Renderable] Show for InteractiveTreeNode[T]
     with output(self, logger) {
       let NodeId(n) = self.id
       let tag = @loomcore.Renderable::kind_tag(self.kind)
       logger.write_string(
         "#\{n} \{tag} [\{self.text_range.start}..\{self.text_range.end}]"
       )
     }
   ```

   Do **not** call `self.id.to_string()` — `Show for NodeId` is still
   the @debug.to_string delegate (`"NodeId(11)"`), which would produce
   the wrong output. Bound: `T : @loomcore.Renderable`. Inspect test
   with a Term-instantiated node.

5. **`moon info` and `.mbti` diff** for `core/`, `projection/`. Confirm
   the only changes are the bound updates and new exports
   ([[feedback_api_diff_check]]).

6. **Add `term_css_class : Term -> String` in `lang/lambda/proj/`.**
   Exhaustive match over the 11 Term variants per the mapping in Design
   Notes. Inspect tests per variant. `moon info` on `lang/lambda/proj/`;
   diff `.mbti` to verify only the new export appears.

7. **Add missing CSS selectors** in `examples/ideal/web/styles/editor.css`:
   `.tree-row.kind-unit .tree-accent`,
   `.tree-row.kind-unbound .tree-accent`,
   `.tree-row.kind-hole .tree-accent`. Accent color: `var(--canopy-muted)`
   for all three (refine in browser smoke). No `.inspector-value.kind-*`
   selectors — the inspector CSS class is dropped in step 10.

8. **Import wiring.** Confirmed today `examples/ideal/main/moon.pkg`
   imports `@canopy_core`, `@proj`, `@editor`, `@lambda`, `@lambda_edits`,
   `@ast`, but NOT `@loomcore` or `@lambda_proj`. Add:

   ```
   "dowdiness/loom/core" @loomcore,
   "dowdiness/canopy/lang/lambda/proj" @lambda_proj,
   ```

   `term_css_class` goes in `lang/lambda/proj/` and is imported directly
   as `@lambda_proj.term_css_class`. **Do not re-export from
   `lang/lambda/top.mbt`** — that facade is deliberately narrow per its
   leading doc-comment ("Only re-exports symbols that are actually
   consumed today"; adding `term_css_class` would re-expand the surface
   the §7 audit + earlier housekeeping deliberately trimmed).

   Rerun `moon check` on `examples/ideal` after the import addition;
   verify no other workspace member needs the import (none should — the
   function is only consumed by view_outline + view_inspector).

9. **Migrate `view_outline.mbt`.** Replace `kind_of(node.label)` (line 70)
   with `term_css_class(node.kind)`. Tree-row body stays `node.label` — no
   change. Delete the `kind_of` function.

10. **Migrate `view_inspector.mbt`.** Replace `let kind = kind_of(node.label)`
    (line 80) with `let chip = @loomcore.Renderable::kind_tag(node.kind)`.
    Use `chip` in `[text(chip)]`. Change the span class to just
    `"inspector-value"` (drop the `kind-\{chip}` segment — see Design
    Notes).

11. **Snapshot audit.** Workspace-wide `moon test`. Before running
    `--update`, enumerate flips:
    `grep -rn 'inspect.*\b\(SpanEdit\|GenericTreeOp\|ProjNode\|InteractiveTreeNode\)\b' core/ projection/ examples/ideal/main/ lang/`.
    Reject flips in tests that intentionally captured the old Debug form
    (replace with explicit `@debug.to_string(value)`). Only after audit:
    `moon test --update`.

12. **`moon fmt && moon info`.** Diff `*.mbti` files across all touched
    packages.

13. **Browser smoke test.** `cd examples/web && npm run dev`; load the
    lambda editor; verify:
    - Outline tree row text is unchanged (still uses `node.label`).
    - Outline tree row accent colors match — including new
      `kind-unit`/`kind-unbound`/`kind-hole` if any variants render.
    - Inspector chip shows `"App"`/`"Lam"`/`"If"`/etc. (the
      `Renderable::kind_tag` output), not the parsed-label form (which
      collapsed `Plus`/`Minus` → `"binop"`).
    - **Visible behavior change for `Bop` nodes:** inspector chip text
      goes `"binop"` → `"Bop"`. Surface in the PR description.

## Acceptance Criteria

- [ ] `SpanEdit { start=25, delete_len=3, inserted="add" }.to_string() ==
  "@25 -3 +«add»"`.
- [ ] `SpanEdit { ..., inserted="a»b" }.to_string()` escapes the `»`
  per the table.
- [ ] `SpanEdit { ..., inserted="a\x00b" }.to_string()` renders as
  `"@... -... +«a\u{00}b»"`.
- [ ] `SpanEdit { ..., inserted="a\u{2028}b" }.to_string()` renders as
  `"@... -... +«a\u{2028}b»"` (line-separator escaped, not passed
  through as a literal line break).
- [ ] `GenericTreeOp::Drop(source=NodeId(11), target=NodeId(12),
  position=After).to_string() == "Drop(#11→#12 After)"`.
- [ ] `CommitEdit(NodeId(3), "x»y")` renders as
  `"CommitEdit(#3 «x\»y»)"`.
- [ ] `ProjNode` with `node_id=9`, kind `App`, range `[25, 47]` renders
  as `"#9 App [25..47]"`. Children not included.
- [ ] `InteractiveTreeNode` with same fields renders identically.
- [ ] `Show for NodeId` is unchanged; `node_id.to_string()` still emits
  `"NodeId(11)"` at all existing call sites.
- [ ] `view_outline::kind_of` is deleted; no callers
  (`moon ide find-references` empty).
- [ ] Outline tree-row body content is `node.label` (unchanged).
- [ ] Outline tree-row CSS class derives from `term_css_class(node.kind)`.
- [ ] Inspector chip text comes from
  `@loomcore.Renderable::kind_tag(node.kind)`; the inert
  `kind-\{kind}` CSS class is dropped.
- [ ] `editor.css` has selectors for every CSS class `term_css_class`
  can return.
- [ ] `core/`, `projection/`, `lang/lambda/proj/` `.mbti` diff shows only
  the intended bound updates + new exports.
- [ ] `moon test` workspace-wide passes; snapshot updates audited
  (not blanket `--update`).
- [ ] Browser smoke confirms outline accents + inspector chip text.

## Validation

```bash
# Per-package, in order
moon check
moon test
# Audit before --update:
grep -rn 'inspect.*\b\(SpanEdit\|GenericTreeOp\|ProjNode\|InteractiveTreeNode\)\b' \
  core/ projection/ examples/ideal/main/ lang/
moon test --update    # only after auditing what's flipping
moon info
git diff core/pkg.generated.mbti projection/pkg.generated.mbti \
         lang/lambda/proj/pkg.generated.mbti

# Workspace fan-out (per CLAUDE.md "Test & Build")
cd examples/ideal && moon test
cd lib/semantic && moon test
moon fmt

# Verify NodeId.to_string unchanged at production sites
grep -rn 'node_id\.to_string\|NodeId.*\.to_string' lang/ projection/ editor/ core/

# Browser smoke
cd examples/web && npm run dev
```

## Risks

- **Snapshot churn.** Steps 1-4 change rendering of four commonly
  inspected types. The audit step (11) catches accidental flips. Tests
  that *intentionally* captured Debug output get explicit
  `@debug.to_string(value)` replacements.
- **Constraint swap, not widening.** `T : Debug` → `T : Renderable`. If
  any out-of-tree consumer has only `Debug`, it loses `Show for ProjNode[T]`.
  In-tree: production T's (Term, JsonValue, markdown Block/Inline) all
  implement Renderable. Test helpers with `ProjNode[Int]` exist in
  `core/proj_zipper_wbtest.mbt:7` and `core/source_map_wbtest.mbt:46`;
  step 3 verifies they don't trip the bound change.
- **Inspector chip text change (`"binop"` → `"Bop"`).** Inspector chip
  visibly changes for `Bop` nodes. Improvement, but surface in PR.
- **CSS new selectors.** Adding `kind-unit`/`kind-hole`/`kind-unbound`
  to editor.css is small but visible. Pick accent colors during browser
  smoke (step 13) and screenshot for the PR description.
- **Inspector CSS class dropped.** No matching selectors exist today
  (selector audit confirmed), so the change is inert. Re-add if the
  inspector starts needing kind-specific styling.

## Notes

- Recommended PR shape: one PR for steps 1-5 (`core/`+`projection/`
  Show impls + tests + `.mbti` diff, no view or CSS changes) and a
  second PR for steps 6-13 (lambda `term_css_class` + CSS additions +
  import wiring + view migration + browser smoke). The first is purely
  additive at the framework layer; the second is where visual changes
  land.
- Optional third cut: `term_css_class` (step 6) + CSS (step 7) +
  import wiring (step 8) could split from the view migration (steps
  9-10) for an even smaller review surface. Probably overkill — the
  view migration is mechanical once the helper exists.
- Codex pre-implementation review per global rules: validate the
  format strings + escaping rule before writing tests. Easiest catches:
  punctuation (`→` U+2192, `«»` U+00AB/00BB), `Drop` argument order,
  control-char escape boundary (< 0x20, == 0x7F).
- After merge: mark §15 first item done in `docs/TODO.md`; update
  [[project_inspector_traceability_workstream]] (deliverable 1 of 4
  shipped); reference this plan from Tasks 2-3 when they're created.
- Tasks 2-3 (the broader Renderable/Pretty integration) are not
  blocked by this PR. They're independent improvements that share a
  direction.
- Related memories: [[feedback_section7_audit_methodology]] (this is
  the payoff for keeping the stubs), [[feedback_algorithm_process]]
  (Codex validates the design first), [[feedback_test_count_delta]]
  (verify new inspect tests actually run), [[feedback_api_diff_check]]
  (audit `.mbti` diffs).
