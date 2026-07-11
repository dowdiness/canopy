# Pretty-Printer Engine for Canopy

## Why

Canopy currently has Show/Debug for stringifying types, and a single-line
`TermSym for Pretty` interpretation for Lambda AST. These are insufficient for
a structural editor:

- **No width-aware layout** — all output is single-line or manual `\n` joins
- **No annotations** — output is plain strings, can't carry syntax categories or
  node identity for editor rendering
- **No JSON pretty-printer** — JsonValue has no formatted output at all
- **Debug output is verbose** — large ASTs are unreadable in tests/diagnostics
- **Error messages are flat strings** — no structure, no source context

A proper pretty-printer is foundational for the editor's UI/UX (formatted code
display, hover info, diagnostic messages) and for developer experience
(REPL, test output, debugging).

## Scope

In:
- `canopy/pretty/` — new package: Layout engine, combinators, renderers
- `lang/lambda/proj/pretty_layout.mbt` — TermSym interpretation
- `lang/json/proj/pretty_layout.mbt` — JSON AST pretty-printing

Out:
- Error/diagnostic reporting system (uses the engine, designed separately)
- CRDT state inspection (uses the engine, designed separately)
- Πe cost-factory extension (future; engine designed for it but not implemented)
- Web editor integration (uses `render_spans`, wired separately)

## Current State

- `loom/examples/lambda/src/ast/sym.mbt`: `TermSym for Pretty` produces
  single-line strings via `struct Pretty { repr: String }`
- `loom/examples/lambda/src/ast/ast.mbt`: `print_term()` uses the Pretty
  interpretation via `replay`
- `@debug.to_string(ast)`: verbose constructor-style output
- No width control, no layout choices, no annotations

## Desired State

- A Wadler-Lindig pretty-printing engine in `canopy/pretty/` with:
  - Generic `Layout[A]` document type parameterized over annotations
  - Standard combinators: `text`, `line`, `hardline`, `softline`, `nest`,
    `group`, `annotate`, `bracket`, etc.
  - Width-aware layout resolution (greedy group flattening)
  - Two renderers: `render_string` (plain text) and `render_spans` (annotated)
- TermSym integration via `PrettyLayout` wrapper type in `lang/lambda/proj/`
- JSON pretty-printing via the same pattern in `lang/json/proj/`
- `Cmd[A]` intermediate command stream separating layout resolution from output

## Design

### Algorithm

Wadler-Lindig with greedy group flattening. Start with Wadler, design for
extensibility toward Πe ("A Pretty Expressive Printer", Porncharoenwase,
Pombrio, Torlak, OOPSLA 2023) via pluggable layout resolver.

**References:**
- Wadler, "A prettier printer" (1998)
- Porncharoenwase et al., "A Pretty Expressive Printer" (OOPSLA 2023)

### Package Structure

```
canopy/pretty/
  layout.mbt           Layout[A] enum (8 constructors)
  combinators.mbt      text, line, nest, group, annotate, bracket, etc.
  ann.mbt              Ann, SyntaxCategory, Span
  render.mbt           Wadler layout algorithm: resolve() -> Array[Cmd[A]]
  render_string.mbt    render_string(layout, width~) -> String
  render_spans.mbt     render_spans(layout, width~) -> Array[(Span, A)]
  moon.pkg.json        depends on: framework/core (for NodeId)

lang/lambda/proj/
  pretty_layout.mbt    impl TermSym for PrettyLayout

lang/json/proj/
  pretty_layout.mbt    JSON AST -> Layout[Ann]
```

### Core Types

```moonbit
// Layout[A] — generic document tree
pub enum Layout[A] {
  Empty
  Text(String)
  Line                    // space in flat mode, newline in broken mode
  HardLine                // always newline
  Nest(Int, Layout[A])
  Concat(Layout[A], Layout[A])
  Group(Layout[A])        // try flat, fall back to broken
  Annotate(A, Layout[A])  // attach metadata to a subtree
} derive(Show, Eq)

// Rendering mode — used internally by the layout algorithm
priv enum Mode {
  Flat    // inside a group that fits — Line becomes space
  Break   // normal mode — Line becomes newline + indent
}

// Annotation for editor rendering
// pub(all) so lang packages can construct Ann values directly
pub(all) struct Ann {
  category : SyntaxCategory
  node_id : @core.NodeId?       // @core = dowdiness/canopy/framework/core
} derive(Show, Eq)

pub enum SyntaxCategory {
  Keyword; Identifier; Number; StringLit
  Operator; Punctuation; Comment; Error
} derive(Show, Eq)

// Span in rendered output
pub(all) struct Span {
  start : Int
  end : Int
} derive(Show, Eq)

// Intermediate command stream
pub enum Cmd[A] {
  CText(String)
  CNewline(Int)       // newline + indent spaces
  CAnnStart(A)
  CAnnEnd(A)
} derive(Show, Eq)
```

The `moon.pkg.json` for `canopy/pretty/` imports framework/core as `@core`:
```json
{
  "import": [
    { "path": "dowdiness/canopy/framework/core", "alias": "core" }
  ]
}
```

### Combinators

```moonbit
pub fn text[A](s : String) -> Layout[A]
pub fn char[A](c : Char) -> Layout[A]
pub fn line[A]() -> Layout[A]                 // space or newline
pub fn hardline[A]() -> Layout[A]             // always newline
pub fn softline[A]() -> Layout[A]             // empty or newline (= group(line()))
pub fn nest[A](indent~ : Int = 2, doc : Layout[A]) -> Layout[A]
pub fn group[A](doc : Layout[A]) -> Layout[A]
pub fn concat[A](l : Layout[A], r : Layout[A]) -> Layout[A]
pub fn annotate[A](ann : A, doc : Layout[A]) -> Layout[A]
pub impl[A] Add for Layout[A] with add        // + operator
pub fn separate[A](sep : Layout[A], docs : Array[Layout[A]]) -> Layout[A]
pub fn surround[A](l : Layout[A], r : Layout[A], doc : Layout[A]) -> Layout[A]
pub fn parens[A](doc : Layout[A]) -> Layout[A]
pub fn brackets[A](doc : Layout[A]) -> Layout[A]
pub fn braces[A](doc : Layout[A]) -> Layout[A]
pub fn bracket[A](l : String, r : String, doc : Layout[A]) -> Layout[A]
```

### Layout Algorithm

Two-pass architecture:
1. `resolve(width, layout) -> Array[Cmd[A]]` — Wadler layout resolution
2. `cmds -> String` or `cmds -> Array[(Span, A)]` — output formatting

```moonbit
// Layout resolution: recursive tree traversal, column-threaded.
// Mode (Flat/Break) is defined in Core Types above.
pub fn resolve[A](width : Int, layout : Layout[A]) -> Array[Cmd[A]] {
  let cmds : Array[Cmd[A]] = []
  fn go(indent : Int, mode : Mode, column : Int, lay : Layout[A]) -> Int {
    match lay {
      Empty => column
      Text(s) => { cmds.push(CText(s)); column + s.length() }
      Line => match mode {
        Flat => { cmds.push(CText(" ")); column + 1 }
        Break => { cmds.push(CNewline(indent)); indent }
      }
      HardLine => { cmds.push(CNewline(indent)); indent }
      Nest(i, doc) => go(indent + i, mode, column, doc)
      Concat(l, r) => {
        let col = go(indent, mode, column, l)
        go(indent, mode, col, r)
      }
      Group(doc) => {
        let m = if flat_width(doc) <= width - column { Flat } else { Break }
        go(indent, m, column, doc)
      }
      Annotate(ann, doc) => {
        cmds.push(CAnnStart(ann))
        let col = go(indent, mode, column, doc)
        cmds.push(CAnnEnd(ann))
        col
      }
    }
  }
  let _ = go(0, Break, 0, layout)
  cmds
}

// Flat width computation for group decisions
fn flat_width[A](layout : Layout[A]) -> Int {
  match layout {
    Empty => 0
    Text(s) => s.length()
    Line => 1
    HardLine => -1           // can't flatten
    Nest(_, doc) => flat_width(doc)
    Concat(l, r) => {
      let lw = flat_width(l)
      guard lw >= 0 else { -1 }
      let rw = flat_width(r)
      guard rw >= 0 else { -1 }
      lw + rw
    }
    Group(doc) => flat_width(doc)
    Annotate(_, doc) => flat_width(doc)
  }
}
```

### Renderers

```moonbit
// Plain text — ignores annotations
pub fn render_string[A](layout : Layout[A], width~ : Int = 80) -> String

// Annotated spans — for editor rendering
pub fn render_spans[A](layout : Layout[A], width~ : Int = 80) -> Array[(Span, A)]
```

`render_spans` uses `for cmd in cmds; offset = 0 { ... } nobreak { spans }`
to thread offset as a functional loop variable.

### TermSym Integration

```moonbit
// lang/lambda/proj/pretty_layout.mbt

pub struct PrettyLayout {
  layout : @pretty.Layout[@pretty.Ann]
}

// Convenience constructors for Ann (using pub(all) struct fields)
fn ann_plain(category : @pretty.SyntaxCategory) -> @pretty.Ann {
  { category, node_id: None }
}

fn ann_node(category : @pretty.SyntaxCategory, id : @core.NodeId) -> @pretty.Ann {
  { category, node_id: Some(id) }
}

// Helper functions for annotated text fragments
fn kw(s : String) -> @pretty.Layout[@pretty.Ann]       // Keyword
fn ident(s : String) -> @pretty.Layout[@pretty.Ann]    // Identifier
fn num(s : String) -> @pretty.Layout[@pretty.Ann]      // Number
fn op(s : String) -> @pretty.Layout[@pretty.Ann]       // Operator
fn punc(s : String) -> @pretty.Layout[@pretty.Ann]     // Punctuation

// TermSym interpretation — each AST construct maps to Layout[Ann]
pub impl TermSym for PrettyLayout with lit(n) { ... }
pub impl TermSym for PrettyLayout with lam(x, body) { ... }
pub impl TermSym for PrettyLayout with app(f, arg) { ... }
pub impl TermSym for PrettyLayout with add(l, r) { ... }
pub impl TermSym for PrettyLayout with if_(cond, then_, else_) { ... }
pub impl TermSym for PrettyLayout with let_(x, val, body) { ... }
```

Usage via the existing replay pipeline:
```moonbit
let pl : PrettyLayout = replay(term)
@pretty.render_string(pl.layout, width=80)    // REPL
@pretty.render_spans(pl.layout, width=80)     // editor
```

### Future Annotation Candidates

These don't require engine changes — each defines its own annotation type
and uses `Layout[ThatType]` independently.

| Category | Annotations | When needed |
|----------|------------|-------------|
| Editor interaction | Selectability, editability, cursor targets | Structural editing UX |
| Diagnostics | Severity (error/warn/info/hint), message, related spans | Error reporting |
| Semantic | Hover content, link targets, scope visualization | IDE-like features |
| Collaboration | Authorship, diff markers | Multi-user editing |
| Structural | Foldability, placeholder/hole markers | Code folding |

### Πe Extension Path

1. Add `Choice(Layout[A], Layout[A])` constructor to `Layout[A]`
2. Replace `flat_width(doc) <= width - column` in `resolve` with a pluggable
   cost factory
3. No changes to combinators, renderers, or TermSym integrations

## Steps

1. Create `canopy/pretty/` package with `moon.pkg.json`
2. Implement `Layout[A]` enum and combinators
3. Implement `Ann`, `SyntaxCategory`, `Span`
4. Implement `Cmd[A]`, `flat_width`, `resolve`
5. Implement `render_string`
6. Implement `render_spans`
7. Add tests: combinators, layout resolution, string rendering, span rendering
8. Implement `PrettyLayout` TermSym interpretation in `lang/lambda/proj/`
9. Implement JSON pretty-printing in `lang/json/proj/`
10. Add snapshot tests comparing pretty-printed output at various widths
11. Wire into REPL (`cmd/main/`) for immediate developer value

## Acceptance Criteria

- [ ] `render_string(layout, width=80)` produces width-aware multi-line output
- [ ] `render_string(layout, width=999)` produces single-line output (flat)
- [ ] `render_spans` produces correct `(Span, Ann)` pairs with proper nesting
- [ ] `Group` flattens when content fits, breaks when it doesn't
- [ ] `HardLine` always breaks and forces surrounding groups to break
- [ ] `Annotate` spans bracket correctly in both renderers
- [ ] Lambda AST pretty-prints via `replay(term) : PrettyLayout`
- [ ] JSON values pretty-print with proper indentation
- [ ] `moon check` passes
- [ ] `moon test` passes for all new tests
- [ ] No regressions in existing tests

## Validation

```bash
moon check
moon test
cd loom/examples/lambda && moon test
```

## Risks

- **MoonBit closure semantics**: local `fn go(...)` capturing `Array` (a
  reference type) — verify this works correctly in practice. If not,
  thread `cmds` as a parameter or use a top-level private function
- **`flat_width` performance**: recursive traversal on every `Group` node.
  If profiling shows this is hot, add pre-computed `Requirement` caching
  (as in Yoorkin/prettyprinter). Benchmark first.
- **Orphan rule**: `PrettyLayout` wrapper is needed because we can't impl
  `TermSym` (from lambda package) for `Layout[Ann]` (from pretty package)
  directly. This is a known MoonBit constraint.

## Notes

- Yoorkin/prettyprinter (`moonbit-community/prettyprinter`) was evaluated as
  an existing solution. It's well-built (Wadler-Lindig, Pretty trait, 30+
  standard type impls) but doesn't support annotations — fundamental for a
  structural editor. Its source is a useful reference for MoonBit idioms.
- illusory0x0/prettyprinter uses a 2D deque box model — interesting but
  immature (v0.1.1, no trait support, last update Sep 2025).
- mizchi/ast_printer is a MoonBit source code printer, not a general
  pretty-printer.
