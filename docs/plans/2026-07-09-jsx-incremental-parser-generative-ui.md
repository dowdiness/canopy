# JSX Incremental Parser for Generative UI

## Why

Canopy + loom already provide an incremental, error-tolerant CST parser and a
reactive projection pipeline (`Grammar → CST → CstFold → AST → ProjNode[T] →
ViewNode`) that reconciles across edits without losing node identity. That is
exactly the shape needed for a generative-UI surface: an LLM streams JSX-like
markup token by token, and the UI should grow incrementally from the
already-parsed prefix without remounting components that are already
rendered.

This plan builds that capability in three repo-scoped phases and stops at a
read-only proof of the reconciliation property — bidirectional editing and
real component mounting are explicitly deferred (Phase 3).

## Scope

**In (Phase 0 + 1, repo: `loom` submodule):**
- `loom/examples/html/` housekeeping (prerequisite — JSX reuses its
  tag/lexer patterns and, once Task 0.2 settles which mode-switching
  mechanism actually works there, JSX's `{...}` embedded-expression mode
  switch reuses whichever one that turns out to be — not necessarily
  `set_lex_mode`; see Current State)
- `loom/examples/jsx/` — new grammar, lexer, CST parser, AST, trait impls

**In (Phase 2, repo: `canopy` main):**
- `lang/jsx/proj/` — CST → `ProjNode[JsxAst]` projection, token spans, memo
  builder only (ADDING_A_LANGUAGE.md Phase 2 steps 2-4)
- A wbtest that simulates chunked streaming input and asserts `NodeId`
  stability across chunks (the existence proof for the generative-UI value
  proposition)

**Out (this plan does not implement, see Phase 3 stub):**
- Parsing the contents of `{...}` embedded expressions as JavaScript —
  they are opaque raw spans in every phase this plan covers
- Bidirectional editing (`lang/jsx/edits/`, `lang/jsx/companion/`,
  ADDING_A_LANGUAGE.md steps 5-6)
- FFI/web export, DOM mounting, component registry
- HTML5-spec-correct optional-closing-tag / implied-element behavior (JSX
  requires explicit close tags, so this is moot for JSX itself, but do not
  backport it into the html example as part of this plan)

## Current State (verified 2026-07-09)

- `docs/development/ADDING_A_LANGUAGE.md` is the canonical 7-step guide.
  Markdown is the reference implementation; do not copy Lambda's pattern
  (predates CstFold, has a custom edit bridge).
- `loom/examples/html/` is a simplified HTML tree builder (730 non-test
  lines: 19% loomgen-generated, 62% hand-written native lexer/parser). It is
  a workspace member of `loom/moon.work` but **not** of canopy's root
  `moon.work` — it only builds/tests from inside the `loom/` submodule
  checkout, not from canopy root.
- `loom/examples/html/README.mbt.md` "Known Issues": `<script>`/`<style>`
  content is lexed as `Text` instead of `RawText`, so the parser's
  `RawTextLeaf` branch (`cst_parser.mbt:67-74`) is dead code. Tracked as
  loom **issue #626** (OPEN). The fix requires parser-driven lex-mode
  switching, tracked as the M19 capstone, loom **issue #609** (OPEN).
- The infrastructure #609 depends on already shipped: loom **issue #532**
  (CLOSED) added `ParserContext::lex_mode()` / `ParserContext::set_lex_mode(Int)`
  to `loom/loom/core/parser_context_access.mbt:283-297`. The accessors are
  real and present today — confirmed by direct read:
  ```moonbit
  pub fn[T, K] ParserContext::lex_mode(self : ParserContext[T, K]) -> Int
  pub fn[T, K] ParserContext::set_lex_mode(self : ParserContext[T, K], mode : Int) -> Unit
  ```
  **However — verified by a second review pass, 2026-07-09 — the field they
  read/write has NO consumer.** `grep -rn lex_mode loom/loom/*.mbt`
  (excluding tests) hits only: the struct field declaration
  (`parser.mbt:133,146`), the getter/setter (`parser_context_access.mbt`),
  and checkpoint save/restore (`parser_events.mbt:182,203`, so it survives
  backtracking, nothing more). `Grammar.lex : (String) -> @core.LexResult[T]`
  (`loom/loom/grammar.mbt:13`) is a **whole-input batch function that never
  receives a `ParserContext`** — there is no feedback path from
  `set_lex_mode` back into lexing anywhere in `pipeline/` or `incremental/`.
  `parser.mbt:131`'s own comment ("switch the lexer to a different mode
  mid-parse") is aspirational, not implemented. **Do not treat
  `set_lex_mode` as a working mechanism** — using it today only changes what
  `ctx.lex_mode()` returns; it does not change what token the lexer produces
  next. Building that feedback path is the actual scope of #609 (OPEN), not
  a detail Phase 0/1 can casually wire up as a side effect of an example fix.
  By contrast, `ModeLexer[T, M]` (`loom/loom/core/mode_lexer.mbt`) — used
  today by `examples/markdown` — threads mode token-to-token as a real
  lexer-level state machine, and `tokenize_with_modes` / `ModeRelexState`
  give it incremental re-lex support already. It is the mechanism that
  actually works today for "switch lexing behavior based on structural
  markers." Task 1.1 below is the gate for choosing between these; do not
  assume the answer.
- `ParserContext::current_node_kind()` (same file, line 343) returns the
  `SyntaxKind` of the most recently opened, unclosed node — useful for
  "am I inside an embedded expression / inside a raw-text element" checks
  without a separate stack.
- loom **issue #646** (CLOSED, but root cause explicitly unresolved per its
  own body): `moon test --target native` for `examples/html` hangs at 100%
  CPU in bundled `tcc`. PR #645 scoped CI's `test-modules` job to
  `moon test -p <module>` as a workaround, so `examples/html` (plus `css`,
  `graph-dsl`, `moonbit`) are **not in loom's CI matrix**. The underlying
  hang was never fixed — only worked around.
- `loom/examples/markdown/src/` demonstrates `ModeLexer[T, M]`
  (`loom/loom/core/mode_lexer.mbt`) — lexer-side mode tracking via
  `tokenize_with_modes`, where the next mode is a pure function of lexer
  state, with `ModeRelexState` giving it incremental re-lex support. This is
  the mechanism Task 1.1 defaults to for JSX's embedded-expression switch,
  since (per the `set_lex_mode` finding above) it is the one that actually
  works today — `set_lex_mode` is a fallback branch, not the default.
- Canopy's `lang/markdown/{proj,edits,companion}/` is the reference package
  layout for Phase 2; do not model `lang/jsx/` on `lang/lambda/` (documented
  legacy pattern, ADDING_A_LANGUAGE.md line 9-13).

## Desired State

1. `loom/examples/html/` builds and tests cleanly from a scoped command, is
   back in loom's CI matrix, and `<script>`/`<style>` content round-trips as
   `RawTextLeaf` — settling, with evidence rather than assumption, which
   mode-switching mechanism actually works end-to-end before JSX depends on
   it.
2. `loom/examples/jsx/` parses a fixed grammar (elements, fragments,
   attributes, text children, `{...}` opaque embedded-expression spans) into
   an error-tolerant CST, with a real AST (`derive(Eq, Debug)`) and
   `TreeNode`/`Renderable` trait impls, following the Markdown reference
   shape.
3. `lang/jsx/proj/` in canopy converts that CST into a reconciling
   `ProjNode[JsxAst]` tree. A wbtest feeds the parser JSX text in
   monotonically growing chunks (simulating an LLM token stream) and asserts
   that `NodeId`s already assigned to fully-parsed ancestor elements do not
   change as later siblings/descendants are appended.
4. Everything past `ProjNode[JsxAst]` (real rendering, editing) is
   explicitly out of scope — Phase 3 lists it as a stub for future planning,
   not a task list.

---

## Phase 0 — `loom/examples/html` housekeeping (repo: loom submodule)

**Why this is a prerequisite, not parallel work:** Phase 1's hardest design
piece (embedded-expression mode switching) needs the *same mechanism
decision* #609 needs for `<script>`/`<style>` — whichever mechanism Task
0.2 actually gets working (see its Step 0 below; `set_lex_mode` is **not**
a working mechanism today, see Current State), Phase 1 should reuse rather
than re-debug from scratch. Sequencing Task 0.2 before Phase 1 only pays off
if Task 0.2 lands on a mechanism that genuinely transfers to JSX's `{...}`
case — if it lands on html-specific lexer-side detection that doesn't
generalize, say so explicitly in Task 0.2's Step 5 write-up rather than
letting Phase 1 assume it inherited something reusable. Phase 0 also gets
`examples/html` back into CI so Phase 1's sibling `examples/jsx` doesn't
inherit an untested-in-CI neighbor's blind spots — that part of the
rationale holds regardless of which mechanism Task 0.2 picks.

**Repo boundary:** all commits in this phase happen inside the `loom/`
submodule checkout and its own git history. Push to `loom`'s remote
(`github.com/dowdiness/loom`) and get a loom-side PR merged **before**
touching canopy's submodule pointer — per canopy `CLAUDE.md` Submodule
Workflow. Do not bump the canopy `loom` pointer until Phase 0 is merged
upstream in loom.

### Task 0.1: Reproduce and minimize the tcc hang (issue #646)

This is an investigation task, not a scripted fix — the root cause is
unconfirmed (toolchain-side `tcc` bug vs. project-side). Time-box it.

- [ ] **Step 1:** From `loom/` submodule root, reproduce:
  ```bash
  cd loom/examples/html
  NEW_MOON_MOD=0 moon test --target native
  ```
  Confirm it still hangs on the current toolchain pin (loom `CLAUDE.md` /
  `.github/workflows/ci.yml` for the pinned MoonBit version — do not assume
  the 2026-06-29 repro toolchain in #646 is still current; re-check the pin
  first).
- [ ] **Step 2:** Minimize — does `moon test -p dowdiness/html --target native`
  from `examples/html/` alone still hang, or only full-workspace fan-out
  (`cd loom && moon test`)? Record which.
- [ ] **Step 3:** Per #646's own suggested investigation: inspect why the
  html blackbox test driver's `tcc` rspfile includes `README.mbt.md:0-5`
  (the doc-test block) alongside `parser_test.mbt`/`lexer_test.mbt`. If the
  doc-test compilation is the hang trigger, try isolating/removing it from
  the native blackbox build and re-test.
- [ ] **Step 4 (branch on result):**
  - If reproducible and root-cause-able on the project side within ~1 hour
    of investigation → fix it, re-add `examples/html` to loom's
    `test-modules` CI matrix (`.github/workflows/ci.yml` in loom), verify
    green.
  - If it reproduces on `wasm-gc` target too, or looks toolchain-internal
    (tcc spinning with tiny constant RSS, no forward progress) → do not keep
    debugging inside this plan. File/update the upstream MoonBit issue,
    leave the CI workaround (`-p <module>` scoping) in place, and continue
    to Task 0.2 — the hang blocks CI coverage, not correctness, so it must
    not block Phase 1.
- [ ] **Step 5:** Whichever branch: leave a one-paragraph note in this plan's
  Notes section (or a loom-side issue comment on #646) recording which
  branch was taken and why, so the next agent doesn't re-investigate from
  scratch.

### Task 0.2: Fix RawText emission for `<script>`/`<style>` (issue #626)

Two options are already named in #626 itself. **Design gate, not a coin
flip** — and per Current State, `set_lex_mode` (Option B as originally
scoped) is **not implementable as a mid-parse lexer switch today**: the
lexer is invoked as a whole-input batch function with no feedback path from
`ParserContext`. Do not start Option B's implementation steps until Step 0
below is answered.

- [ ] **Step 0 (architecture check, do this first):** Read
  `loom/examples/html/grammar.mbt` and `cst_parser.mbt` and confirm how
  lexing and parsing are actually sequenced for this example: is the whole
  input tokenized once via `Grammar.lex` before `cst_parser.mbt` ever runs
  (this appears to be the case given `Grammar.lex : (String) -> LexResult[T]`
  takes no `ParserContext`), or is there an interleaved/incremental path
  this example uses instead? Then choose:
  - If lexing is a single batch pass (expected): use **Option A**
    (lexer-side detection) — teach `lexer.mbt` to recognize the literal
    `<script`/`<style` open-tag text during its own scan and switch itself
    into a raw-text scanning mode until the matching literal close tag,
    with no `ParserContext` involvement. This is achievable without any
    loom-core changes.
  - Only reach for `ParserContext::set_lex_mode` if Step 0 finds a real
    interleaved lex/parse path that already threads `ParserContext` into
    lexing — and if so, note that this is likely the first real consumer
    of #532's accessors, since none exists today.
  - Do **not** attempt to build the missing lex↔parse feedback path
    (i.e., implement #609's actual infrastructure) as a side effect of this
    task. If Step 0 shows `set_lex_mode` requires that infrastructure and
    Option A alone doesn't fit, stop and flag it — #609 is a separate,
    larger scoped task, not something to absorb silently into a "fix one
    example" task.

**Recommendation, pending Step 0: Option A** (lexer-side detection in
`lexer.mbt`), since the batch-lexing architecture is the expected finding.
The steps below assume Option A; adapt them if Step 0 finds otherwise.

- [ ] **Step 1:** Write a failing test first, in
  `loom/examples/html/parser_test.mbt`:
  ```moonbit
  ///|
  test "script content is raw text" {
    let (tree, diagnostics) = html_grammar.parse_cst(
      "<script>var x = 1;</script>",
    )
    inspect(diagnostics.length(), content="0")
    // assert the script body is under a RawTextLeaf node, not TextLeaf —
    // exact assertion shape depends on how @seam.SyntaxNode exposes child
    // kinds; inspect the actual tree shape via `moon ide` before writing
    // the final assertion, don't guess the API.
  }
  ```
- [ ] **Step 2:** Run it, confirm it fails (diagnostics.length() != 0, or the
  node kind assertion fails) — `moon test -p dowdiness/html -f parser_test.mbt`
  from `loom/examples/html/` (do NOT run unscoped `moon test` here — see
  Task 0.1).
- [ ] **Step 3 (Option A path — expected):** In `loom/examples/html/lexer.mbt`,
  when the tokenizer's own scan recognizes an `OpenTag(String)` whose tag
  name is `script` or `style` (case-insensitively — HTML tag/element names
  are ASCII case-insensitive per spec, do not gate on exact-case `<script`),
  switch the lexer's own internal scanning state so subsequent characters
  are consumed as raw text and emitted as a single `@token.RawText` token,
  scanning until it finds the matching close-tag sequence
  (`</script>`/`</style>`, also case-insensitive) rather than re-entering
  normal tag-scanning rules mid-content. This is self-contained within
  `lexer.mbt` — no `ParserContext` involvement, no `cst_parser.mbt` change
  needed beyond the existing `RawTextLeaf` branch already having somewhere
  to attach the token.
- [ ] **Step 3-alt (only if Step 0 found an interleaved lex/parse path):**
  In `cst_parser.mbt`, call `ctx.set_lex_mode(RAW_TEXT_MODE)` after emitting
  the `<script>`/`<style>` open-tag node and `ctx.set_lex_mode(0)` at the
  matching close tag; then wire the interleaved lexer (found in Step 0) to
  consult `ctx.lex_mode()` before producing each token. Do not attempt this
  branch without first confirming in Step 0 that such an interleaved path
  exists — building one from scratch is #609's scope, not this task's.
- [ ] **Step 4:** Whichever path Step 3 took, confirm `@token.RawText` (not
  `@token.Text`) is emitted for script/style content, and that the emitted
  token spans exactly the content between the open and close tags (excluding
  the tags themselves).
- [ ] **Step 5:** Run the test from Step 1, confirm it passes.
- [ ] **Step 6:** Run the full scoped suite:
  `moon test -p dowdiness/html` and `moon check -p dowdiness/html --deny-warn`
  from `loom/examples/html/`.
- [ ] **Step 7:** `moon info && moon fmt` (loom root), check
  `git diff -- '*.mbti'` for unintended surface changes.
- [ ] **Step 8:** Commit in the loom submodule, push to loom's remote, open
  a loom-side PR referencing #626 (and #609 if this closes the M19
  capstone's core exercise).

### Acceptance Criteria (Phase 0)

- [ ] `moon test -p dowdiness/html` passes from `loom/examples/html/`
- [ ] `<script>`/`<style>` content produces `RawTextLeaf` nodes, 0
      diagnostics, per the Step 1 test
- [ ] Either #646 is fixed and `examples/html` is back in loom's CI
      `test-modules` matrix, OR the investigation branch is documented (Task
      0.1 Step 5) and the CI workaround remains — both are acceptable exit
      states, silence is not
- [ ] `git diff -- '*.mbti'` reviewed for unintended API changes
- [ ] Loom-side PR merged and pushed to loom's own remote

### Validation (Phase 0)

```bash
cd loom/examples/html
NEW_MOON_MOD=0 moon check -p dowdiness/html --deny-warn
NEW_MOON_MOD=0 moon test -p dowdiness/html
cd ../..   # loom root
moon info && moon fmt
git diff -- '*.mbti'
```

---

## Phase 1 — `loom/examples/jsx` grammar (repo: loom submodule)

**Repo boundary:** same as Phase 0 — commits and PR land in loom's own repo
first.

### Task 1.1 — Design gate (prose only, no code)

Per this project's Algorithm Implementation Process: design in prose, get it
validated (Codex, or a fresh reviewer agent if Codex is unavailable this
session), *then* write tests, *then* implement. Do not skip to code for the
two items below — they are the actual novel algorithm work in this whole
plan; everything else is mechanical application of the html/markdown
patterns.

- [ ] **Step 1:** Write a prose design doc (append to this plan's Notes, or a
  short standalone note) answering, for the **embedded-expression mode
  switch**:
  - **Mechanism choice first, not assumed:** per Current State,
    `ParserContext::set_lex_mode` has no working lex-side consumer in loom
    today — using it requires building the interleaved lex/parse feedback
    path that is #609's actual open scope. Default to **`ModeLexer[T, M]`**
    (`loom/loom/core/mode_lexer.mbt`) instead — it is the mechanism
    `examples/markdown` already uses successfully, and
    `tokenize_with_modes`/`ModeRelexState` give it incremental re-lex
    support for free, which the streaming use case needs regardless. Only
    choose `set_lex_mode` if Task 0.2's Step 0 found real interleaved
    lex/parse wiring reusable here — state explicitly which mechanism was
    chosen and why, do not leave it implicit.
  - Exact trigger: lexer (in `ModeLexer`'s mode-threading model) sees `{`
    while its current mode is "JSX children" or "JSX attribute value" —
    transitions to a `JsExprRaw` mode for subsequent tokens.
  - Exact exit: matching `}` at depth 0 relative to the `{` that opened the
    expression — transitions back to the mode that was active before entry
    (children vs. attribute-value, since these differ).
  - Depth tracking: is depth counted as one integer folded into the mode
    value itself (e.g. `JsExprRaw(depth)` if `M` is an enum/struct, which
    `ModeLexer[T, M]` supports since `M` is a free type parameter), or
    tracked via a side counter the grammar's `fold_node` reconstructs from
    the token stream? State which, and why.
  - String-literal awareness: JS strings/template literals inside the
    expression can contain unbalanced `{`/`}` (e.g. `{"a}b"}`,
    `` {`${x}`} ``). State exactly how the design avoids miscounting depth
    inside a string — e.g. the mode machine recognizes `"`, `'`, `` ` ``
    and transitions to a nested "inside string" sub-mode until the matching
    quote (respecting `\` escapes), before resuming brace-depth counting.
    Do not assume this is out of scope — single/double-quoted string
    literals inside `{}` are common in real JSX and getting this wrong
    produces silently truncated expression spans.
  - **Nested JSX inside `{...}`** (e.g. `{cond ? <a/> : <b/>}`): state
    explicitly that under the opaque-span design, this stays one opaque
    blob — the parser does not recurse into it. Note the consequence for
    the plan's own value proposition: conditional-rendering-heavy LLM
    output (a common real-world JSX pattern) gets no incremental visible
    growth *inside* the expression, only at its boundaries. This is an
    acceptable Phase 1 limitation, but it must be a stated limitation, not
    a silent gap discovered later.
  - **Growing opaque `ExprSpan` identity:** as an LLM streams `{fo` → `{foo`
    → `{foo}`, is this a single `ProjNode` leaf whose *content* changes
    (text-mutation reconciliation) or does each partial token re-parse
    produce a structurally different node? State which — this is a
    different reconciliation case from Task 2.4's appended-sibling test and
    needs its own answer, since `{...}` content-growth is likely the single
    most common streaming event in real LLM-JSX output (attribute/text
    values grow character-by-character far more often than new sibling
    elements appear).
- [ ] **Step 2:** Write a prose design doc for **error recovery on a
  streaming (monotonically-growing) prefix of JSX text**, enumerating at
  least these cases and what CST/diagnostic shape each produces:
  1. Fully closed element tree (baseline, not interesting).
  2. One or more open elements with no matching close tag yet
     (`<div><span>text` — stream just hasn't sent `</span></div>` yet).
     State explicitly: does the parser emit an "unclosed element" node that
     still contains its already-seen children (so the projection layer can
     render them), or does it emit an error node that discards children?
     The projection layer's read-only rendering (Phase 2) requires the
     former — an unclosed element must still expose its parsed-so-far
     children, or the whole generative-UI value proposition (incremental
     visible growth) breaks. State this as a hard requirement on the CST
     shape, not an implementation detail to decide later.
  3. A truncated tag itself, cut mid-token (`<div cla`, or `<di`) — the
     tag name or an attribute name/value is incomplete. State what token
     the lexer emits at EOF for a truncated token (an error token? a
     best-effort partial token?) and what the parser does with it (defer
     to `too_many_errors`/recovery-loop patterns already in
     `parser_context_access.mbt`, or a JSX-specific EOF-recovery rule).
  4. A truncated embedded expression (`{foo.bar(` with the stream cut
     mid-expression, no matching `}` yet). Since the expression body is
     opaque, state whether the whole `{...}` span becomes "pending" (no
     node emitted until `}` arrives) or a partial-content node is emitted
     eagerly. Prefer eager partial emission if it doesn't require guessing
     — consistent with case 2's requirement that already-seen content stays
     visible.
- [ ] **Step 3:** Get both designs validated before Task 1.2 starts, per
  this project's Algorithm Implementation Process (CLAUDE.md): "Is this
  algorithm correct? What edge cases break it?" If Codex is available this
  session, use it (`mcp__codex__codex`). If Codex is unavailable (as it was
  during this plan's own authoring — see Notes), use a fresh reviewer agent
  with no prior context on this plan, and have it independently re-derive
  the edge cases rather than just checking the ones already listed in Step
  1/2 — do not implement against an unvalidated design.
- [ ] **Step 4:** Append the validated design (or a link to wherever it's
  recorded) to this plan's Notes section before starting Task 1.2.

### Task 1.2 — Grammar, lexer, AST (mechanical, follows html/markdown pattern)

Package layout, following `loom/examples/html/` structure:

```
loom/examples/jsx/
  moon.mod
  moon.pkg
  meta/term_kind.mbt        # #loom.term enum (loomgen input)
  token/
    moon.pkg
    token.mbt                # #loom.token enum (loomgen input)
    token_impls.g.mbt         # generated (loomgen output)
  syntax/
    moon.pkg
    syntax_kind.mbt           # generated (loomgen output)
  spec.g.mbt                  # generated make_jsx_spec factory
  lexer.mbt                   # hand-written tokenizer (peek/advance, per html's pattern)
  ast.mbt                     # AST type — NEW, html has none (fold_node=() => ()); jsx needs a real one for Phase 2
  cst_parser.mbt               # hand-written recursive descent parser
  grammar.mbt                  # Grammar::new wiring, real fold_node this time
  proj_traits.mbt               # TreeNode + Renderable impls
  jsx_spec.mbt                  # LanguageSpec construction
  lexer_test.mbt
  parser_test.mbt
  ast_test.mbt
```

Unlike `examples/html` (which has `fold_node=(_node, _recurse) => ()` — CST
only, no AST), JSX needs a real AST from the start, because Phase 2's
`CstFold` step requires one. Decide the AST shape now, following
ADDING_A_LANGUAGE.md Step 1's `derive(Eq, Debug)` requirement:

```moonbit
pub(all) enum JsxNode {
  Element(tag~ : String, attrs~ : Array[JsxAttr], children~ : Array[JsxNode])
  Fragment(children~ : Array[JsxNode])
  Text(String)
  ExprSpan(raw~ : String)   // opaque {...} content, unparsed
  Error(String)
} derive(Eq, Debug)

pub(all) struct JsxAttr {
  name : String
  value : JsxAttrValue
} derive(Eq, Debug)

pub(all) enum JsxAttrValue {
  StringLit(String)
  ExprSpan(raw~ : String)  // {...} in attribute position
} derive(Eq, Debug)
```

This shape is a starting point, not gospel — Task 1.1's design gate may
require adjusting it (e.g. if unclosed elements need a distinct
`UnclosedElement` variant rather than reusing `Element` with an
incomplete-children marker). Update it in place if the validated design
says otherwise; do not silently diverge from what Task 1.1 decided.

- [ ] **Step 1:** Scaffold `meta/term_kind.mbt` and `token/token.mbt` with
  `#loom.term`/`#loom.token` annotations covering: `OpenTagStart` (`<`),
  `TagName`, `Slash`, `TagEnd` (`>`), `SelfCloseEnd` (`/>`),
  `AttrName`, `Eq`, `AttrStringLit`, `BraceOpen`, `BraceClose`, `Text`,
  `FragmentOpen` (`<>`), `FragmentClose` (`</>`), plus whatever Task 1.1's
  design settled on for raw-mode JS-expr tokens.
- [ ] **Step 2:** Run loomgen (mirrors html's `Regenerating Generated Files`
  recipe in its README):
  ```bash
  moon run loomgen --target native -- \
    loom/examples/jsx/token/token.mbt \
    --term loom/examples/jsx/meta/term_kind.mbt \
    /tmp/jsx-token /tmp/jsx-syntax
  cp /tmp/jsx-syntax/syntax_kind.mbt loom/examples/jsx/syntax/
  cp /tmp/jsx-token/token_impls.g.mbt loom/examples/jsx/token/
  ```
- [ ] **Step 3:** Write the lexer (`lexer.mbt`), implementing Task 1.1's
  validated mode-switch design. Write failing tests in `lexer_test.mbt`
  first (one per token kind + one for the brace-depth/string-awareness edge
  case from Task 1.1 Step 2), confirm they fail, then implement.
- [ ] **Step 4:** Write the recursive-descent parser (`cst_parser.mbt`),
  implementing Task 1.1's validated error-recovery design. Write failing
  tests in `parser_test.mbt` first — at minimum: simple element, nested
  elements, fragment, self-closing tag, attribute with string value,
  attribute with `{expr}` value, text child, `{expr}` child, unclosed
  element (per design case 2), truncated tag (per design case 3), truncated
  expression (per design case 4).
- [ ] **Step 5:** Write `fold_node` in `grammar.mbt`, converting CST to the
  `JsxNode` AST from the shape above (or its Task-1.1-revised version).
- [ ] **Step 6:** Write `ast.mbt` trait impls (`TreeNode`, `Renderable`) in
  `proj_traits.mbt`, following the html/markdown pattern shown in
  ADDING_A_LANGUAGE.md Step 1 (`children`, `same_kind`, `kind_tag`, `label`,
  `placeholder`, `unparse`).
- [ ] **Step 7:** `moon test -p dowdiness/jsx` (scoped — do not run unscoped
  `moon test` from inside `loom/`, see Phase 0's tcc-hang history).

### Acceptance Criteria (Phase 1)

- [ ] Task 1.1's two design docs exist and were validated (Codex or
      equivalent second-opinion review) before any Task 1.2 implementation
      commit
- [ ] `moon test -p dowdiness/jsx` passes, covering every case enumerated in
      Task 1.1 Step 2 (cases 1-4) plus the string-literal brace-depth edge
      case from Task 1.1 Step 1
- [ ] `JsxNode` derives `Eq, Debug`
- [ ] `moon check -p dowdiness/jsx --deny-warn` clean
- [ ] `moon info && moon fmt`, `git diff -- '*.mbti'` reviewed
- [ ] Loom-side PR merged and pushed to loom's remote

### Validation (Phase 1)

```bash
cd loom/examples/jsx
NEW_MOON_MOD=0 moon check -p dowdiness/jsx --deny-warn
NEW_MOON_MOD=0 moon test -p dowdiness/jsx
cd ../..
moon info && moon fmt
git diff -- '*.mbti'
```

---

## Phase 2 — `lang/jsx/proj` canopy integration (repo: canopy main)

**Prerequisite:** Phase 1 merged in loom's own repo. Then, in canopy:
```bash
git submodule update --remote loom
git add loom
git commit -m "chore: update loom submodule (add jsx parser)"
```
Verify `git status` shows only the `loom` pointer changed before committing
— do not bundle this with Phase 2 code changes in the same commit.

**Then, before Task 2.1:** `dowdiness/jsx` must be resolvable as an import
target from canopy packages. Verified fact: canopy's root `moon.work` lists
`"./loom/examples/markdown"` as a member (that's how
`lang/markdown/proj/moon.pkg` resolves `"dowdiness/markdown"` today) but
does **not** list `"./loom/examples/html"` — membership is per-example, not
automatic. Add `"./loom/examples/jsx"` to canopy's root `moon.work`
`members` array in the same commit as the submodule pointer bump above, and
run `moon check` from canopy root to confirm `dowdiness/jsx` resolves before
writing any Phase 2 package. This also means jsx joins canopy's full
workspace `moon check`/`moon test` fan-out and whatever CI matrices key off
`moon.work` membership — note that in the PR description, since it's a
scope expansion beyond "just add a proj package."

Follow ADDING_A_LANGUAGE.md **Phase 2, Steps 2-4 only**. Do not implement
Steps 5-6 (edit operations, companion, SyncEditor factory) — those are
explicitly Phase 3 (deferred). This means `lang/jsx/` gets only a `proj/`
subpackage, not `edits/` or `companion/`.

### Task 2.1: Projection builder

**File:** `lang/jsx/proj/proj_node.mbt` (~60-120 lines, per the guide's own
estimate for this step)

- [ ] **Step 1:** `lang/jsx/proj/moon.pkg`:
  ```
  import {
    "dowdiness/canopy/core" @core,
    "dowdiness/incr" @incr,
    "dowdiness/jsx" @jsx,
    "dowdiness/loom" @loom,
    "dowdiness/loom/core" @loomcore,
    "dowdiness/seam" @seam,
  }
  ```
- [ ] **Step 2:** Implement `syntax_to_proj_node` / `build_proj_tree`,
  pattern-matching on `JsxNode`, following the guide's `Document(blocks)`
  container-vs-leaf example (Element/Fragment are containers; Text/ExprSpan
  are leaves).
- [ ] **Step 3:** Add `parse_to_proj_node(text : String)` convenience
  function per the guide's exact signature.
- [ ] **Step 4:** `moon check`.

### Task 2.2: Token spans

**File:** `lang/jsx/proj/populate_token_spans.mbt` (~80-150 lines)

- [ ] **Step 1:** Define role conventions for JSX, following Markdown's
  table pattern: `"tag_name"`, `"attr_name"`, `"attr_value"`, `"text"`,
  `"expr_raw"` (the opaque `{...}` content span — needed later if/when
  Phase 3 wires an editor, but populate it now since it's free to compute
  alongside the others), `"open_bracket"`/`"close_bracket"` for element
  delimiters.
- [ ] **Step 2:** Implement `populate_token_spans`, parallel-walking syntax
  tree and projection tree per the guide's pattern, calling
  `source_map.set_token_span(proj_id, role, range)`.
- [ ] **Step 3:** `moon check`.
- [ ] **Step 4 (checkpoint whitebox test):**
  `lang/jsx/proj/proj_node_wbtest.mbt`:
  ```moonbit
  test "parse and project basic element" {
    let (root, errors) = parse_to_proj_node("<div>hello</div>")
    inspect(errors.length(), content="0")
    inspect(root.kind.kind_tag(), content="Element")
  }
  ```
  (Verified against current syntax in `lang/markdown/proj/proj_node_wbtest.mbt`
  — that file uses plain `inspect(...)`/`parse_to_proj_node(...)`, not the
  deprecated postfix-`!` error-propagation call form; do not copy the `!`
  form from ADDING_A_LANGUAGE.md's own prose example without checking
  current code first.)
  Run: `moon test -p dowdiness/canopy/lang/jsx/proj`

### Task 2.3: Memo builder

**File:** end of `lang/jsx/proj/proj_node.mbt` (~15 lines)

- [ ] **Step 1:** Implement `build_jsx_projection_memos`, delegating to
  `@core.build_projection_memos` exactly per the guide's template (do not
  hand-roll reconciliation).
- [ ] **Step 2:** `moon check`.

### Task 2.4: Streaming-reconciliation existence-proof test

This is the test that actually validates the generative-UI premise from this
plan's "Why" section — not optional, not generic coverage.

**File:** `lang/jsx/proj/streaming_reconcile_wbtest.mbt`

- [ ] **Step 1:** Pick a fixed JSX fixture with at least 3 nested elements
  and one `{expr}` child, e.g.
  `<div><h1>{title}</h1><p>hello world</p></div>`.
- [ ] **Step 2:** Write a test that feeds the parser this text in at least 6
  increasing prefixes, and make sure at least two of them cut **mid-token**,
  not just at clean JSX-token boundaries — LLM token streams don't align
  with JSX tokens, so a test that only ever cuts cleanly (`<div><h1>`, never
  `<di`) doesn't exercise Task 1.1 Step 2 cases 3/4 at all. Example prefix
  sequence: `<di` (mid-tag-name), `<div><h1` (mid-tag-name again), `<div><h1>`,
  `<div><h1>{titl` (mid-expression), `<div><h1>{title}</h1><p>hello`
  (mid-text), full string. Use the same `Parser[JsxAst]`/incremental
  re-parse entry point Markdown's integration test uses — that test lives
  at `lang/markdown/companion/integration_wbtest.mbt` (in `companion/`, not
  `proj/`; verified by direct read, correcting an earlier draft of this
  plan). Since Phase 2 explicitly does not create a `lang/jsx/companion/`
  package, this test must drive the incremental parser directly (whatever
  `Parser[JsxAst]`/`apply_edit`-equivalent entry point `loom/loom/pipeline/`
  exposes) from inside `lang/jsx/proj/streaming_reconcile_wbtest.mbt` — read
  the companion test only for the call shape, do not conclude a companion
  package is needed to write this test.
- [ ] **Step 3:** Record the `NodeId` assigned to the outer `<div>`
  element's `ProjNode` and to the `<h1>` element's `ProjNode` **at their
  first appearance** in the tree — which, per Task 1.1 Step 2 case 2's
  requirement, is while they are still unclosed, not after the whole
  fixture has streamed in. (An earlier draft of this task recorded NodeIds
  "once fully parsed" — for the outer `<div>`, that's only true at the
  *final* prefix, making any stability assertion vacuous since there are no
  later prefixes left to check against. Recording at first appearance is
  the only version of this test that actually exercises the
  unclosed→closed identity transition, which is the property the whole
  plan's premise depends on.) Assert those specific `NodeId`s are identical
  across every subsequent prefix, including the mid-token ones from Step 2.
- [ ] **Step 4:** Also assert every prefix from the first point `<div>` has
  been opened onward produces a non-empty `children` array on the outer
  element's `ProjNode`, even before `</div>` arrives — Task 1.1 Step 2 case
  2's hard requirement, checked end-to-end here.
- [ ] **Step 5:** For the `{title}` expression specifically, additionally
  test the growing-opaque-span sub-case from Task 1.1 Step 1 (`{titl` →
  `{title` → `{title}`) and assert whichever identity behavior that design
  doc specified (single leaf with mutating content, vs. new node per
  partial parse) — do not leave this case unchecked just because Step 3
  covers element-level identity; span-level identity is a distinct claim.
- [ ] **Step 6:** `moon test -p dowdiness/canopy/lang/jsx/proj`.

### Acceptance Criteria (Phase 2)

- [ ] `moon test -p dowdiness/canopy/lang/jsx/proj` passes, including the
      Task 2.4 streaming-reconciliation test
- [ ] `moon check` (workspace) clean
- [ ] `moon info`, `git diff -- '*.mbti'` reviewed
- [ ] No `lang/jsx/edits/` or `lang/jsx/companion/` package created (explicit
      scope boundary — flag it in review if a future agent adds one under
      this plan without an explicit scope amendment)

### Validation (Phase 2)

```bash
moon check
moon test -p dowdiness/canopy/lang/jsx/proj
moon info
git diff -- '*.mbti'
```

---

## Phase 3 — Deferred (explicit non-goals, not planned in detail)

Do not start these under this plan. List kept here so the next planning pass
doesn't have to rediscover scope boundaries:

- Bidirectional editing: `lang/jsx/edits/` (edit op enum + dispatcher) and
  `lang/jsx/companion/` (`LanguageSpec` + `SyncEditor` factory) — ADDING_A_LANGUAGE.md
  Steps 5-6, deferred until Phase 2's read-only reconciliation is validated
  and there's a real consumer asking for editability.
- JS expression evaluation of `{...}` spans — needs a real JS
  parser/evaluator or an embedding of an existing one; out of scope for the
  incremental-parser layer entirely, belongs to a runtime/eval component.
- FFI export (`ffi/canopy_jsx.mbt`) and a TypeScript adapter, per
  ADDING_A_LANGUAGE.md's "Optional: FFI and web integration" section.
- A component registry mapping `ViewNode` → real mounted UI
  components/DOM — the actual "generative UI" rendering surface. This is
  the reason the whole plan exists, but it depends on Phase 2 shipping
  first and on product decisions (which component set, how props bind to
  `{expr}` spans) that are out of scope for a parser-layer plan.
- Namespace handling (SVG/MathML tags), unquoted attribute values, spread
  attributes (`{...props}`) — defer indefinitely unless a concrete
  consumer needs them; do not add speculatively.

## Risks

- **Phase 0's tcc hang may not be fixable within this plan's timebox.** The
  plan explicitly allows leaving it as a documented CI workaround (Task 0.1
  Step 4, branch 2) rather than blocking Phase 1 on an upstream toolchain
  bug. Do not let Phase 1 start until Task 0.1 reaches *some* documented
  conclusion, even if that conclusion is "still broken, workaround stays."
- **Resolved (2026-07-09, second review pass — no longer an open question):**
  `set_lex_mode` has no working consumer today. `grep -rn lex_mode
  loom/loom/*.mbt` (excluding tests) shows the field is only stored, read
  back, and checkpointed — nothing in `pipeline/`/`incremental/` reads it to
  change lexer output, and `Grammar.lex` is a whole-input batch function
  with no `ParserContext` parameter. Task 0.2 and Task 1.1 have been
  rewritten to default to lexer-side detection (Option A) and `ModeLexer[T,
  M]` respectively, with `set_lex_mode` demoted to a fallback branch gated
  on an explicit architecture check (Task 0.2 Step 0) rather than assumed.
  Do not re-introduce `set_lex_mode` as the default plan without re-verifying
  this — it is not a stale note, it was checked by direct grep.
- **String-literal-aware brace counting inside `{...}` is exactly the kind
  of thing that looks simple and has a long tail of edge cases** (nested
  template literals with their own `${}` interpolation, regex literals
  containing `{`/`}`, comments containing quote characters). The design gate
  (Task 1.1) should state explicitly which of these it handles and which it
  declares out of scope — silently mishandling one is worse than declaring
  it unsupported.
- **Multi-repo coordination.** Phase 0 and Phase 1 PRs must be merged and
  pushed to loom's own remote before the canopy submodule pointer bump
  (start of Phase 2). An agent picking up Phase 2 without checking this will
  either work against a stale `loom` checkout or (worse) push a submodule
  pointer bump to an unmerged loom commit.

## Notes

- Related loom issues: #626 (RawText emission, OPEN), #609 (M19 capstone,
  OPEN), #532 (lex-mode API, CLOSED/shipped), #646 (tcc hang, CLOSED but
  root cause unresolved per its own body).
- Reference packages to read before writing code, not to copy blindly:
  `loom/examples/html/` (tag/lexer structure, coarse-token design),
  `loom/examples/markdown/src/` (`ModeLexer[T, M]` — the mechanism Phase 1
  defaults to for embedded-expression mode switching, see Current State),
  `lang/markdown/{proj,edits,companion}/`
  (canopy-side reference layout — but this plan only implements the `proj/`
  slice of it).
- This plan was authored inline (Sonnet 5) rather than by Codex per the
  project's "Opus orchestrates, Codex plans" convention, because Codex was
  reported unavailable in the authoring session (2026-07-09). If Codex
  becomes available before Phase 1 Task 1.1 executes, run the two design
  docs through it as originally intended rather than treating this plan's
  own draft answers to Task 1.1 as pre-validated — they are scaffolding for
  the design questions, not the validated design itself.
- **2026-07-09, second-opinion review (Fable 5, via a fresh agent since the
  `advisor` tool was unavailable this session):** found two blockers and
  one major gap, all independently verified by direct source reads before
  being applied here:
  1. `set_lex_mode` has no working consumer in loom today (confirmed by
     grep — see Current State and Risks). The plan originally recommended
     it as Phase 0/Task 1.1's default mechanism; both tasks now default to
     lexer-side detection / `ModeLexer` instead, with `set_lex_mode` demoted
     to an explicitly-gated fallback branch.
  2. Phase 2 was missing the step that registers `./loom/examples/jsx` in
     canopy's root `moon.work` — without it, `"dowdiness/jsx"` doesn't
     resolve from `lang/jsx/proj/moon.pkg` and an executing agent would be
     stranded. Added as an explicit step before Task 2.1.
  3. Task 2.4's original NodeId-stability assertion recorded identity
     "once fully parsed," which is vacuous for the outer element (only true
     at the final prefix). Rewritten to record identity at first appearance
     (while still unclosed), added mid-token prefix cuts, added a
     growing-opaque-span identity sub-case, and corrected the reference
     test's actual path (`companion/`, not `proj/`).
  The review also flagged (addressed above): nested JSX inside `{...}` as
  an explicit stated limitation rather than a silent gap, HTML tag-name
  case-insensitivity (was incorrectly stated as case-sensitive), and
  deprecated postfix-`!` syntax in a pasted test snippet.
- Task 1.1's design-gate output (the two prose docs) should be appended
  below this line once written, or linked if kept as separate files.
