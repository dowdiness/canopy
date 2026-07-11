# Pretty-Printer Engine Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Wadler-Lindig pretty-printing engine with annotation support for Canopy's structural editor.

**Architecture:** Generic `Layout[A]` document tree with greedy group flattening. Two-pass rendering: `resolve` produces `Array[Cmd[A]]`, then separate renderers produce `String` or `Array[(Span, A)]`. TermSym integration via `PrettyLayout` wrapper type.

**Tech Stack:** MoonBit, Wadler-Lindig algorithm, TermSym (Finally Tagless)

**Design spec:** `docs/plans/2026-03-31-pretty-printer-design.md`

---

### Task 1: Package Scaffold and Layout[A] Enum

**Files:**
- Create: `pretty/moon.pkg`
- Create: `pretty/layout.mbt`
- Create: `pretty/layout_wbtest.mbt`

- [ ] **Step 1: Create package config**

```
// pretty/moon.pkg
import {
  "dowdiness/canopy/framework/core" @core,
}
```

- [ ] **Step 2: Write Layout[A] enum**

```moonbit
// pretty/layout.mbt

///|
pub enum Layout[A] {
  Empty
  Text(String)
  Line
  HardLine
  Nest(Int, Layout[A])
  Concat(Layout[A], Layout[A])
  Group(Layout[A])
  Annotate(A, Layout[A])
} derive(Show, Eq)
```

- [ ] **Step 3: Write basic test**

```moonbit
// pretty/layout_wbtest.mbt

test "Layout constructors" {
  let doc : Layout[Unit] = Concat(Text("hello"), Concat(Text(" "), Text("world")))
  inspect!(doc, content="Concat(Text(\"hello\"), Concat(Text(\" \"), Text(\"world\")))")
}
```

- [ ] **Step 4: Verify**

Run: `moon check && moon test -p dowdiness/canopy/pretty`

- [ ] **Step 5: Commit**

```bash
git add pretty/
git commit -m "feat(pretty): add Layout[A] enum and package scaffold"
```

---

### Task 2: Annotation Types

**Files:**
- Create: `pretty/ann.mbt`
- Create: `pretty/ann_wbtest.mbt`

- [ ] **Step 1: Write Ann, SyntaxCategory, Span types**

```moonbit
// pretty/ann.mbt

///|
pub enum SyntaxCategory {
  Keyword
  Identifier
  Number
  StringLit
  Operator
  Punctuation
  Comment
  Error
} derive(Show, Eq)

///|
pub(all) struct Ann {
  category : SyntaxCategory
  node_id : @core.NodeId?
} derive(Show, Eq)

///|
pub(all) struct Span {
  start : Int
  end : Int
} derive(Show, Eq)
```

- [ ] **Step 2: Run moon check**

Run: `moon check`

- [ ] **Step 3: Write test**

```moonbit
// pretty/ann_wbtest.mbt

test "Ann construction" {
  let ann = { category: Keyword, node_id: None }
  inspect!(ann.category, content="Keyword")
}

test "Ann with node_id" {
  let ann = { category: Identifier, node_id: Some(@core.NodeId::from_int(42)) }
  inspect!(ann.node_id.is_empty(), content="false")
}

test "Span construction" {
  let span : Span = { start: 0, end: 5 }
  inspect!(span.start, content="0")
  inspect!(span.end, content="5")
}
```

- [ ] **Step 4: Verify**

Run: `moon test -p dowdiness/canopy/pretty`

- [ ] **Step 5: Commit**

```bash
git add pretty/ann.mbt pretty/ann_wbtest.mbt
git commit -m "feat(pretty): add Ann, SyntaxCategory, and Span types"
```

---

### Task 3: Combinators

**Files:**
- Create: `pretty/combinators.mbt`
- Create: `pretty/combinators_wbtest.mbt`

- [ ] **Step 1: Write failing tests for basic combinators**

```moonbit
// pretty/combinators_wbtest.mbt

test "text" {
  let doc : Layout[Unit] = text("hello")
  inspect!(doc, content="Text(\"hello\")")
}

test "char" {
  let doc : Layout[Unit] = char('x')
  inspect!(doc, content="Text(\"x\")")
}

test "line" {
  let doc : Layout[Unit] = line()
  inspect!(doc, content="Line")
}

test "hardline" {
  let doc : Layout[Unit] = hardline()
  inspect!(doc, content="HardLine")
}

test "softline is group(line)" {
  let doc : Layout[Unit] = softline()
  inspect!(doc, content="Group(Line)")
}

test "nest" {
  let doc : Layout[Unit] = nest(text("x"))
  inspect!(doc, content="Nest(2, Text(\"x\"))")
}

test "nest custom indent" {
  let doc : Layout[Unit] = nest(indent=4, text("x"))
  inspect!(doc, content="Nest(4, Text(\"x\"))")
}

test "group" {
  let doc : Layout[Unit] = group(text("x"))
  inspect!(doc, content="Group(Text(\"x\"))")
}

test "concat via +" {
  let doc : Layout[Unit] = text("a") + text("b")
  inspect!(doc, content="Concat(Text(\"a\"), Text(\"b\"))")
}

test "annotate" {
  let doc = annotate(42, text("x"))
  inspect!(doc, content="Annotate(42, Text(\"x\"))")
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `moon test -p dowdiness/canopy/pretty`
Expected: FAIL — functions not defined

- [ ] **Step 3: Implement combinators**

```moonbit
// pretty/combinators.mbt

///|
pub fn text[A](s : String) -> Layout[A] {
  Text(s)
}

///|
pub fn char[A](c : Char) -> Layout[A] {
  Text(c.to_string())
}

///|
pub fn line[A]() -> Layout[A] {
  Line
}

///|
pub fn hardline[A]() -> Layout[A] {
  HardLine
}

///|
pub fn softline[A]() -> Layout[A] {
  Group(Line)
}

///|
pub fn nest[A](layout : Layout[A], indent~ : Int = 2) -> Layout[A] {
  Nest(indent, layout)
}

///|
pub fn group[A](doc : Layout[A]) -> Layout[A] {
  Group(doc)
}

///|
pub fn concat[A](l : Layout[A], r : Layout[A]) -> Layout[A] {
  Concat(l, r)
}

///|
pub fn annotate[A](ann : A, doc : Layout[A]) -> Layout[A] {
  Annotate(ann, doc)
}

///|
pub impl[A] Add for Layout[A] with add(self, other) {
  Concat(self, other)
}

///|
pub fn separate[A](sep : Layout[A], docs : Array[Layout[A]]) -> Layout[A] {
  match docs {
    [] => Empty
    [x, .. xs] => xs.iter().fold(init=x, fn(acc, d) { acc + sep + d })
  }
}

///|
pub fn surround[A](
  left : Layout[A],
  right : Layout[A],
  doc : Layout[A],
) -> Layout[A] {
  left + doc + right
}

///|
pub fn parens[A](doc : Layout[A]) -> Layout[A] {
  surround(char('('), char(')'), doc)
}

///|
pub fn brackets[A](doc : Layout[A]) -> Layout[A] {
  surround(char('['), char(']'), doc)
}

///|
pub fn braces[A](doc : Layout[A]) -> Layout[A] {
  surround(char('{'), char('}'), doc)
}

///|
pub fn bracket[A](l : String, r : String, doc : Layout[A]) -> Layout[A] {
  group(text(l) + nest(line() + doc) + line() + text(r))
}
```

- [ ] **Step 4: Run tests**

Run: `moon check && moon test -p dowdiness/canopy/pretty`
Expected: all pass

- [ ] **Step 5: Add tests for higher-level combinators**

```moonbit
// append to pretty/combinators_wbtest.mbt

test "separate" {
  let doc : Layout[Unit] = separate(text(", "), [text("a"), text("b"), text("c")])
  inspect!(
    doc,
    content="Concat(Concat(Text(\"a\"), Concat(Text(\", \"), Text(\"b\"))), Concat(Text(\", \"), Text(\"c\")))",
  )
}

test "separate empty" {
  let doc : Layout[Unit] = separate(text(", "), [])
  inspect!(doc, content="Empty")
}

test "parens" {
  let doc : Layout[Unit] = parens(text("x"))
  inspect!(doc, content="Concat(Concat(Text(\"(\"), Text(\"x\")), Text(\")\"))")
}
```

- [ ] **Step 6: Verify and commit**

Run: `moon check && moon test -p dowdiness/canopy/pretty`

```bash
git add pretty/combinators.mbt pretty/combinators_wbtest.mbt
git commit -m "feat(pretty): add Layout combinators"
```

---

### Task 4: Layout Algorithm — flat_width and resolve

**Files:**
- Create: `pretty/render.mbt`
- Create: `pretty/render_wbtest.mbt`

- [ ] **Step 1: Write flat_width tests**

```moonbit
// pretty/render_wbtest.mbt

test "flat_width of text" {
  inspect!(flat_width(text("hello") : Layout[Unit]), content="5")
}

test "flat_width of line" {
  inspect!(flat_width(line() : Layout[Unit]), content="1")
}

test "flat_width of hardline" {
  inspect!(flat_width(hardline() : Layout[Unit]), content="-1")
}

test "flat_width of concat" {
  let doc : Layout[Unit] = text("ab") + text("cd")
  inspect!(flat_width(doc), content="4")
}

test "flat_width of concat with hardline" {
  let doc : Layout[Unit] = text("ab") + hardline() + text("cd")
  inspect!(flat_width(doc), content="-1")
}

test "flat_width of nest" {
  let doc : Layout[Unit] = nest(text("hello"))
  inspect!(flat_width(doc), content="5")
}

test "flat_width of group" {
  let doc : Layout[Unit] = group(text("hello"))
  inspect!(flat_width(doc), content="5")
}

test "flat_width of annotate" {
  let doc = annotate(42, text("hello"))
  inspect!(flat_width(doc), content="5")
}
```

- [ ] **Step 2: Run tests to verify failure**

Run: `moon test -p dowdiness/canopy/pretty`
Expected: FAIL — `flat_width` not defined

- [ ] **Step 3: Implement Mode, Cmd, and flat_width**

```moonbit
// pretty/render.mbt

///|
priv enum Mode {
  Flat
  Break
} derive(Show, Eq)

///|
pub enum Cmd[A] {
  CText(String)
  CNewline(Int)
  CAnnStart(A)
  CAnnEnd(A)
} derive(Show, Eq)

///|
/// Compute width of a layout when rendered flat (Lines become spaces).
/// Returns -1 if the layout contains HardLine (cannot flatten).
fn flat_width[A](layout : Layout[A]) -> Int {
  match layout {
    Empty => 0
    Text(s) => s.length()
    Line => 1
    HardLine => -1
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

- [ ] **Step 4: Verify flat_width tests pass**

Run: `moon check && moon test -p dowdiness/canopy/pretty`

- [ ] **Step 5: Write resolve tests**

```moonbit
// append to pretty/render_wbtest.mbt

test "resolve simple text" {
  let doc : Layout[Unit] = text("hello")
  inspect!(resolve(80, doc), content="[CText(\"hello\")]")
}

test "resolve concat" {
  let doc : Layout[Unit] = text("a") + text("b")
  inspect!(resolve(80, doc), content="[CText(\"a\"), CText(\"b\")]")
}

test "resolve hardline" {
  let doc : Layout[Unit] = text("a") + hardline() + text("b")
  inspect!(resolve(80, doc), content="[CText(\"a\"), CNewline(0), CText(\"b\")]")
}

test "resolve nest + hardline" {
  let doc : Layout[Unit] = text("a") + nest(hardline() + text("b"))
  inspect!(
    resolve(80, doc),
    content="[CText(\"a\"), CNewline(2), CText(\"b\")]",
  )
}

test "resolve group that fits" {
  let doc : Layout[Unit] = group(text("a") + line() + text("b"))
  inspect!(
    resolve(80, doc),
    content="[CText(\"a\"), CText(\" \"), CText(\"b\")]",
  )
}

test "resolve group that breaks" {
  let doc : Layout[Unit] = group(text("a") + line() + text("b"))
  inspect!(
    resolve(3, doc),
    content="[CText(\"a\"), CNewline(0), CText(\"b\")]",
  )
}

test "resolve nested group" {
  let doc : Layout[Unit] = group(
    text("[") + nest(line() + text("item1") + text(",") + line() + text("item2")) + line() + text("]"),
  )
  // Width 80: fits on one line
  inspect!(
    resolve(80, doc),
    content="[CText(\"[\"), CText(\" \"), CText(\"item1\"), CText(\",\"), CText(\" \"), CText(\"item2\"), CText(\" \"), CText(\"]\")]",
  )
  // Width 10: breaks
  inspect!(
    resolve(10, doc),
    content="[CText(\"[\"), CNewline(2), CText(\"item1\"), CText(\",\"), CNewline(2), CText(\"item2\"), CNewline(0), CText(\"]\")]",
  )
}

test "resolve annotate" {
  let doc = annotate("ann", text("x"))
  inspect!(
    resolve(80, doc),
    content="[CAnnStart(\"ann\"), CText(\"x\"), CAnnEnd(\"ann\")]",
  )
}
```

- [ ] **Step 6: Implement resolve**

```moonbit
// append to pretty/render.mbt

///|
/// Wadler layout resolution. Recursive tree traversal with column threading.
/// Produces a flat command stream from a Layout tree.
pub fn resolve[A](width : Int, layout : Layout[A]) -> Array[Cmd[A]] {
  let cmds : Array[Cmd[A]] = []
  fn go(indent : Int, mode : Mode, column : Int, lay : Layout[A]) -> Int {
    match lay {
      Empty => column
      Text(s) => {
        cmds.push(CText(s))
        column + s.length()
      }
      Line =>
        match mode {
          Flat => {
            cmds.push(CText(" "))
            column + 1
          }
          Break => {
            cmds.push(CNewline(indent))
            indent
          }
        }
      HardLine => {
        cmds.push(CNewline(indent))
        indent
      }
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
```

- [ ] **Step 7: Verify all tests pass**

Run: `moon check && moon test -p dowdiness/canopy/pretty`
Expected: all pass. If snapshot output doesn't match, run `moon test --update` and verify diffs.

- [ ] **Step 8: Commit**

```bash
git add pretty/render.mbt pretty/render_wbtest.mbt
git commit -m "feat(pretty): add Wadler layout algorithm (flat_width + resolve)"
```

---

### Task 5: render_string

**Files:**
- Create: `pretty/render_string.mbt`
- Create: `pretty/render_string_wbtest.mbt`

- [ ] **Step 1: Write tests**

```moonbit
// pretty/render_string_wbtest.mbt

test "render_string simple" {
  let doc : Layout[Unit] = text("hello")
  inspect!(render_string(doc), content="hello")
}

test "render_string hardline" {
  let doc : Layout[Unit] = text("a") + hardline() + text("b")
  inspect!(
    render_string(doc),
    content=
      #|a
      #|b
    ,
  )
}

test "render_string nest + hardline" {
  let doc : Layout[Unit] = text("a") + nest(hardline() + text("b"))
  inspect!(
    render_string(doc),
    content=
      #|a
      #|  b
    ,
  )
}

test "render_string group fits" {
  let doc : Layout[Unit] = group(text("a") + line() + text("b"))
  inspect!(render_string(doc), content="a b")
}

test "render_string group breaks" {
  let doc : Layout[Unit] = group(text("a") + line() + text("b"))
  inspect!(
    render_string(doc, width=3),
    content=
      #|a
      #|b
    ,
  )
}

test "render_string bracket" {
  let items : Layout[Unit] = separate(
    text(",") + line(),
    [text("1"), text("2"), text("3")],
  )
  let doc = bracket("[", "]", items)
  // Wide: single line
  inspect!(render_string(doc, width=80), content="[1, 2, 3]")
  // Narrow: multi-line
  inspect!(
    render_string(doc, width=5),
    content=
      #|[
      #|  1,
      #|  2,
      #|  3
      #|]
    ,
  )
}

test "render_string nested brackets" {
  let inner : Layout[Unit] = bracket(
    "[",
    "]",
    separate(text(",") + line(), [text("a"), text("b")]),
  )
  let outer = bracket("[", "]", separate(text(",") + line(), [text("x"), inner, text("y")]))
  inspect!(render_string(outer, width=80), content="[x, [a, b], y]")
  inspect!(
    render_string(outer, width=10),
    content=
      #|[
      #|  x,
      #|  [
      #|    a,
      #|    b
      #|  ],
      #|  y
      #|]
    ,
  )
}
```

- [ ] **Step 2: Run tests to verify failure**

Run: `moon test -p dowdiness/canopy/pretty`
Expected: FAIL — `render_string` not defined

- [ ] **Step 3: Implement render_string**

```moonbit
// pretty/render_string.mbt

///|
/// Render a Layout to a plain string, ignoring annotations.
pub fn render_string[A](layout : Layout[A], width~ : Int = 80) -> String {
  let buf = StringBuilder::new()
  for cmd in resolve(width, layout) {
    match cmd {
      CText(s) => buf.write_string(s)
      CNewline(indent) => {
        buf.write_char('\n')
        for _ in 0..<indent {
          buf.write_char(' ')
        }
      }
      CAnnStart(_) | CAnnEnd(_) => ()
    }
  }
  buf.to_string()
}
```

- [ ] **Step 4: Verify tests pass**

Run: `moon check && moon test -p dowdiness/canopy/pretty`
Expected: all pass. Update snapshots with `moon test --update` if needed, then verify diffs.

- [ ] **Step 5: Commit**

```bash
git add pretty/render_string.mbt pretty/render_string_wbtest.mbt
git commit -m "feat(pretty): add render_string"
```

---

### Task 6: render_spans

**Files:**
- Create: `pretty/render_spans.mbt`
- Create: `pretty/render_spans_wbtest.mbt`

- [ ] **Step 1: Write tests**

```moonbit
// pretty/render_spans_wbtest.mbt

test "render_spans no annotations" {
  let doc : Layout[String] = text("hello")
  let spans = render_spans(doc)
  inspect!(spans, content="[]")
}

test "render_spans single annotation" {
  let doc = annotate("kw", text("let"))
  let spans = render_spans(doc)
  // "let" spans bytes 0..3
  inspect!(spans, content="[({start: 0, end: 3}, \"kw\")]")
}

test "render_spans nested annotations" {
  let doc = annotate(
    "expr",
    annotate("kw", text("let")) + text(" ") + annotate("id", text("x")),
  )
  let spans = render_spans(doc)
  // "kw" at 0..3, "id" at 4..5, "expr" at 0..5
  inspect!(
    spans,
    content="[({start: 0, end: 3}, \"kw\"), ({start: 4, end: 5}, \"id\"), ({start: 0, end: 5}, \"expr\")]",
  )
}

test "render_spans with line breaks" {
  let doc = annotate("block", text("a") + hardline() + text("b"))
  let spans = render_spans(doc)
  // "a\nb" = 3 bytes (a + newline + b)
  inspect!(spans, content="[({start: 0, end: 3}, \"block\")]")
}

test "render_spans with indented line" {
  let doc = annotate("block", text("a") + nest(hardline() + text("b")))
  let spans = render_spans(doc)
  // "a\n  b" = 5 bytes (a + newline + 2 spaces + b)
  inspect!(spans, content="[({start: 0, end: 5}, \"block\")]")
}
```

- [ ] **Step 2: Run tests to verify failure**

Run: `moon test -p dowdiness/canopy/pretty`
Expected: FAIL — `render_spans` not defined

- [ ] **Step 3: Implement render_spans**

```moonbit
// pretty/render_spans.mbt

///|
/// Render a Layout to annotated spans for editor rendering.
/// Returns an array of (Span, annotation) pairs.
pub fn render_spans[A](layout : Layout[A], width~ : Int = 80) -> Array[(Span, A)] {
  let spans : Array[(Span, A)] = []
  let ann_stack : Array[(A, Int)] = []
  for cmd in resolve(width, layout); offset = 0 {
    match cmd {
      CText(s) => continue offset + s.length()
      CNewline(indent) => continue offset + 1 + indent
      CAnnStart(ann) => {
        ann_stack.push((ann, offset))
        continue offset
      }
      CAnnEnd(_) => {
        if ann_stack.pop() is Some((ann, start)) {
          spans.push(({ start, end: offset }, ann))
        }
        continue offset
      }
    }
  } nobreak {
    ignore(offset)
  }
  spans
}
```

- [ ] **Step 4: Verify tests pass**

Run: `moon check && moon test -p dowdiness/canopy/pretty`
Expected: all pass. Update snapshots if needed.

- [ ] **Step 5: Commit**

```bash
git add pretty/render_spans.mbt pretty/render_spans_wbtest.mbt
git commit -m "feat(pretty): add render_spans for annotated output"
```

---

### Task 7: Lambda PrettyLayout (TermSym Integration)

**Files:**
- Create: `lang/lambda/proj/pretty_layout.mbt`
- Create: `lang/lambda/proj/pretty_layout_wbtest.mbt`

**Context:** The TermSym trait (in `loom/examples/lambda/src/ast/sym.mbt`) has these methods:
`int_lit`, `var`, `lam`, `app`, `bop`, `if_then_else`, `module`, `unit`, `unbound`, `error_term`, `hole`.
`Bop` is a binary operator enum. `VarName` = `String`.
Check `loom/examples/lambda/src/ast/sym.mbt` for the existing `Pretty` interpretation as reference.

- [ ] **Step 1: Write test for simple terms**

```moonbit
// lang/lambda/proj/pretty_layout_wbtest.mbt

test "pretty int_lit" {
  let pl : PrettyLayout = @ast.TermSym::int_lit(42)
  inspect!(@pretty.render_string(pl.layout), content="42")
}

test "pretty var" {
  let pl : PrettyLayout = @ast.TermSym::var("x")
  inspect!(@pretty.render_string(pl.layout), content="x")
}

test "pretty unit" {
  let pl : PrettyLayout = @ast.TermSym::unit()
  inspect!(@pretty.render_string(pl.layout), content="()")
}

test "pretty lam" {
  let pl : PrettyLayout = @ast.TermSym::lam(
    "x",
    @ast.TermSym::var("x"),
  )
  inspect!(@pretty.render_string(pl.layout), content="λx. x")
}

test "pretty app" {
  let pl : PrettyLayout = @ast.TermSym::app(
    @ast.TermSym::var("f"),
    @ast.TermSym::var("x"),
  )
  inspect!(@pretty.render_string(pl.layout), content="f x")
}
```

- [ ] **Step 2: Run tests to verify failure**

Run: `moon test -p dowdiness/canopy/lang/lambda/proj`
Expected: FAIL — `PrettyLayout` not defined

- [ ] **Step 3: Implement PrettyLayout with basic TermSym methods**

First check `loom/examples/lambda/src/ast/sym.mbt` for `Bop` variants and the
existing `Pretty` interpretation to match its output style. Then implement:

```moonbit
// lang/lambda/proj/pretty_layout.mbt

///|
pub struct PrettyLayout {
  layout : @pretty.Layout[@pretty.Ann]
}

///|
fn kw(s : String) -> @pretty.Layout[@pretty.Ann] {
  @pretty.annotate({ category: Keyword, node_id: None }, @pretty.text(s))
}

///|
fn ident(s : String) -> @pretty.Layout[@pretty.Ann] {
  @pretty.annotate({ category: Identifier, node_id: None }, @pretty.text(s))
}

///|
fn num(s : String) -> @pretty.Layout[@pretty.Ann] {
  @pretty.annotate({ category: Number, node_id: None }, @pretty.text(s))
}

///|
fn op(s : String) -> @pretty.Layout[@pretty.Ann] {
  @pretty.annotate({ category: Operator, node_id: None }, @pretty.text(s))
}

///|
fn punc(s : String) -> @pretty.Layout[@pretty.Ann] {
  @pretty.annotate({ category: Punctuation, node_id: None }, @pretty.text(s))
}

///|
fn err(s : String) -> @pretty.Layout[@pretty.Ann] {
  @pretty.annotate({ category: Error, node_id: None }, @pretty.text(s))
}

///|
pub impl @ast.TermSym for PrettyLayout with int_lit(n) {
  { layout: num(n.to_string()) }
}

///|
pub impl @ast.TermSym for PrettyLayout with var(name) {
  { layout: ident(name) }
}

///|
pub impl @ast.TermSym for PrettyLayout with unit() {
  { layout: punc("()") }
}

///|
pub impl @ast.TermSym for PrettyLayout with lam(x, body) {
  { layout:
    @pretty.group(
      kw("λ") + ident(x) + punc(".") + @pretty.text(" ") +
      @pretty.nest(body.layout)
    )
  }
}

///|
pub impl @ast.TermSym for PrettyLayout with app(f, arg) {
  { layout:
    @pretty.group(
      f.layout + @pretty.nest(@pretty.line() + arg.layout)
    )
  }
}

///|
pub impl @ast.TermSym for PrettyLayout with bop(b, l, r) {
  // Bop variants: Plus, Minus (defined in loom/examples/lambda/src/ast/ast.mbt)
  let op_str = match b {
    Plus => "+"
    Minus => "-"
  }
  { layout:
    @pretty.group(
      l.layout + @pretty.text(" ") + op(op_str) +
      @pretty.nest(@pretty.line() + r.layout)
    )
  }
}

///|
pub impl @ast.TermSym for PrettyLayout with if_then_else(cond, then_, else_) {
  { layout:
    @pretty.group(
      kw("if") + @pretty.text(" ") + cond.layout +
      @pretty.nest(
        @pretty.line() + kw("then") + @pretty.text(" ") + then_.layout +
        @pretty.line() + kw("else") + @pretty.text(" ") + else_.layout
      )
    )
  }
}

///|
pub impl @ast.TermSym for PrettyLayout with module(defs, body) {
  let def_layouts = defs.map(fn(pair) {
    let (name, val) = pair
    kw("let") + @pretty.text(" ") + ident(name) +
    @pretty.text(" ") + op("=") + @pretty.text(" ") +
    @pretty.nest(val.layout)
  })
  let defs_doc = @pretty.separate(@pretty.hardline(), def_layouts)
  { layout: defs_doc + @pretty.hardline() + body.layout }
}

///|
pub impl @ast.TermSym for PrettyLayout with unbound(name) {
  { layout: err("<unbound: " + name + ">") }
}

///|
pub impl @ast.TermSym for PrettyLayout with error_term(msg) {
  { layout: err("<error: " + msg + ">") }
}

///|
pub impl @ast.TermSym for PrettyLayout with hole(id) {
  { layout: err("_" + id.to_string()) }
}
```

- [ ] **Step 4: Run moon check to verify compilation**

Run: `moon check`

Fix any type errors. In particular:
- `Bop` has variants `Plus` and `Minus` — match on them for operator strings
- Verify `@ast.TermSym` is the correct trait path
- Verify `lang/lambda/proj/moon.pkg` includes `dowdiness/canopy/pretty`

Add to `lang/lambda/proj/moon.pkg` imports:
```
"dowdiness/canopy/pretty" @pretty,
```

- [ ] **Step 5: Run tests**

Run: `moon test -p dowdiness/canopy/lang/lambda/proj`
Expected: basic tests pass. Update snapshots if output format differs slightly.

- [ ] **Step 6: Add width-sensitive tests**

```moonbit
// append to lang/lambda/proj/pretty_layout_wbtest.mbt

test "pretty nested app breaks" {
  let pl : PrettyLayout = @ast.TermSym::app(
    @ast.TermSym::app(
      @ast.TermSym::var("very_long_function_name"),
      @ast.TermSym::var("first_argument"),
    ),
    @ast.TermSym::var("second_argument"),
  )
  inspect!(
    @pretty.render_string(pl.layout, width=30),
    content=
      #|very_long_function_name
      #|  first_argument
      #|  second_argument
    ,
  )
}

test "pretty if_then_else wide" {
  let pl : PrettyLayout = @ast.TermSym::if_then_else(
    @ast.TermSym::var("c"),
    @ast.TermSym::var("t"),
    @ast.TermSym::var("e"),
  )
  inspect!(@pretty.render_string(pl.layout), content="if c then t else e")
}

test "pretty if_then_else narrow" {
  let pl : PrettyLayout = @ast.TermSym::if_then_else(
    @ast.TermSym::var("condition"),
    @ast.TermSym::var("then_branch"),
    @ast.TermSym::var("else_branch"),
  )
  inspect!(
    @pretty.render_string(pl.layout, width=20),
    content=
      #|if condition
      #|  then then_branch
      #|  else else_branch
    ,
  )
}

test "pretty module" {
  let pl : PrettyLayout = @ast.TermSym::module(
    [("x", @ast.TermSym::int_lit(1)), ("y", @ast.TermSym::int_lit(2))],
    @ast.TermSym::bop(@ast.Bop::Plus, @ast.TermSym::var("x"), @ast.TermSym::var("y")),
  )
  inspect!(
    @pretty.render_string(pl.layout),
    content=
      #|let x = 1
      #|let y = 2
      #|x + y
    ,
  )
}
```

- [ ] **Step 7: Verify and commit**

Run: `moon check && moon test -p dowdiness/canopy/lang/lambda/proj`
Update snapshots as needed — the exact output may differ from these examples.
Verify diffs make sense.

```bash
git add lang/lambda/proj/pretty_layout.mbt lang/lambda/proj/pretty_layout_wbtest.mbt
git commit -m "feat(pretty): add PrettyLayout TermSym interpretation for Lambda"
```

---

### Task 8: JSON Pretty-Printing

**Files:**
- Create: `lang/json/proj/pretty_layout.mbt`
- Create: `lang/json/proj/pretty_layout_wbtest.mbt`
- Modify: `lang/json/proj/moon.pkg` — add `@pretty` import

**Context:** JSON AST is `@json.JsonValue` enum with variants:
`Null`, `Bool(Bool)`, `Number(Double)`, `String(String)`,
`Array(Array[JsonValue])`, `Object(Array[(String, JsonValue)])`, `Error(String)`.
Constructors must be fully qualified: `@json.JsonValue::Null`, etc.

- [ ] **Step 1: Add pretty import to moon.pkg**

Add to `lang/json/proj/moon.pkg` imports:
```
"dowdiness/canopy/pretty" @pretty,
```

- [ ] **Step 2: Write tests**

```moonbit
// lang/json/proj/pretty_layout_wbtest.mbt

test "json null" {
  inspect!(@pretty.render_string(json_to_layout(@json.JsonValue::Null)), content="null")
}

test "json bool" {
  inspect!(@pretty.render_string(json_to_layout(@json.JsonValue::Bool(true))), content="true")
}

test "json number" {
  inspect!(@pretty.render_string(json_to_layout(@json.JsonValue::Number(3.14))), content="3.14")
}

test "json string" {
  inspect!(
    @pretty.render_string(json_to_layout(@json.JsonValue::String("hello"))),
    content="\"hello\"",
  )
}

test "json array wide" {
  let arr = @json.JsonValue::Array([@json.JsonValue::Number(1.0), @json.JsonValue::Number(2.0), @json.JsonValue::Number(3.0)])
  inspect!(@pretty.render_string(json_to_layout(arr)), content="[1, 2, 3]")
}

test "json array narrow" {
  let arr = @json.JsonValue::Array([@json.JsonValue::Number(1.0), @json.JsonValue::Number(2.0), @json.JsonValue::Number(3.0)])
  inspect!(
    @pretty.render_string(json_to_layout(arr), width=5),
    content=
      #|[
      #|  1,
      #|  2,
      #|  3
      #|]
    ,
  )
}

test "json object" {
  let obj = @json.JsonValue::Object([("name", @json.JsonValue::String("Alice")), ("age", @json.JsonValue::Number(30.0))])
  inspect!(
    @pretty.render_string(json_to_layout(obj)),
    content="{\"name\": \"Alice\", \"age\": 30}",
  )
}

test "json nested" {
  let obj = @json.JsonValue::Object([
    ("users", @json.JsonValue::Array([
      @json.JsonValue::Object([("name", @json.JsonValue::String("A"))]),
      @json.JsonValue::Object([("name", @json.JsonValue::String("B"))]),
    ])),
  ])
  inspect!(
    @pretty.render_string(json_to_layout(obj), width=20),
    content=
      #|{
      #|  "users": [
      #|    {"name": "A"},
      #|    {"name": "B"}
      #|  ]
      #|}
    ,
  )
}
```

- [ ] **Step 3: Run tests to verify failure**

Run: `moon test -p dowdiness/canopy/lang/json/proj`
Expected: FAIL — `json_to_layout` not defined

- [ ] **Step 4: Implement json_to_layout**

```moonbit
// lang/json/proj/pretty_layout.mbt

///|
fn json_ann(category : @pretty.SyntaxCategory) -> @pretty.Ann {
  { category, node_id: None }
}

///|
/// Convert a JsonValue to a pretty-printable Layout with annotations.
pub fn json_to_layout(value : @json.JsonValue) -> @pretty.Layout[@pretty.Ann] {
  // Pattern matching on @json.JsonValue — variants are accessible
  // without full qualification inside match arms
  match value {
    @json.JsonValue::Null =>
      @pretty.annotate(json_ann(Keyword), @pretty.text("null"))
    @json.JsonValue::Bool(b) =>
      @pretty.annotate(json_ann(Keyword), @pretty.text(b.to_string()))
    @json.JsonValue::Number(n) => {
      // Format: strip trailing ".0" for integers
      let s = n.to_string()
      let display = if s.ends_with(".0") {
        s.substring(end=s.length() - 2)
      } else {
        s
      }
      @pretty.annotate(json_ann(Number), @pretty.text(display))
    }
    @json.JsonValue::String(s) =>
      @pretty.annotate(
        json_ann(StringLit),
        @pretty.text("\"") + @pretty.text(s) + @pretty.text("\""),
      )
    @json.JsonValue::Array(elems) => {
      let items = elems.map(json_to_layout)
      let sep = @pretty.text(",") + @pretty.line()
      @pretty.group(
        @pretty.text("[") +
        @pretty.nest(@pretty.softline() + @pretty.separate(sep, items)) +
        @pretty.softline() +
        @pretty.text("]")
      )
    }
    @json.JsonValue::Object(pairs) => {
      let entries = pairs.map(fn(pair) {
        let (key, val) = pair
        @pretty.annotate(json_ann(StringLit), @pretty.text("\"" + key + "\"")) +
        @pretty.text(":") + @pretty.text(" ") +
        json_to_layout(val)
      })
      let sep = @pretty.text(",") + @pretty.line()
      @pretty.group(
        @pretty.text("{") +
        @pretty.nest(@pretty.softline() + @pretty.separate(sep, entries)) +
        @pretty.softline() +
        @pretty.text("}")
      )
    }
    @json.JsonValue::Error(msg) =>
      @pretty.annotate(json_ann(Error), @pretty.text("<error: " + msg + ">"))
  }
}
```

- [ ] **Step 5: Verify**

Run: `moon check && moon test -p dowdiness/canopy/lang/json/proj`
Expected: pass. Update snapshots as needed — number formatting and spacing
may need adjustment. Verify diffs make sense.

- [ ] **Step 6: Commit**

```bash
git add lang/json/proj/pretty_layout.mbt lang/json/proj/pretty_layout_wbtest.mbt lang/json/proj/moon.pkg
git commit -m "feat(pretty): add JSON pretty-printing with json_to_layout"
```

---

### Task 9: Interface Update and Final Validation

**Files:**
- Modify: generated `.mbti` files

- [ ] **Step 1: Update interfaces**

Run: `moon info`

- [ ] **Step 2: Check API surface**

Run: `git diff *.mbti`

Verify the public API includes:
- `Layout[A]` enum with all constructors
- All combinator functions
- `Ann`, `SyntaxCategory`, `Span` types
- `Cmd[A]` enum
- `resolve`, `render_string`, `render_spans` functions
- `PrettyLayout` struct in lambda proj
- `json_to_layout` in json proj

- [ ] **Step 3: Format**

Run: `moon fmt`

- [ ] **Step 4: Full test suite**

Run: `moon check && moon test && cd loom/examples/lambda && moon test`

- [ ] **Step 5: Commit**

```bash
git add pretty/*.mbti lang/lambda/proj/*.mbti lang/json/proj/*.mbti
git add pretty/*.mbt lang/lambda/proj/*.mbt lang/json/proj/*.mbt
git commit -m "chore: update interfaces and format for pretty-printer"
```

---

## Appendix: File Map

| File | Action | Purpose |
|------|--------|---------|
| `pretty/moon.pkg` | Create | Package config with framework/core dep |
| `pretty/layout.mbt` | Create | `Layout[A]` enum (8 constructors) |
| `pretty/ann.mbt` | Create | `Ann`, `SyntaxCategory`, `Span` |
| `pretty/combinators.mbt` | Create | `text`, `line`, `nest`, `group`, etc. |
| `pretty/render.mbt` | Create | `Mode`, `Cmd[A]`, `flat_width`, `resolve` |
| `pretty/render_string.mbt` | Create | `render_string` |
| `pretty/render_spans.mbt` | Create | `render_spans` |
| `pretty/layout_wbtest.mbt` | Create | Layout constructor tests |
| `pretty/ann_wbtest.mbt` | Create | Ann type tests |
| `pretty/combinators_wbtest.mbt` | Create | Combinator tests |
| `pretty/render_wbtest.mbt` | Create | flat_width + resolve tests |
| `pretty/render_string_wbtest.mbt` | Create | String rendering snapshot tests |
| `pretty/render_spans_wbtest.mbt` | Create | Span rendering tests |
| `lang/lambda/proj/pretty_layout.mbt` | Create | `PrettyLayout` + TermSym impls |
| `lang/lambda/proj/pretty_layout_wbtest.mbt` | Create | Lambda pretty-printing tests |
| `lang/lambda/proj/moon.pkg` | Modify | Add `@pretty` import |
| `lang/json/proj/pretty_layout.mbt` | Create | `json_to_layout` |
| `lang/json/proj/pretty_layout_wbtest.mbt` | Create | JSON pretty-printing tests |
| `lang/json/proj/moon.pkg` | Modify | Add `@pretty` import |
