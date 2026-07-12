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

### Task 0.1: Reproduce and minimize the tcc hang (issue #646) — RESOLVED 2026-07-10

This is an investigation task, not a scripted fix — the root cause is
unconfirmed (toolchain-side `tcc` bug vs. project-side). Time-box it.

**Resolution: already fixed upstream, no further work needed here — see the
2026-07-10 Notes entry.** Steps below are recorded as N/A per that finding
rather than executed individually.

- [x] **Step 1:** From `loom/` submodule root, reproduce:
  ```bash
  cd loom/examples/html
  NEW_MOON_MOD=0 moon test --target native
  ```
  Confirm it still hangs on the current toolchain pin (loom `CLAUDE.md` /
  `.github/workflows/ci.yml` for the pinned MoonBit version — do not assume
  the 2026-06-29 repro toolchain in #646 is still current; re-check the pin
  first).
- [x] **Step 2:** Minimize — does `moon test -p dowdiness/html --target native`
  from `examples/html/` alone still hang, or only full-workspace fan-out
  (`cd loom && moon test`)? Record which.
  N/A — confirmed no hang either way on the current checkout (fix already
  present); unscoped fan-out surfaces an unrelated pre-existing
  `lambda/typecheck` abort, not a hang.
- [x] **Step 3:** Per #646's own suggested investigation: inspect why the
  html blackbox test driver's `tcc` rspfile includes `README.mbt.md:0-5`
  (the doc-test block) alongside `parser_test.mbt`/`lexer_test.mbt`. If the
  doc-test compilation is the hang trigger, try isolating/removing it from
  the native blackbox build and re-test.
  N/A — root cause was a parser recovery bug (mismatched close tag from a
  README doc test caused an infinite recovery loop), already found and
  fixed in loom PR #647; no doc-test isolation needed.
- [x] **Step 4 (branch on result):** Branch taken: reproducible and already
  root-caused/fixed **by someone else** before this session (loom PR #647,
  merged 2026-07-07) — `examples/html` is already back in loom's CI
  `test-modules` matrix (loom PR #649, merged 2026-07-08), confirmed green
  via the scoped local repro this session.
- [x] **Step 5:** Whichever branch: leave a one-paragraph note in this plan's
  Notes section (or a loom-side issue comment on #646) recording which
  branch was taken and why, so the next agent doesn't re-investigate from
  scratch.
  Done — see the 2026-07-10 Notes entry above.

### Task 0.2: Fix RawText emission for `<script>`/`<style>` (issue #626) — DONE 2026-07-10

**Resolution: merged as [dowdiness/loom#662](https://github.com/dowdiness/loom/pull/662), squashed into loom `main` at `13b809e`, CI green (33/33 checks), canopy's loom submodule pointer bumped to that commit in the same session.** Steps below are recorded as completed per that PR, not re-executed individually.

Two options are already named in #626 itself. **Design gate, not a coin
flip** — and per Current State, `set_lex_mode` (Option B as originally
scoped) is **not implementable as a mid-parse lexer switch today**: the
lexer is invoked as a whole-input batch function with no feedback path from
`ParserContext`. Do not start Option B's implementation steps until Step 0
below is answered.

- [x] **Step 0 (architecture check, do this first):** Read
  `loom/examples/html/grammar.mbt` and `cst_parser.mbt` and confirm how
  lexing and parsing are actually sequenced for this example: is the whole
  input tokenized once via `Grammar.lex` before `cst_parser.mbt` ever runs
  (this appears to be the case given `Grammar.lex : (String) -> LexResult[T]`
  takes no `ParserContext`), or is there an interleaved/incremental path
  this example uses instead? Then choose:
  Confirmed by direct read: `Grammar.lex : (String) -> LexResult[T]`, no
  `ParserContext` parameter, batch pass — Option A confirmed correct, no
  interleaved path exists. One refinement the plan didn't anticipate: the
  existing `PrefixLexer`/step-lexer (`html_step_lexer(source, start)`) is
  itself stateless per call — no channel to carry "the previous token was
  `OpenTag(script)"`. The correct Option A mechanism is `@core.ModeLexer[T,
  M]` + `@core.erase_mode_lexer`, the exact pattern `examples/markdown`
  already uses for its own raw-until-delimiter lexing
  (`HtmlBlockRaw`/`HtmlBlockUntil`) — not a hand-rolled stateless hack. See
  PR #662 for the implementation.
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

- [x] **Step 1:** Write a failing test first, in
  `loom/examples/html/parser_test.mbt` — done as `"script content is raw
  text"`, using `@seam.CstElement::Node(tree).iter().find_first(...)` to
  locate the `RawTextToken` leaf (not `CstNode::first_token`, whose
  parameter is an `is_trivia` skip-predicate, not a match-predicate — a
  real API-signature trap caught during Step 5, see PR #662).
- [x] **Step 2:** Run it, confirm it fails — confirmed 2 diagnostics
  (expected 0) via `moon test -p dowdiness/html` from `loom/examples/html/`
  (the `-f parser_test.mbt` filter itself is unreliable/broken, see
  `feedback_moon_test_f_filter_broken` memory — ran the full scoped suite
  instead).
- [x] **Step 3 (Option A path — expected):** Implemented in
  `loom/examples/html/lexer.mbt` via `@core.ModeLexer[Token, HtmlLexMode]`
  (`Normal | RawText(String)`) + `@core.erase_mode_lexer`, case-insensitive
  close-tag matching with a tag-name-boundary check (`</scripts>` doesn't
  falsely close a `<script>`), zero-width-match self-delegation for
  immediately-closed elements (`<script></script>`) to avoid the #646 class
  of zero-progress bug. Also made `is_raw_text_tag` (cst_parser.mbt)
  case-insensitive and shared it as the single source of truth between the
  lexer's mode switch and the parser's raw-branch gate.
- [ ] **Step 3-alt:** not taken — Step 0 confirmed no interleaved lex/parse
  path exists.
- [x] **Step 4:** Confirmed via lexer-level regression tests
  (`lexer_test.mbt`): `@token.RawText` (not `@token.Text`) emitted, span
  excludes the open/close tags, mixed-case tags work, empty content doesn't
  hang or emit a zero-width token.
- [x] **Step 5:** Test from Step 1 passes (26/26 total in the package).
- [x] **Step 6:** `moon test -p dowdiness/html` (26/26) and
  `moon check -p dowdiness/html --deny-warn` (clean) both pass — note
  `moon check` takes filesystem `[PATH]...`, not `moon test`'s `-p
  <module/package>` flag; ran from within `loom/examples/html/` instead.
- [x] **Step 7:** `moon info && moon fmt` run from loom root;
  `git diff -- '*.mbti'` empty — no interface changes (new bindings are
  unexported `let`s).
- [x] **Step 8:** Committed in the loom submodule (2 commits: the fix, plus
  a `/moonbit-refactoring`-pass follow-up flattening a nested match),
  pushed to `dowdiness/loom`, opened
  [PR #662](https://github.com/dowdiness/loom/pull/662) (`Closes #626`,
  auto-closed on merge). CI green (33/33 checks, including main's own
  post-merge run at `13b809e`, not just the pre-merge PR checks). Squash-merged
  with explicit user confirmation. Canopy's `loom` submodule pointer bumped
  to `13b809e` in this same session (see next commit in canopy's own
  history) — #609 (M19 capstone) is NOT closed by this PR, it remains a
  separate, larger task per Step 0's explicit scope boundary.

### Acceptance Criteria (Phase 0) — met 2026-07-10

- [x] `moon test -p dowdiness/html` passes from `loom/examples/html/`
      (26/26)
- [x] `<script>`/`<style>` content produces `RawTextLeaf` nodes, 0
      diagnostics, per the Step 1 test
- [x] #646 is fixed (already, before this session — loom PR #647) and
      `examples/html` is back in loom's CI `test-modules` matrix (loom PR
      #649) — the first acceptable exit state, not the documented-workaround
      branch
- [x] `git diff -- '*.mbti'` reviewed — no interface changes
- [x] Loom-side PR merged and pushed to loom's own remote —
      [dowdiness/loom#662](https://github.com/dowdiness/loom/pull/662),
      squash-merged, CI green including main's own post-merge run

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

- [x] **Step 1:** Write a prose design doc (append to this plan's Notes, or a
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
- [x] **Step 2:** Write a prose design doc for **error recovery on a
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
- [x] **Step 3:** Get both designs validated before Task 1.2 starts, per
  this project's Algorithm Implementation Process (CLAUDE.md): "Is this
  algorithm correct? What edge cases break it?" If Codex is available this
  session, use it (`mcp__codex__codex`). If Codex is unavailable (as it was
  during this plan's own authoring — see Notes), use a fresh reviewer agent
  with no prior context on this plan, and have it independently re-derive
  the edge cases rather than just checking the ones already listed in Step
  1/2 — do not implement against an unvalidated design.
- [x] **Step 4:** Append the validated design (or a link to wherever it's
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
  Root(children~ : Array[JsxNode])   // streaming prefix can have several roots
  Element(tag~ : String, attrs~ : Array[JsxAttr], children~ : Array[JsxNode])
  Fragment(children~ : Array[JsxNode])
  Text(String)
  ExprSpan(raw~ : String)   // opaque {...} content, unparsed, quotes kept
  Error(String)
} derive(Eq, Debug)

pub(all) struct JsxAttr {
  name : String
  value : JsxAttrValue
} derive(Eq, Debug)

pub(all) enum JsxAttrValue {
  StringLit(String)        // unquoted content; diagnostics carry truncation
  ExprSpan(raw~ : String)  // {...} in attribute position
  Bare                     // boolean attribute, or truncated `<div cla`
} derive(Eq, Debug)
```

This shape was a starting point; Step 5 (2026-07-10) updated it in place
per the instruction below with three divergences, each recorded in loom
commit `9857615`: `Root(children~)` added (a streaming prefix legally has
several roots and `Fragment` must not be conflated with the document
root), `JsxAttrValue::Bare` added (boolean attributes and EOF-truncated
attribute names both produce value-less `AttrNode`s), and `StringLit`
stores unquoted content (diagnostics, not the AST, carry the
unterminated-literal fact). Unclosed elements reuse `Element` with no
marker — the truncated-prefix AST is deliberately shape-identical to its
closed equivalent (Design B case 2). Original instruction: update this
snippet in place if the validated design says otherwise; do not silently
diverge from what Task 1.1 decided.

- [x] **Step 1:** Scaffold `meta/term_kind.mbt` and `token/token.mbt` with
  `#loom.term`/`#loom.token` annotations covering: `OpenTagStart` (`<`),
  `TagName`, `Slash`, `TagEnd` (`>`), `SelfCloseEnd` (`/>`),
  `AttrName`, `Eq`, `AttrStringLit`, `BraceOpen`, `BraceClose`, `Text`,
  `FragmentOpen` (`<>`), `FragmentClose` (`</>`), plus whatever Task 1.1's
  design settled on for raw-mode JS-expr tokens. Done 2026-07-10 in loom
  commit `97e8dd7` (`feat/jsx-phase1-task1.2` branch, not yet merged) —
  also added `ExprRawText`/`ExprStringUnterminated`/
  `AttrStringLitUnterminated` (Design B) and `ExprSpanNode`/`AttrNode`
  term kinds beyond html's set. `NEW_MOON_MOD=0 moon check examples/jsx`
  passes.
- [x] **Step 2:** Run loomgen (mirrors html's `Regenerating Generated Files`
  recipe in its README). Done 2026-07-10 in loom commit `9034eb8` — ran
  both parts of html's recipe (the snippet below only shows part 1; part
  2 seeds `spec.g.mbt`/`make_jsx_spec` from the generated
  `syntax_kind.mbt`, needed later for `jsx_spec.mbt`/`grammar.mbt`).
  Re-running part 1 with `--seed` reproduced byte-identical
  `token_impls.g.mbt` output, confirming determinism.
  ```bash
  moon run loomgen --target native -- \
    loom/examples/jsx/token/token.mbt \
    --term loom/examples/jsx/meta/term_kind.mbt \
    /tmp/jsx-token /tmp/jsx-syntax
  cp /tmp/jsx-syntax/syntax_kind.mbt loom/examples/jsx/syntax/
  cp /tmp/jsx-token/token_impls.g.mbt loom/examples/jsx/token/
  ```
- [x] **Step 3:** Write the lexer (`lexer.mbt`), implementing Task 1.1's
  validated mode-switch design. Write failing tests in `lexer_test.mbt`
  first (one per token kind + one for the brace-depth/string-awareness edge
  case from Task 1.1 Step 2), confirm they fail, then implement. Done
  2026-07-10 in loom commits `a2f6805` + `8a3f78a` (Codex
  post-implementation review applied; 20 lexer tests).
- [x] **Step 4:** Write the recursive-descent parser (`cst_parser.mbt`),
  implementing Task 1.1's validated error-recovery design. Write failing
  tests in `parser_test.mbt` first — at minimum: simple element, nested
  elements, fragment, self-closing tag, attribute with string value,
  attribute with `{expr}` value, text child, `{expr}` child, unclosed
  element (per design case 2), truncated tag (per design case 3), truncated
  expression (per design case 4). Done 2026-07-10 in loom commit `d97399d`
  (tests confirmed red first; 23 parser tests incl. 2 Codex-review
  termination regressions; 43/43 for the package; `parse_cst` exposed via
  `SyntaxGrammar` — fold-free until Step 5; note: `parse_jsx_root` must
  not open a RootNode, the entry points wrap in `spec.root_kind`).
- [x] **Step 5:** Write `fold_node` in `grammar.mbt`, converting CST to the
  `JsxNode` AST from the shape above (or its Task-1.1-revised version).
  Done 2026-07-10 in loom commit `9857615` (tests confirmed red first; 16
  AST tests incl. 2 Codex-review regressions; 59/59 for the package;
  AST-shape divergences recorded in the snippet above; `parse_cst` now
  delegates to the full `jsx_grammar`, Step 4's interim `SyntaxGrammar`
  removed).
- [x] **Step 6:** Write `ast.mbt` trait impls (`TreeNode`, `Renderable`) in
  `proj_traits.mbt`, following the html/markdown pattern shown in
  ADDING_A_LANGUAGE.md Step 1 (`children`, `same_kind`, `kind_tag`, `label`,
  `placeholder`, `unparse`). Done 2026-07-11 in loom commit `4751207`
  (tests confirmed red first; 14 trait tests incl. 2 Codex-review
  regressions). Load-bearing decisions: `Element` `same_kind` requires an
  equal tag (one identity reset at streaming tag completion);
  `Text`/`ExprSpan` `same_kind` ignore content (growing-span ProjNode
  identity, per the Design B note); `kind_tag` = plain variant names
  (Phase 2's Step 4 test expects exactly `"Element"`). Note: the two
  projection-layer ExprSpan ID-stability tests the Design B note requires
  live in Phase 2's `streaming_reconcile_wbtest.mbt` (Steps 3/5) — they
  need canopy's `@core.reconcile`, which loom-side Task 1.2 cannot reach.
- [x] **Step 7:** `moon test -p dowdiness/jsx` (scoped — do not run unscoped
  `moon test` from inside `loom/`, see Phase 0's tcc-hang history). Done
  2026-07-11: 73/73 (20 lexer, 23 parser, 16 AST, 14 trait tests).

### Acceptance Criteria (Phase 1)

- [x] Task 1.1's two design docs exist and were validated (Codex or
      equivalent second-opinion review) before any Task 1.2 implementation
      commit
- [x] `moon test -p dowdiness/jsx` passes, covering every case enumerated in
      Task 1.1 Step 2 (cases 1-4) plus the string-literal brace-depth edge
      case from Task 1.1 Step 1 — 73/73 as of loom `4751207` (2026-07-11)
- [x] `JsxNode` derives `Eq, Debug` (`examples/jsx/ast.mbt`)
- [x] `moon check -p dowdiness/jsx --deny-warn` clean (2026-07-11, run as
      `moon check examples/jsx --deny-warn` — `moon check` scopes by path)
- [x] `moon info && moon fmt`, `git diff -- '*.mbti'` reviewed after every
      step (final surface: `parse_cst`, `parse_ast`, `jsx_grammar`,
      `JsxNode`/`JsxAttr`/`JsxAttrValue`, TreeNode/Renderable impls)
- [x] Loom-side PR merged and pushed to loom's remote — loom PR #680,
      squash `1e90ab7`, merged 2026-07-11 (37/37 checks green; CI matrix
      gained examples-jsx format + check/test jobs in the same PR)

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

- [x] **Step 1:** `lang/jsx/proj/moon.pkg` — done 2026-07-11, added
  `"dowdiness/jsx/syntax" @syntax` beyond this snippet (needed for
  `AttrNode`/token-kind filtering in Steps 2 and Task 2.2). Also required
  registering `dowdiness/jsx@0.1.0` in canopy's root `moon.mod` import
  list (not just `moon.work` membership) — `moon check` failed with
  "containing module is not imported" until both were added.
  ```
  import {
    "dowdiness/canopy/core" @core,
    "dowdiness/incr" @incr,
    "dowdiness/jsx" @jsx,
    "dowdiness/jsx/syntax" @syntax,
    "dowdiness/loom" @loom,
    "dowdiness/loom/core" @loomcore,
    "dowdiness/seam" @seam,
  }
  ```
- [x] **Step 2:** Implemented `syntax_to_proj_node` / `build_proj_tree` in
  `proj_node.mbt`, done 2026-07-11. Container/leaf split follows
  `JsxNode`'s own `TreeNode::children` grouping (`loom/examples/jsx/proj_traits.mbt`):
  `Root`/`Fragment`/`Element` are containers, `Text`/`ExprSpan`/`Error` are
  leaves — verified by direct read of `jsx_fold_node` in
  `loom/examples/jsx/grammar.mbt` that this matches the CST shape.
  Divergence from the guide's `Document(blocks)` example: `Element`'s CST
  children interleave `AttrNode`s with content children (confirmed by
  reading `jsx_fold_node`'s own `node.children().filter(c => c.kind() !=
  attr_kind)` filtering), so `build_proj_tree` needs the same filter
  (`element_content_children`) before the parallel walk — `Root`/`Fragment`
  have no such filtering need. `fold_node` itself is reached via
  `@jsx.jsx_grammar.fold_node` (a `Grammar` struct field), not a
  separately-exported top-level function like markdown's
  `markdown_fold_node` — jsx's `pkg.generated.mbti` doesn't export one.
- [x] **Step 3:** Added `parse_to_proj_node(text : String)` — done
  2026-07-11, matches the guide's signature exactly.
- [x] **Step 4:** `moon check lang/jsx/proj` — done 2026-07-11, clean (0
  errors; `@incr`/`@loom` unused-import warnings expected until Task 2.3
  consumes them).

### Task 2.2: Token spans

**File:** `lang/jsx/proj/populate_token_spans.mbt` (~80-150 lines)

- [x] **Step 1:** Role conventions defined 2026-07-11 per the plan's list,
  plus one addition: `"attr_name"`/`"attr_value"` are index-suffixed
  (`"attr_name:0"`, `"attr_value:0"`, ...) because attributes aren't
  separate `ProjNode`s (excluded from `TreeNode::children`), so their
  spans must attach to the owning `Element`'s id — a plain role string
  would collide across an element with more than one attribute
  (`SourceMap` holds one `Range` per `(id, role)`). Documented inline in
  `populate_attrs`'s doc comment.
- [x] **Step 2:** Implemented in `populate_token_spans.mbt`, done
  2026-07-11. `"close_bracket"` needed extra care beyond the guide's
  pattern: an element's close tag reuses the same token kinds as its open
  tag (`OpenTagStartToken`, `TagNameToken`, `TagEndToken` all appear
  twice for a container element — confirmed by reading
  `loom/examples/jsx/cst_parser.mbt`'s close-tag comment), so
  `close_bracket` takes the *last* `TagEndToken` (via `tokens_of_kind`),
  not `find_token`'s first-match default.
  **Codex post-impl review (2026-07-11) caught a real bug here**: the
  first cut took *any* last match, so an unclosed element (Design B case
  2, e.g. `<div><span>text`) — whose only direct `TagEndToken` is the
  open tag's own `>`, since `parse_content` in `cst_parser.mbt` is only
  reached after that token is already emitted, and `emit_close_tag`
  contributes a second one only when a real `</tag>` closer exists —
  wrongly got that open-tag `>` recorded as `close_bracket` instead of
  `None`. Fixed to require `tokens_of_kind(TagEndToken).length() >= 2`
  before taking the last match. Regression coverage added in
  `lang/jsx/proj/populate_token_spans_wbtest.mbt` (new file, 3 tests):
  unclosed element → no `close_bracket`; closed element → `close_bracket`
  at its own `>`; nested same-tag elements (`<div><div>x</div></div>`)
  each get their own distinct `close_bracket` span. Confirmed red
  (`Some({start: 4, end: 5})` instead of `None`) against the pre-fix code
  before reapplying the fix, per test-first discipline.
- [x] **Step 3:** `moon check lang/jsx/proj` — done 2026-07-11, clean.
  Re-verified 2026-07-11 after the close_bracket fix above: `moon check`
  workspace-wide clean, `moon test -p dowdiness/canopy/lang/jsx/proj` →
  14/14 passed (11 original + 3 new regression tests).
  **Follow-up broad Codex review (2026-07-11, post-merge on PR #877's
  squashed commit) caught a second gap**: Step 1's doc comment listed
  `"tag_name"` as a role convention, but it was never actually populated
  — `populate_element_delimiters` only ever set `open_bracket`/
  `close_bracket`. Fixed by adding a `set_optional_token_span(...,
  "tag_name", TagNameToken)` call; `find_token`'s first-match default is
  correct here without extra disambiguation (unlike `close_bracket`)
  because the open tag's `TagNameToken` is always emitted before any
  close tag's. 2 new regression tests added (basic element, and a
  nested-same-tag case proving the open tag's name is picked, not the
  close tag's or inner element's). The broad review also flagged that
  `attr_name:N`/`attr_value:N`'s index is positional, not a durable
  per-attribute identity across edits — documented as a caveat in
  `populate_attrs`'s doc comment rather than changed (no consumer yet;
  Phase 2 is read-only). `moon test -p dowdiness/canopy/lang/jsx/proj` →
  16/16 passed.
- [x] **Step 4 (checkpoint whitebox test):** written in
  `lang/jsx/proj/proj_node_wbtest.mbt`, done 2026-07-11 — 8 tests, all
  passing. The plan's literal snippet above needed one correction before
  it would pass: `parse_to_proj_node` always wraps in `Root` (Task 1.2
  Step 5's later AST divergence — a streaming prefix can have several
  roots — postdates this snippet), so `root.kind.kind_tag()` is `"Root"`,
  not `"Element"`; the actual test asserts `root.children[0].kind.kind_tag()
  == "Element"` instead. Confirmed by first running the plan's exact
  snippet and observing the failure before editing it (not just spot-copied).
  Run: `moon test -p dowdiness/canopy/lang/jsx/proj` → 8/8 passed.

### Task 2.3: Memo builder

**File:** end of `lang/jsx/proj/proj_node.mbt` (~15 lines)

- [x] **Step 1:** Implemented `build_jsx_projection_memos` — done
  2026-07-11, delegates to `@core.build_projection_memos` with no
  `reconcile_node` override (uses its default, `@core.reconcile`), exactly
  per the guide's basic template — no hand-rolled reconciliation.
- [x] **Step 2:** `moon check lang/jsx/proj --deny-warn` — done
  2026-07-11, clean (the `@incr`/`@loom` unused-import warnings from Task
  2.1 Step 4 are gone now that this step consumes them).

### Task 2.4: Streaming-reconciliation existence-proof test

This is the test that actually validates the generative-UI premise from this
plan's "Why" section — not optional, not generic coverage.

**File:** `lang/jsx/proj/streaming_reconcile_wbtest.mbt`

- [x] **Step 1:** Fixture chosen exactly as the plan's example —
  `<div><h1>{title}</h1><p>hello world</p></div>` (3 elements: div, h1, p;
  1 expr child) — `streaming_fixture` in `streaming_reconcile_wbtest.mbt`.
- [x] **Step 2:** Implemented using the plan's exact 6-prefix example
  sequence verbatim (`streaming_prefixes`), driving a raw
  `@loom.new_parser(text, @jsx.jsx_grammar)` + `parser.set_source(...)`
  directly — confirmed by reading `lang/markdown/companion/integration_wbtest.mbt`
  for the call shape only, and finding the more on-point precedent in
  `lang/markdown/proj/sdeg_heading_side_table_wbtest.mbt` (a proj-level
  wbtest already using `@loom.new_parser` + `parser.set_source` +
  `derived.read_or_abort()` with no companion package involved) — no
  `lang/jsx/companion/` package created.
- [x] **Step 3:** Recorded `div`'s and `h1`'s `NodeId`s at prefix index 1
  (`"<div><h1"`) per the recording-point clarification — both tags are
  already complete and stable at that prefix. Added the optional
  companion assertion: prefix 0's `<di` element's id differs from `div`'s
  recorded id (`inspect(di_id == div_id, content="false")`).
- [x] **Step 4:** Asserted `div.children.length() > 0` for every prefix
  from index 1 onward (indices 2-5 in the loop, plus index 1 itself at
  the point of recording) — done, same test.
- [x] **Step 5:** Implemented as two separate tests (Design A's note
  requires two distinct claims, not one):
  `"streaming: ExprSpan identity stable across unclosed-to-closed growth"`
  (`<h1>{titl` → `<h1>{title` → `<h1>{title}`, the plan's literal
  example) and `"streaming: ExprSpan identity stable across closed-content
  growth"` (`<h1>{a}` → `<h1>{ab}` → `<h1>{abc}`, covering Design A's other
  required case — content mutating while the span stays closed at every
  step, which the unclosed→closed sequence never exercises). Both assert
  `ProjNode` id stability, confirming `@core.reconcile`'s `same_kind`-based
  identity preservation as designed.
- [x] **Step 6:** `moon test -p dowdiness/canopy/lang/jsx/proj` — done
  2026-07-11: 11/11 passed (8 from Task 2.2 + 3 streaming tests; 14/14
  after the Task 2.2 Step 2 close_bracket regression tests were added).

**Known coverage gap (Codex post-impl review, 2026-07-11, not fixed —
scope call, not an oversight):** the fixture/prefix list above is
prescribed verbatim by this plan and intentionally not extended. Codex
flagged that it doesn't exercise identity/span stability while an
*attribute* streams in (`<div cla` → `<div class="a"`) or while a
self-closing tag completes (`<div/` → `<div/>`). Both are real streaming
cases per Task 1.1's Design B, but neither is part of the plan's chosen
existence-proof fixture. Left as a documented gap rather than silently
expanding Task 2.4's locked scope; a future task should add it if a real
consumer needs attribute-level or self-close streaming guarantees.

### Acceptance Criteria (Phase 2)

- [x] `moon test -p dowdiness/canopy/lang/jsx/proj` passes, including the
      Task 2.4 streaming-reconciliation test — 11/11, 2026-07-11
- [x] `moon check` (workspace) clean — 2026-07-11, 0 errors (1
      pre-existing unrelated warning in `lang/lambda`, not touched by this
      work)
- [x] `moon info`, `git diff -- '*.mbti'` reviewed — 2026-07-11. Running
      `moon fmt`/`moon info` at the workspace root reformatted files in
      several *unrelated* submodules (`alga`, `event-graph-walker`,
      `graphviz`, `order-tree`, `rabbita`, `svg-dsl`) as a side effect of
      `moon.work`'s full-workspace fan-out (toolchain-skew line-wrap
      drift, no semantic change) — reverted with `git checkout -- .` in
      each before committing; only `lang/jsx/proj`'s own new
      `pkg.generated.mbti` is part of this change. See
      `reference_moon_fmt_workspace_cascade` memory.
- [x] No `lang/jsx/edits/` or `lang/jsx/companion/` package created —
      confirmed: `lang/jsx/` contains only `proj/`

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

### V1 contract: FFI sessions and empty-tag recovery (#886)

This section fixes the V1 implementation boundary. V1 solves same-session
projection identity for the JSX streaming demo; it does not introduce a
generic `ProjectionShape`, persistent cross-session identity, `Move`/
`Reparent` patches, or a general DOM transaction/rollback framework.

The stateful FFI surface is:

- `jsx_session_new(source, root_id) -> SessionCreateResult`, where the JSON
  result contains `handle` (a decimal opaque handle or `null`) and the initial
  `RenderResult` under `result`;
- `jsx_session_render(handle, source) -> RenderResult`;
- `jsx_session_dispose(handle) -> Unit`.

`SessionCreateResult` and `RenderResult` are JSON strings at the JavaScript
boundary. A successful creation publishes the handle only after the initial
render commits; a failed creation returns `handle: null`.

`jsx_parse_to_json` remains a stateless inspection API and makes no ID-stability
promise. The old `jsx_parse_and_render` API may remain as a compatibility
wrapper for one migration cycle, but it must not remain the owner of global
parser or DOM state.

The V1 result envelope is versioned and contains `schema_version`, `success`,
`revision`, `mounted_ids`, `diagnostics`, and `error`. `mounted_ids` are
decimal strings at the FFI boundary even though the internal `NodeId` remains
an integer. Recoverable parser diagnostics produce `success=true` when the
recovered projection is renderable; parse, projection, or render failures
produce `success=false`.

#### FFI session ownership and disposal

The FFI surface uses an opaque, per-renderer `JsxSession` handle. A session is
the identity boundary for one logical JSX stream; it is not a process-global
parser or renderer.

- The caller creates and owns the session. Creation supplies the initial source
  and the DOM root/container that the session is allowed to modify.
- The session owns the Loom parser, projection memo(s), previous projected tree,
  diagnostics state, mounted-node registry, and the identity allocation epoch.
  The caller never receives or stores the parser or memo separately.
- A render/update operation plans the source update, recovered projection, ID
  changes, and DOM patches as one candidate. Only a successful candidate and a
  successful DOM application advance the committed revision and mounted IDs.
  Recoverable diagnostics do not prevent a commit when the projection is
  renderable.
- Calls for one session are single-threaded and non-reentrant. Separate
  sessions may exist concurrently and must not share parsers, projection
  memos, mounted-node registries, or identity state.
- `NodeId` stability is guaranteed only between successful updates of the same
  live session. Independent `parse_to_proj_node`/inspection calls and newly
  created sessions allocate identity independently; equal numeric IDs may
  recur, but IDs have no cross-session persistence or ownership meaning.
- Disposal is explicit and idempotent. It unmounts nodes created by the session
  from the owned container, clears that session's registry, releases the parser
  and projection references, and invalidates the handle. A later update/render
  against the handle returns a structured disposed-session error; it never
  silently creates a replacement session.
- The compatibility reset disposes all live sessions and invalidates their
  handles; it does not recycle handles or preserve `NodeId`s. Stateful callers
  should use explicit dispose/create instead.
- A parse or projection failure does not advance the committed source,
  projection, identity allocation, revision, or mounted IDs. The session
  restores the parser to the last committed source, remains usable, and
  returns the rejected candidate's diagnostics together with the last
  committed revision and mounted IDs.
- V1 does not promise rollback for an arbitrary exception during DOM mutation.
  If DOM application fails after partial mutation, the session becomes
  `dirty`; the next successful render must remount the smallest supported
  mountable ancestor subtree before resuming incremental updates. A future
  version may replace this recovery path with detached-subtree staging or
  rollback.

The compatibility convenience function may retain a fresh-session,
stateless-inspection form, but it must not imply identity stability. The
stateful web path must migrate away from module-level parser and element
registries; the DOM root is caller-owned, while the session may remove only
nodes it created in that root.

#### Empty-tag recovery renderer behavior

`Element(tag="")` remains an explicit recovery projection node so the tree
inspector, source map, and diagnostics can account for the malformed source.
It is not a valid DOM element and is never passed to `document.createElement`.

The DOM renderer treats the recovery node as a transparent, non-mountable
wrapper:

- it emits no `MakeElement`, `SetAttrs`, or `Release` patch for the recovery
  node itself;
- it does not add the recovery node's ID to the mounted-ID set;
- its already-parsed children are visited under the recovery node's parent, with
  compacted sibling indexes, preserving visible streamed content;
- attributes on the empty-tag recovery node are ignored by the DOM renderer;
  their source and diagnostics remain available in the projection/inspector;
- an empty recovery node with no children produces no DOM operation.

When the recovery node becomes a valid tagged element, the renderer creates a
new mountable element and renders the recovered children beneath it. Because
the current patch protocol has no reparent operation, the affected descendant
subtree is remounted at this transition if it was previously mounted through
the transparent recovery context. V1 remounts the smallest supported
mountable ancestor subtree; it does not attempt to preserve descendant DOM
identity through this boundary. Identity preservation resumes normally on
subsequent updates of the valid element. This transition is therefore an
explicit exception to the ordinary same-kind identity guarantee and must have
its own regression test.

The same remount boundary is used for any element-tag change, including a
truncated valid tag such as `di` becoming `div`, because V1 has no reparent
patch and cannot safely move already-mounted descendants across a changed
element parent.

The contract is intentionally suppressive rather than placeholder-rendering:
incomplete markup must not add visual chrome to the user's generated UI. The
tree/debug view may still label the node as a recovery element, and diagnostics
remain the user-visible explanation for the missing tag.

#### Required acceptance tests

- Two live sessions render independently without cross-session IDs or DOM
  registry leakage.
- Initial render commits as revision 1; failed initial render publishes no
  usable handle and leaves the root untouched.
- Disposal removes only the session's mounted nodes, is safe to call twice, and
  rejects later updates.
- Recoverable diagnostics return success with diagnostics; rejected candidates
  return failure with the previous committed revision and mounted IDs.
- A recoverable empty-tag node emits no invalid-element patch while its children
  remain visible under the original parent.
- Empty-tag recovery transitioning to a valid tag creates a valid element and
  remounts the smallest supported mountable ancestor subtree.
- A simulated DOM-application failure marks the session dirty and the next
  successful render repairs the affected subtree before incremental updates
  resume.
- Stateless inspection documents fresh-ID semantics, while successive updates
  through one session preserve unaffected same-kind IDs.

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

- Related loom issues: #626 (RawText emission, OPEN as of 2026-07-10), #609
  (M19 capstone, OPEN as of 2026-07-10), #532 (lex-mode API, CLOSED/shipped),
  #646 (tcc hang, CLOSED — root cause found and fixed by loom PR #647, see
  the 2026-07-10 Task 0.1 resolution note below, not just a CI workaround as
  originally suspected).
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
- **2026-07-10, Task 1.1 Step 1/2 design, round 2 (Opus, revised after
  Codex round-1 verdict `needs-rework` — see the round-1 verdict and the
  round-2 confirmation entries below this block for the full record).**
  This replaces the round-1 draft in place; round-1's text is preserved
  only in git history, not duplicated here, per this project's
  documentation conventions (docs are the current truth, not a changelog
  of drafts).

  ### Design A — embedded-expression mode switch

  **Mechanism:** `ModeLexer[Token, JsxLexMode]`
  (`loom/loom/core/mode_lexer.mbt`), not `set_lex_mode` — confirmed again
  this session that `set_lex_mode` has no working lex/parse feedback
  consumer in loom, and `ModeLexer` is the mechanism `examples/markdown`
  already ships with (`markdown_mode_lexer`, `loom/examples/markdown/lexer.mbt`).
  `tokenize_with_modes`/`ModeRelexState`/`relex_from` give incremental
  re-lex for free, which the streaming use case needs regardless of the
  mode-switch design itself.

  **Mode shape** (data folded into the mode value, following the
  `CodeBlock(fence_len)` and `HtmlBlockUntil(delimiter)` precedent in
  `markdown/lexer.mbt` — `M` is a free type parameter, so it can carry an
  `Int` and a nested enum, not just a bare tag):

  ```
  enum JsxLexMode {
    Children
    TagBody   // between the tag name and `>`/`/>`: scanning for the next
              // attribute name or the tag close — the one concrete mode
              // an attribute-value expression always resumes into
    JsExprRaw(depth~ : Int, origin~ : ExprOrigin)
    JsExprString(quote~ : Char, depth~ : Int, origin~ : ExprOrigin)
  }
  enum ExprOrigin { FromChildren; FromAttrValue }
  ```

  (Names illustrative — Task 1.2 Step 1 owns the actual `token.mbt`/mode
  enum wiring; this fixes the *shape*, not the identifiers.)

  **Scope boundary, corrected after Codex round 2 (round 1's `AttrValue`
  label was a bare tag with no real content — Codex round 2 correctly
  called this a relabeling, not a fix, so `TagBody` above is now the
  actual, singular, concrete resume mode, not a placeholder name):**
  `Children`/`TagBody` are the two modes relevant to the `{}` mode switch
  specifically, not the full JSX tag/attr lexer state machine — how
  `TagBody` itself recognizes an attribute name vs. `>`/`/>` (i.e.
  whether it needs internal sub-states of its own, mirroring
  `examples/html/lexer.mbt`'s `read_open_tag_body` cursor loop) is Task
  1.2's mechanical implementation detail, not a Task 1.1 design question
  — the point Task 1.1 must fix, and now does, is that there is exactly
  **one** resume mode (`TagBody`) for every attribute-value expression
  exit, so `origin=FromAttrValue`'s exit target is unambiguous without
  needing to carry a nested resume mode value.

  - **Trigger:** lexer sees `{` while mode is `Children` or `TagBody` →
    transitions to `JsExprRaw(depth=1, origin=FromChildren|FromAttrValue)`
    (origin recorded from whichever mode was active at the `{`).
  - **Exit:** matching `}` at `depth == 1` (about to close, i.e. the
    outermost `{`) transitions back to `Children` (if `origin=FromChildren`)
    or `TagBody` (if `origin=FromAttrValue`) — a direct match on the
    `origin` tag, not a stored nested mode, since `TagBody` is the one
    and only concrete resume state for the attribute-value case. This is
    *why* `origin` is carried in the mode value alongside depth, not just
    depth alone: nothing else at the point of the closing `}` knows which
    of the two fixed targets to resume.
  - **Depth tracking:** folded into the mode value itself
    (`JsExprRaw(depth~, ..)`), not a side counter reconstructed by
    `fold_node`. Reason: `ModeLexer`'s `lex_step` is a pure function of
    `(input, pos, mode)` — nothing outside the mode value is visible to
    the next step call. More importantly, `tokenize_with_modes` records
    "the mode BEFORE each token" into a parallel array specifically so
    `relex_from`'s convergence check has a complete lexer-state snapshot
    at every token boundary; a counter that lived outside the mode (e.g.
    reconstructed later from the token stream) would be invisible to that
    contract and would break incremental re-lex correctness, not just be
    inelegant. On `{` inside `JsExprRaw`, depth increments (still
    `origin`-tagged); on `}` at depth > 1, depth decrements and mode stays
    `JsExprRaw`; only depth == 1 exiting on `}` leaves the expression.
  - **String-literal awareness (`"`/`'` only — see template-literal
    scoping below):** on `"` or `'` while in `JsExprRaw(depth, origin)`,
    transition to `JsExprString(quote, depth, origin)` (depth carried
    through unchanged — string content never participates in brace
    counting). Inside `JsExprString`, a `\` consumes itself plus the next
    character unconditionally (mirrors `examples/html/lexer.mbt`'s
    `read_attr_value` escape handling), and the matching unescaped
    `quote` returns to `JsExprRaw(depth, origin)`. Verified correct for
    `{"a}b"}` and `attr={cond ? "a}" : "b"}` — the `}` inside the string
    never reaches the depth counter.
  - **Template literals (`` ` ``) are explicitly out of scope for Phase
    1's correct handling, not silently mis-tokenized.** Codex's
    round-1 review found that treating `` ` `` identically to `"`/`'`
    (scan for the next unescaped backtick, ignore everything between)
    mis-balances on nested substitutions — `` {`${`x`}`} `` has an inner
    backtick that gets mistaken for the outer literal's close, letting
    its `${}` region's `}` close the JSX expression early. Real JS-aware
    template handling needs a *stack* of "in template text" /
    "in `${...}` substitution" states (each `${` inside template text
    pushes back into brace-counted expression scanning, each matching
    `}` pops), which is genuine recursive nesting the opaque-blob
    philosophy elsewhere in this design deliberately avoids. Phase 1's
    answer: the lexer still recognizes `` ` `` and enters
    `JsExprString('`', depth, origin)`, but does **not** special-case
    `${` inside it — a raw `` ` `` is a plain opaque-content delimiter,
    same rule as `"`/`'`. Any `{...}` value containing a nested
    backtick-inside-backtick or a `${...}` substitution that itself
    contains a backtick-delimited string will mis-tokenize (produces a
    wrong span or a spurious "unclosed expression" diagnostic, not a
    silent wrong-but-plausible parse). This is a stated Phase 1
    limitation with a concrete failure mode, not a silent gap — nested
    template substitutions are common enough in real JSX that this
    should be revisited before Phase 1 is called done for anything
    beyond the plan's own examples, but implementing the full stack
    machine now is out of scope for this pass.
  - **Comments and regex literals inside `{...}` are also out of scope
    and will corrupt depth counting** (`{ /* } */ x }`, `{ // }\nx }`,
    `{ /}/.test(x) }`) — braces inside `//`/`/* */` comments or regex
    literals are not string-delimited, so this design's `"`/`'`-only
    escaping does not protect them. Stated as an explicit Phase 1
    limitation (same category as template literals above): the plan's
    own JSX examples do not require comment/regex support inside `{}`,
    and adding a full JS-lexical-aware scanner (distinguishing regex
    from division, tracking comment state) is disproportionate scope for
    Phase 1's opaque-span design. Track as a follow-up if real usage
    hits it.
  - **Nested JSX inside `{...}`** (e.g. `{cond ? <a/> : <b/>}`): stays one
    opaque blob under this design — the lexer/parser never leaves
    `JsExprRaw`/`JsExprString` to re-enter `Children`/tag-parsing.
    Consequence, stated explicitly per the plan's instruction: JSX
    conditionally-rendered inside `{...}` (a common real LLM-JSX pattern)
    gets no incremental visible growth *inside* the expression — only the
    `ExprSpan`'s boundaries move. Accepted as a Phase 1 limitation.
    **Scope of this limitation, widened after a 2026-07-10 post-commit
    review (not a Codex round, a direct value-fit check against the
    plan's own generative-UI premise):** the plan's wording above singles
    out conditional rendering (ternaries) as the flagged example, but the
    dominant real-world instance of "JSX nested inside `{...}`" for
    generative-UI output is **`.map()`-driven list rendering**
    (`{items.map(item => <Card key={item.id}>{item.name}</Card>)}`) —
    table rows, chat messages, card grids — not ternaries. Brace-depth
    counting still finds the correct outer `}` for this pattern (the
    braces inside a `.map()` callback are textually balanced, same as any
    other nested-brace JS), so the *lexer* is not at risk here. The
    limitation is that this pattern is also swallowed whole into one
    `ExprSpan`, meaning the specific content Phase 1's "incremental
    visible growth" value proposition is meant to showcase — list items
    or cards appearing one at a time as an LLM streams them — gets only
    boundary-level growth (the whole blob's span moves), not per-item
    incremental structure. Phase 1 still delivers real value for static
    scaffolding (headers, containers, text/attribute character-by-
    character streaming), but that is a narrower slice of realistic
    generative-UI output than "conditional-rendering-heavy" suggests.
    This does not change Phase 1's scope or defer anything further —
    Phase 3 (`## Phase 3 — Deferred`) already defers "JS expression
    evaluation of `{...}` spans" and the component-registry rendering
    surface, which is where recursing into `.map()`-returned JSX would
    eventually have to live — but it should be weighed honestly when
    deciding whether to continue past Phase 1, not discovered later as a
    surprise gap between what shipped and what the plan's premise
    implied.
  - **Growing opaque `ExprSpan` identity — corrected after Codex round 1
    (the original draft's justification was factually wrong, not just
    under-specified):** the *CST* node for a growing `{fo` → `{foo` →
    `{foo}` span is expected to re-parse on each edit — that's normal
    loom behavior and not itself a problem. `ReuseCursor`'s structural
    reuse does **not** apply here as originally claimed: `ReuseCursor`
    only reuses a node that sits wholly *outside* the edit's damage
    range with matching leading/trailing token context, and a span
    that's actively growing at its own tail is exactly the
    left-adjacent-to-damage case `ReuseCursor` conservatively declines to
    reuse (per loom's own reuse contract — a node ending where damage
    starts is not "outside damage"). Claiming `ReuseCursor` gives content
    mutation without a new node was the wrong mechanism.
    The real answer lives one layer up: identity stability for
    `ExprSpan` is a **projection-level** guarantee via
    `@core.reconcile`, which preserves an old `ProjNode`'s ID across a
    CST re-parse when `TreeNode::same_kind(old.kind, new.kind)` holds for
    the corresponding node — i.e. as long as the re-parsed node is still
    kind-tagged `ExprSpan`, projection reconciliation keeps the same
    `ProjNode` ID even though the underlying CST node is a fresh parse
    with different raw content. This is the same category of guarantee
    Task 2.4 records for first-appearance-while-unclosed identity
    elsewhere in this plan, but it is `@core.reconcile`'s job, not
    `ReuseCursor`'s — the two are different layers (CST structural reuse
    vs. projection kind-based identity) and this design should not
    conflate them again. **Required before Task 1.2's tests are called
    complete:** a projection-layer test asserting the `ExprSpan`
    `ProjNode` ID is stable across `{fo}` → `{foo}` → `{foo}` growth, and
    a second asserting stability across an *unclosed* prefix growing
    into a closed one (`{fo` → `{foo` → `{foo}`), not just the
    already-closed case.

  ### Design B — error recovery on a streaming JSX prefix

  Baseline precedent verified by reading `loom/examples/html/cst_parser.mbt`
  directly this session (`parse_content`/`finish_element`, lines ~110–173):
  html's element-content loop (`while !ctx.at_eof() { match ctx.peek() { ... } }`)
  keeps emitting child nodes as normal CST children of the currently-open
  element regardless of whether a matching close tag ever arrives; on EOF
  it calls `ctx.error("Unclosed element: " + tag_name)` — a diagnostic
  push, not a control-flow branch that discards anything — and the caller
  (`parse_element`) unconditionally calls `ctx.finish_node()` right after,
  so the CST node closes normally with every already-parsed child intact.
  JSX's design below is this same shape applied to JSX's four cases, not a
  new invention.

  1. **Fully closed tree** — baseline, not interesting (per plan).
  2. **Open elements, no matching close yet** (`<div><span>text`): follow
     html's precedent exactly — `parse_jsx_content`'s loop runs until a
     matching close tag, `/>`, or EOF; on EOF it pushes
     `ctx.error("Unclosed JSX element: <" + tag_name + ">")` and the
     caller still calls `ctx.finish_node()` unconditionally. The `Element`
     CST/AST node therefore always contains its already-seen children —
     it is never replaced by a content-discarding error node. Stated as a
     hard CST-shape requirement per the plan's instruction, because
     Phase 2's read-only projection rendering depends on it for
     incremental visible growth.
  3. **Truncated tag mid-token** (`<div cla`, `<di`): split into two
     sub-cases, because they need different answers.
     - *Identifier-like truncation* (tag name, attribute name cut off
       mid-word, no trailing delimiter expected): the lexer's
       `take_while`-style identifier scan is naturally EOF-safe — it just
       stops at end of input and emits a best-effort partial token (e.g.
       `TagName("di")`) with no synthetic error token needed at the lex
       level. The truncation surfaces one level up, at the parser: it
       reaches EOF still inside tag-open state, never having seen `>` or
       `/>`. This is not a distinct lexer contract; it's the same
       "loop until sync point or EOF" shape as case 2, just inside
       `parse_open_tag` instead of `parse_content`. Corrected after Codex
       round 1: give `parse_open_tag` its **own explicit EOF branch**
       (`ctx.error("Truncated tag: <" + partial_name + ">")` then finish
       the node directly) rather than routing through the generic
       `skip_until`-based recovery loop for the EOF case specifically —
       `skip_until` guarantees "don't consume past a sync point," not
       "make progress," and html's own `parse_html_root` needed
       `skip_until_progress` instead to avoid spinning when already
       sitting on a sync token (loom PR #647, see the 2026-07-10 Task 0.1
       note below). Reserve `skip_until`/`skip_until_progress` for the
       *non-EOF* recovery case inside `parse_open_tag` (an unexpected
       token that isn't EOF) — `is_sync_point` for JSX must include `EOF`
       explicitly either way, matching html's set, so the loop can still
       terminate if it does fall through to the generic path. Codex round
       2 correctly flagged that this left the non-EOF branch's actual
       progress invariant unstated, so: **use `skip_until_progress`, not
       plain `skip_until`, for the non-EOF branch too** — the same reason
       html needed it at the root applies identically inside
       `parse_open_tag` (an unexpected-but-non-EOF token can itself
       already be sitting on a sync point, e.g. an unexpected `>` — mirror
       is_sync_point's exact membership from html's tag-open recovery, not
       a JSX-specific set), and `parse_open_tag` must not call plain
       `skip_until` anywhere in its non-EOF path. This makes the rule
       uniform across both branches: EOF gets its own direct
       diagnose-and-finish exit (no recovery loop needed since there's
       nothing left to skip past), everything else goes through
       `skip_until_progress`, never plain `skip_until`.
     - *Quoted-value truncation* (`attr="unterminated`, no closing quote
       before EOF): needs a lexer-level signal, mirroring
       `examples/html/lexer.mbt`'s `read_attr_value`. Corrected after
       Codex round 1: do **not** rely on `ModeLexer`'s generic
       `LexStep::Incomplete` auto-recovery for this — `Incomplete`
       (per `push_recovered_mode_step`) emits a single synthetic
       *error* token spanning `[at, EOF)` and a diagnostic, which loses
       the actual scanned text as normal content. Since case 2's hard
       requirement is "already-seen content stays visible," the lexer
       must instead emit the partial value as a **normal `Produced`
       token** of a distinct kind — e.g. `AttrStringLitUnterminated(text)`
       alongside the existing `AttrStringLit(text)` for the well-formed
       case — so the raw scanned characters reach the CST/AST like any
       other content. The *parser*, on seeing
       `AttrStringLitUnterminated`, is what pushes
       `ctx.error("Unterminated attribute string literal")`; the
       diagnostic is a parser-level annotation on top of a normal token,
       not a framework-injected error token that replaces it.
  4. **Truncated embedded expression** (`{foo.bar(`, no matching `}` yet):
     same "eager partial emission, never guess" shape as case 2/3 — do
     not defer node emission until `}` arrives. Corrected after Codex
     round 1: "slice `ctx` source positions into the AST node" is not
     itself a CST construction mechanism — `ExprSpan` needs real tokens
     so the parser can assemble it the same way `parse_content` assembles
     an `Element`'s children, not a special-cased leaf. Concretely:
     lexer emits an `ExprOpen` token for the triggering `{`, then zero or
     more `ExprRawText` tokens (each a `Produced` chunk of raw content —
     one chunk per contiguous run between mode transitions, i.e. a run
     ends where `JsExprString` begins/ends so string-boundary crossings
     don't get silently merged into one opaque blob the parser can't
     inspect for diagnostics), then either `ExprClose` (`}` at depth 1)
     or nothing (EOF while still inside `JsExprRaw`/`JsExprString`). The
     parser builds the `ExprSpan` CST node from `ExprOpen` +
     accumulated `ExprRawText` children exactly as `parse_content` builds
     an `Element` from its children — on EOF without `ExprClose`, it
     pushes `ctx.error("Unclosed expression: missing '}'")` and finishes
     the node anyway with whatever `ExprRawText` children were already
     collected, mirroring case 2's "diagnostic doesn't gate node
     creation" rule exactly, now on a real shallow subtree instead of a
     hand-waved leaf. **Gap Codex round 2 found:** this token stream lets
     the parser diagnose "missing `}`" (no `ExprClose` seen) but gives it
     no way to independently know EOF happened *inside a string*
     specifically (`{ "x` vs. `{foo.bar(` are indistinguishable from
     `ExprRawText` chunks alone, since mode boundaries aren't exposed).
     Fix: when EOF hits while mode is `JsExprString(quote, ..)`
     specifically (as opposed to plain `JsExprRaw`), the lexer emits the
     accumulated partial string content as a distinct
     `ExprStringUnterminated` token kind (same "preserve content, don't
     replace with a synthetic error token" rule as
     `AttrStringLitUnterminated` above) instead of a plain
     `ExprRawText`. The parser, on seeing `ExprStringUnterminated` as the
     last child before EOF, pushes a second, additive diagnostic
     ("Unterminated string literal in expression") alongside — not
     instead of — the "missing `}`" one, since both are independently
     true and independently detectable once the token kind distinguishes
     the two truncation shapes. This token's raw text still folds into
     `ExprSpan`'s concatenated content exactly like any other
     `ExprRawText` chunk — only the diagnostic-triggering is different,
     not the AST shape.

  **Step 3 (external validation), round 1 — Codex, 2026-07-10.**
  Verdict: **needs-rework**. Findings (all applied above in this same
  entry, so Designs A/B above already reflect the fixes — nothing further
  to change from round 1's findings):
  1. Template-literal nesting (`` {`${`x`}`} ``) mis-balances depth under
     the original "treat `` ` `` like `"`/`'`" rule — fixed by explicitly
     scoping template literals as an out-of-scope Phase 1 limitation with
     a stated concrete failure mode (see Design A above), not silently
     mis-tokenizing.
  2. Comments/regex literals inside `{...}` also corrupt depth counting
     and weren't mentioned at all — added as a second explicit Phase 1
     limitation.
  3. The mode enum didn't specify how `origin=FromAttrValue`'s exit
     re-enters tag-body lexing — added the scope-boundary note clarifying
     this is Task 1.2's mechanical extension, with the return-target
     requirement stated explicitly.
  4. `Incomplete` was the right `LexStep` classification but its actual
     behavior (single synthetic error token, content not preserved)
     contradicted case 2's "content stays visible" requirement — fixed
     by emitting partial content as a normal token
     (`AttrStringLitUnterminated`) instead of relying on the framework's
     auto-recovery token.
  5. The original `ReuseCursor`-based identity justification was
     factually wrong (damage-adjacency makes it inapplicable to a
     growing span) — replaced with the correct mechanism,
     `@core.reconcile`'s kind-based `ProjNode` ID preservation, plus two
     required tests.
  6. `skip_until` was conflated with `skip_until_progress`'s
     progress-guarantee — fixed by giving `parse_open_tag` its own
     explicit EOF branch instead of relying on the generic recovery loop
     for that case.
  7. Case 4's "slice ctx source positions" leaf-construction was
     hand-wavy given `ExprSpan` isn't actually a bare token — fixed by
     defining real `ExprOpen`/`ExprRawText`/`ExprClose` tokens so the
     parser assembles it like any other subtree.

  Additional edge cases Codex surfaced that weren't in the plan's
  original enumeration — recorded here as required test cases for Task
  1.2 Steps 3/4, not solved further at the design-prose level:
  - Unterminated string/template inside an expression (`{ "x`, `` {`abc``):
    decide whether the diagnostic reports "missing `}`" only, or also
    "missing closing quote/backtick" — Task 1.2 should emit both when
    both are true, since they're independently detectable from the
    `AttrStringLitUnterminated`-style token plus the missing `ExprClose`.
  - Escaped-backslash runs and EOF immediately after a trailing
    backslash (`{"\\\\}"}`, `{"x\\`) — exercises the escape-consumes-next-
    char-unconditionally rule at the EOF boundary specifically.
  - `attr={f()} b="c">` and `attr={f()}/>` — validates that
    `origin=FromAttrValue`'s exit correctly resumes tag-body scanning for
    a following attribute or tag close, not just end-of-input.
  - A stray `}` encountered while *not* inside any `JsExprRaw` (i.e. in
    `Children` or tag-body mode) — Task 1.2 must decide and test whether
    this is silently treated as literal text or produces a diagnostic;
    this design doc does not yet pick one, flagged for Task 1.2 Step 3/4
    rather than left implicit.

  **Step 3, round 2 (confirmation) — Codex, 2026-07-10.** Verdict:
  **needs one more fix pass** (not a fresh needs-rework — 5 of 7 round-1
  fixes confirmed RESOLVED outright: template-literal scoping,
  comments/regex scoping, `AttrStringLitUnterminated`-as-normal-token,
  `@core.reconcile`/`same_kind` identity mechanism — verified to actually
  exist in `core/reconcile.mbt` and `loom/loom/core/proj_traits.mbt` —
  and the `ExprOpen`/`ExprRawText`/`ExprClose` chunking not contradicting
  the opaque-leaf framing). 3 gaps remained and are now fixed in Designs
  A/B above, in the same edit that added this entry:
  1. `origin=FromAttrValue`'s exit target was relabeled, not resolved —
     `AttrValue` carried no real content of its own. Fixed by replacing
     it with `TagBody`, the one concrete resume mode, and rewriting
     Trigger/Exit to name it directly instead of a placeholder label.
  2. `parse_open_tag`'s non-EOF recovery branch left its progress
     invariant unstated (still capable of the same no-progress hazard
     `skip_until_progress` exists to fix). Fixed by requiring
     `skip_until_progress` uniformly for that branch, never plain
     `skip_until`, with EOF handled by its own separate direct exit.
  3. New gap this round exposed rather than introduced: case 4's token
     stream could report "missing `}`" but had no way to independently
     detect "EOF happened mid-string" (`{ "x` vs `{foo.bar(`
     indistinguishable from `ExprRawText` alone). Fixed by adding a
     distinct `ExprStringUnterminated` token kind, emitted only when EOF
     hits inside `JsExprString` specifically, driving an additive second
     diagnostic alongside the missing-`}` one.
  With these three applied, Designs A/B are considered validated per this
  project's Algorithm Implementation Process — Task 1.2 may begin
  (Step 4 below records this).
- **2026-07-10, Task 0.1 resolution:** #646 was already fixed upstream before
  this session picked up Phase 0 — loom PR #647 (merged 2026-07-07) replaced
  `parse_html_root`'s recovery from `skip_until` to `skip_until_progress`,
  fixing a genuine parser bug (a mismatched close tag left a `CloseTag` sync
  point at the root that `skip_until` never advanced past, spinning the
  `while !ctx.at_eof()` loop forever — not an upstream tcc issue as the
  original issue speculated). PR #649 (merged 2026-07-08) re-added
  `examples/html`/`css`/`graph-dsl`/`moonbit` to loom's CI `test-modules`
  matrix on `--target native`. Verified empirically this session: the fix
  commit (`ca7aa2e`) is an ancestor of canopy's pinned loom commit
  (`2c369ae2`), and `NEW_MOON_MOD=0 moon test -p dowdiness/html --target
  native` from `loom/examples/html/` completes in ~1s, 23/23 passed, no
  tcc spin. No further investigation needed — Task 0.1 is closed as
  already-resolved, not re-derived. (Note: an unscoped `moon test` from
  within `examples/html/` still cascades to the full workspace per
  `moon.work` semantics and hit an unrelated pre-existing abort in
  `lambda/typecheck` — out of scope for this plan, use `-p dowdiness/html`
  as Step 2 already specifies.)
