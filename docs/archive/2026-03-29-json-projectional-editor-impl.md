# JSON Projectional Editor — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a JSON projection pipeline that proves framework/core works with a second real language, validated by tests.

**Architecture:** Shared edit types (SpanEdit, FocusHint) in framework/core. Trait impls in loom JSON module (type owner). Projection builders in `canopy/lang/json/proj/`. Edit handlers in `canopy/lang/json/edits/`. New `SyncEditor::new_generic` constructor avoids FlatProj dependency.

**Tech Stack:** MoonBit, loom parser framework, framework/core (ProjNode, SourceMap, reconcile, SpanEdit, FocusHint)

**Design spec:** `docs/design/2026-03-29-json-projectional-editor-design.md`

---

## Phase overview

| Phase | Tasks | What |
|-------|-------|------|
| A — Prerequisites | 1–3 | Move SpanEdit/FocusHint to framework/core; add SyncEditor::new_generic; make parse_json_string pub |
| B — Loom submodule | 4 | TreeNode + Renderable impls for JsonValue |
| C — Projection pipeline | 5–6 | syntax_to_proj_node, populate_token_spans, memo builder |
| D — Edit handlers | 7–8 | JsonEditOp, compute_json_edit, edit bridge |
| E — Integration | 9 | new_json_editor, end-to-end tests |

Each task must pass all tests before proceeding.

---

## Task 1: Move SpanEdit + FocusHint to framework/core/

**Why:** These types are structurally generic (text span replacement + cursor hint). Moving them to framework/core allows both lambda and JSON to share them without cross-language dependencies.

**Files:**
- Modify: `framework/core/types.mbt` — add SpanEdit and FocusHint definitions
- Modify: `lang/lambda/edits/types.mbt` — replace definitions with `pub using @core { type SpanEdit, type FocusHint }`
- Modify: `lang/lambda/edits/text_edit.mbt` — update references (SpanEdit is also used here)
- Modify: `framework/core/moon.pkg` — no new deps needed

- [ ] **Step 1: Add SpanEdit and FocusHint to `framework/core/types.mbt`**

```moonbit
///|
pub(all) struct SpanEdit {
  start : Int
  delete_len : Int
  inserted : String
} derive(Show, Eq)

///|
pub(all) enum FocusHint {
  RestoreCursor
  MoveCursor(position~ : Int)
} derive(Show, Eq)
```

- [ ] **Step 2: Update `lang/lambda/edits/types.mbt` and `lang/lambda/edits/text_edit.mbt`**

In `lang/lambda/edits/types.mbt`, replace the local SpanEdit and FocusHint definitions with re-exports:
```moonbit
pub using @core { type SpanEdit, type FocusHint }
```

In `lang/lambda/edits/text_edit.mbt`, update any direct references to use the re-exported types (no code change needed if they already reference `SpanEdit` unqualified — the re-export makes them available).

Keep all other definitions (DropPosition, JsonEditOp-equivalent types) unchanged.

- [ ] **Step 3: Run `moon check && moon test`**

All existing tests must pass unchanged — `@proj.SpanEdit` resolves through the re-export chain.

- [ ] **Step 4: `moon info && moon fmt`**

- [ ] **Step 5: Commit**

```bash
git commit -m "refactor: move SpanEdit and FocusHint to framework/core (shared across languages)"
```

---

## Task 2: Add SyncEditor::new_generic (no FlatProj dependency)

**Why:** JSON has no FlatProj. A separate constructor avoids requiring `lang/json/` to import `@lambda_flat` just for the type signature.

**Files:**
- Modify: `editor/sync_editor.mbt` — add `proj_memo` as optional, add `new_generic` constructor
- Modify: `editor/projection_memo.mbt` — update `build_lambda_projection_memos` return, update `get_flat_proj`

- [ ] **Step 1: Make `proj_memo` optional and add `new_generic`**

In `editor/sync_editor.mbt`:
```moonbit
// Change field:
priv proj_memo : @incr.Memo[@lambda_flat.VersionedFlatProj]?

// Add public generic constructor:
pub fn[T] SyncEditor::new_generic(
  agent_id : String,
  make_parser : (String) -> @loom.ImperativeParser[T],
  build_memos : (
    @incr.Runtime,
    @incr.Signal[String],
    @incr.Signal[@seam.SyntaxNode?],
    @loom.ImperativeParser[T],
  ) -> (
    @incr.Memo[@proj.ProjNode[T]?],
    @incr.Memo[Map[@proj.NodeId, @proj.ProjNode[T]]],
    @incr.Memo[@proj.SourceMap],
  ),
  capture_timeout_ms? : Int = 500,
) -> SyncEditor[T] {
  // Same body as `new`, but:
  // - build_memos returns 3-tuple (no FlatProj)
  // - proj_memo = None
}
```

- [ ] **Step 2: Update existing `new` to wrap `proj_memo` in `Some`**

- [ ] **Step 3: Update `get_flat_proj` to handle None**

```moonbit
pub fn[T] SyncEditor::get_flat_proj(self : SyncEditor[T]) -> @proj.FlatProj? {
  match self.proj_memo {
    Some(memo) => Some(memo.get().flat_proj)
    None => None
  }
}
```

- [ ] **Step 4: Update `build_lambda_projection_memos` return type**

Wrap the FlatProj memo return in `Some(...)` to match the new optional field.

- [ ] **Step 5: Run `moon check && moon test`**

- [ ] **Step 6: `moon info && moon fmt` && Commit**

---

## Task 3: Make parse_json_string pub + make apply_text_edit_internal pub

**Why:** The projection builder needs proper string unescaping (already implemented in loom). The edit bridge needs to apply text edits through SyncEditor.

**Files:**
- Modify: `loom/examples/json/src/value_convert.mbt` — change `fn parse_json_string` to `pub fn parse_json_string`
- Modify: `editor/sync_editor_text.mbt` — change `fn[T] SyncEditor::apply_text_edit_internal` to `pub fn[T]`

- [ ] **Step 1: Make parse_json_string pub**

In `loom/examples/json/src/value_convert.mbt` line 5:
```moonbit
// Before:
fn parse_json_string(raw : String) -> String {
// After:
pub fn parse_json_string(raw : String) -> String {
```

- [ ] **Step 2: Run loom JSON tests**

```bash
cd loom/examples/json && moon check && moon test
```

- [ ] **Step 3: Commit in loom, push, bump submodule**

```bash
cd loom/examples/json && git add src/value_convert.mbt && git commit -m "feat(json): make parse_json_string pub for projection builder"
cd loom && git push
cd .. && git add loom
```

- [ ] **Step 4: Make apply_text_edit_internal pub**

In `editor/sync_editor_text.mbt`:
```moonbit
// Before:
fn[T] SyncEditor::apply_text_edit_internal(
// After:
pub fn[T] SyncEditor::apply_text_edit_internal(
```

- [ ] **Step 5: Run `moon check && moon test`**

- [ ] **Step 6: `moon info && moon fmt` && Commit**

```bash
git commit -m "refactor: make apply_text_edit_internal pub for cross-package edit bridges"
```

---

> **Note:** Old Task 1 (optional proj_memo) is now superseded by Task 2 (new_generic constructor). The following tasks are renumbered from the original plan.

## Task 4: Add TreeNode + Renderable impls for JsonValue

**Why:** JsonValue needs these traits for reconciliation and rendering in the projection pipeline.

**Important:** TreeNode and Renderable are defined in `dowdiness/loom/core` (file `loom/loom/src/core/proj_traits.mbt`). The JSON module already imports `dowdiness/loom/core` as `@core`.

**Files:**
- Create: `loom/examples/json/src/proj_traits.mbt` — trait impls
- Create: `loom/examples/json/src/proj_traits_test.mbt` — tests

- [ ] **Step 1: Check if `@core.TreeNode` is accessible**

In the JSON module, `@core` refers to `dowdiness/loom/core` which defines TreeNode and Renderable. Verify:

```bash
grep 'TreeNode\|Renderable' loom/loom/src/core/pkg.generated.mbti
```

Expected: both traits listed. No moon.pkg change needed — `@core` already imports the right package.

- [ ] **Step 2: Write failing tests**

Create `loom/examples/json/src/proj_traits_test.mbt`:

```moonbit
///|
test "TreeNode::children — leaf nodes return empty" {
  inspect(@core.TreeNode::children(JsonValue::Null).length(), content="0")
  inspect(@core.TreeNode::children(Bool(true)).length(), content="0")
  inspect(@core.TreeNode::children(Number(42.0)).length(), content="0")
  inspect(@core.TreeNode::children(String("hello")).length(), content="0")
  inspect(@core.TreeNode::children(Error("oops")).length(), content="0")
}

///|
test "TreeNode::children — Array returns items" {
  let arr = Array([Number(1.0), Number(2.0), String("three")])
  let children = @core.TreeNode::children(arr)
  inspect(children.length(), content="3")
}

///|
test "TreeNode::children — Object returns values only" {
  let obj = Object([("a", Number(1.0)), ("b", Bool(true))])
  let children = @core.TreeNode::children(obj)
  inspect(children.length(), content="2")
  inspect(children[0], content="Number(1)")
  inspect(children[1], content="Bool(true)")
}

///|
test "TreeNode::same_kind — same constructors match" {
  inspect(@core.TreeNode::same_kind(Null, Null), content="true")
  inspect(@core.TreeNode::same_kind(Number(1.0), Number(2.0)), content="true")
  inspect(@core.TreeNode::same_kind(Array([]), Array([Null])), content="true")
  inspect(@core.TreeNode::same_kind(Object([]), Object([("a", Null)])), content="true")
}

///|
test "TreeNode::same_kind — different constructors don't match" {
  inspect(@core.TreeNode::same_kind(Null, Bool(true)), content="false")
  inspect(@core.TreeNode::same_kind(Number(1.0), String("1")), content="false")
  inspect(@core.TreeNode::same_kind(Array([]), Object([])), content="false")
}

///|
test "Renderable::kind_tag" {
  inspect(@core.Renderable::kind_tag(Null), content="Null")
  inspect(@core.Renderable::kind_tag(Array([])), content="Array")
  inspect(@core.Renderable::kind_tag(Object([])), content="Object")
}

///|
test "Renderable::label — leaf values" {
  inspect(@core.Renderable::label(Null), content="null")
  inspect(@core.Renderable::label(Bool(true)), content="true")
  inspect(@core.Renderable::label(Number(42.0)), content="42")
}

///|
test "Renderable::label — containers show summary" {
  let arr = Array([Null, Null, Null])
  inspect(@core.Renderable::label(arr), content="[3 items]")
  let obj = Object([("name", String("Alice")), ("age", Number(30.0))])
  inspect(@core.Renderable::label(obj), content="{name, age}")
}

///|
test "Renderable::placeholder — per-kind" {
  inspect(@core.Renderable::placeholder(Null), content="null")
  inspect(@core.Renderable::placeholder(Bool(true)), content="false")
  inspect(@core.Renderable::placeholder(Number(1.0)), content="0")
  inspect(@core.Renderable::placeholder(String("x")), content="\"\"")
  inspect(@core.Renderable::placeholder(Array([])), content="[]")
  inspect(@core.Renderable::placeholder(Object([])), content="{}")
}

///|
test "Renderable::unparse — round-trip" {
  inspect(@core.Renderable::unparse(Null), content="null")
  inspect(@core.Renderable::unparse(Bool(true)), content="true")
  inspect(@core.Renderable::unparse(Number(42.0)), content="42")
  inspect(@core.Renderable::unparse(String("hello")), content="\"hello\"")
}

///|
test "Renderable::unparse — error produces valid JSON" {
  inspect(@core.Renderable::unparse(Error("something went wrong")), content="null")
}

///|
test "Renderable::unparse — string with escapes" {
  inspect(
    @core.Renderable::unparse(String("line1\nline2")),
    content="\"line1\\nline2\"",
  )
  inspect(
    @core.Renderable::unparse(String("tab\there")),
    content="\"tab\\there\"",
  )
  inspect(
    @core.Renderable::unparse(String("a\"b")),
    content="\"a\\\"b\"",
  )
}
```

- [ ] **Step 3: Run tests to verify they fail**

```bash
cd loom/examples/json && moon test
```

Expected: FAIL — TreeNode and Renderable not implemented for JsonValue.

- [ ] **Step 4: Implement TreeNode for JsonValue**

Create `loom/examples/json/src/proj_traits.mbt`:

```moonbit
// TreeNode and Renderable implementations for JsonValue.
// Enables projectional editing via framework/core (ProjNode, SourceMap, reconcile).

///|
pub impl @core.TreeNode for JsonValue with children(self) {
  match self {
    Array(items) => items
    Object(members) => members.map(fn(m) { m.1 })
    _ => []
  }
}

///|
pub impl @core.TreeNode for JsonValue with same_kind(self, other) {
  match (self, other) {
    (Null, Null) => true
    (Bool(_), Bool(_)) => true
    (Number(_), Number(_)) => true
    (String(_), String(_)) => true
    (Array(_), Array(_)) => true
    (Object(_), Object(_)) => true
    (Error(_), Error(_)) => true
    _ => false
  }
}
```

- [ ] **Step 5: Implement Renderable for JsonValue**

Append to `loom/examples/json/src/proj_traits.mbt`:

```moonbit
///|
pub impl @core.Renderable for JsonValue with kind_tag(self) {
  match self {
    Null => "Null"
    Bool(_) => "Bool"
    Number(_) => "Number"
    String(_) => "String"
    Array(_) => "Array"
    Object(_) => "Object"
    Error(_) => "Error"
  }
}

///|
pub impl @core.Renderable for JsonValue with label(self) {
  match self {
    Null => "null"
    Bool(b) => b.to_string()
    Number(n) => {
      let s = n.to_string()
      // Strip trailing .0 for integers
      if s.length() >= 2 &&
        s[s.length() - 2] == '.' &&
        s[s.length() - 1] == '0' {
        s.substring(end=s.length() - 2)
      } else {
        s
      }
    }
    String(s) =>
      if s.length() > 20 {
        "\"" + s.substring(end=20) + "...\""
      } else {
        "\"" + s + "\""
      }
    Array(items) => "[" + items.length().to_string() + " items]"
    Object(members) => "{" + members.map(fn(m) { m.0 }).join(", ") + "}"
    Error(msg) => "Error: " + msg
  }
}

///|
pub impl @core.Renderable for JsonValue with placeholder(self) {
  match self {
    Null => "null"
    Bool(_) => "false"
    Number(_) => "0"
    String(_) => "\"\""
    Array(_) => "[]"
    Object(_) => "{}"
    Error(_) => "null"
  }
}

///|
pub impl @core.Renderable for JsonValue with unparse(self) {
  json_unparse(self, 0)
}

///|
fn json_unparse(value : JsonValue, depth : Int) -> String {
  match value {
    Null => "null"
    Bool(b) => b.to_string()
    Number(n) => {
      let s = n.to_string()
      if s.length() >= 2 &&
        s[s.length() - 2] == '.' &&
        s[s.length() - 1] == '0' {
        s.substring(end=s.length() - 2)
      } else {
        s
      }
    }
    String(s) => "\"" + json_escape(s) + "\""
    Array(items) =>
      if items.is_empty() {
        "[]"
      } else {
        let indent = make_indent(depth + 1)
        let close_indent = make_indent(depth)
        let parts = items.map(fn(item) { indent + json_unparse(item, depth + 1) })
        "[\n" + parts.join(",\n") + "\n" + close_indent + "]"
      }
    Object(members) =>
      if members.is_empty() {
        "{}"
      } else {
        let indent = make_indent(depth + 1)
        let close_indent = make_indent(depth)
        let parts = members.map(fn(m) {
          indent + "\"" + json_escape(m.0) + "\": " + json_unparse(m.1, depth + 1)
        })
        "{\n" + parts.join(",\n") + "\n" + close_indent + "}"
      }
    Error(_) => "null"
  }
}

///|
fn make_indent(depth : Int) -> String {
  let buf = StringBuilder::new()
  for i = 0; i < depth; i = i + 1 {
    buf.write_string("  ")
  }
  buf.to_string()
}

///|
/// Escape a string for JSON output. Handles double-quote, backslash,
/// and common control characters.
pub fn json_escape(s : String) -> String {
  let buf = StringBuilder::new()
  for ch in s {
    match ch {
      '"' => buf.write_string("\\\"")
      '\\' => buf.write_string("\\\\")
      '\n' => buf.write_string("\\n")
      '\t' => buf.write_string("\\t")
      '\r' => buf.write_string("\\r")
      _ => buf.write_char(ch)
    }
  }
  buf.to_string()
}
```

> **Note:** `json_escape` is `pub` so the canopy projection builder can import it for edit handlers that insert key strings.

- [ ] **Step 6: Run tests**

```bash
cd loom/examples/json && moon check && moon test
```

Expected: all pass including the new proj_traits tests. Update snapshots if needed:

```bash
cd loom/examples/json && moon test --update
```

- [ ] **Step 7: `moon info && moon fmt`**

- [ ] **Step 8: Commit in loom submodule**

```bash
cd loom/examples/json
git add src/proj_traits.mbt src/proj_traits_test.mbt src/pkg.generated.mbti
git commit -m "feat(json): implement TreeNode and Renderable for JsonValue"
```

- [ ] **Step 9: Push loom and bump submodule in canopy**

```bash
cd loom && git push
cd .. && git add loom && git commit -m "chore: bump loom (TreeNode/Renderable for JsonValue)"
```

---

## Task 5: Create lang/json/proj/ — projection builder

**Why:** Converts JSON CST (SyntaxNode) to ProjNode[JsonValue] for the framework pipeline.

**Key architectural decisions:**
1. **SyntaxNode has no `.text()` method** — only SyntaxToken has `.text()`. Use `node.token_text(kind)` or `node.find_token(kind)` to extract token text from nodes.
2. **MemberNode CST structure:** Token children are `StringToken` (key) and `ColonToken`. Node children are the value node (via `child.nth_child(0)`).
3. **Member span for delete correctness:** Each Object ProjNode child uses the **MemberNode's span** (not the value's span), so that `SourceMap::get_range()` for a child covers the full `"key": value` text. This means delete removes the entire member.
4. **String values:** Use `node.token_text(StringToken.to_raw())` to get the raw quoted text, then `@json.parse_json_string(text)` for proper unescaping (handles `\"`, `\\`, `\n`, Unicode escapes). Made pub in Task 3.

**Reference files:**
- `loom/examples/json/src/value_convert.mbt` lines 153-185 (member extraction pattern)
- `loom/seam/syntax_node.mbt` (SyntaxNode API)
- `loom/examples/json/src/cst_parser.mbt` lines 144-156 (MemberNode CST structure)

**Files:**
- Create: `lang/json/proj/moon.pkg`
- Create: `lang/json/proj/proj_node.mbt` — syntax_to_proj_node
- Create: `lang/json/proj/populate_token_spans.mbt` — key name span extraction
- Create: `lang/json/proj/proj_node_wbtest.mbt` — tests

- [ ] **Step 1: Create `lang/json/proj/moon.pkg`**

```
import {
  "dowdiness/canopy/framework/core" @core,
  "dowdiness/json" @json,
  "dowdiness/loom/core" @loomcore,
  "dowdiness/seam" @seam,
  "moonbitlang/core/strconv",
}
```

- [ ] **Step 2: Add `dowdiness/json` to canopy's module dependencies**

In the root `moon.mod.json`, add:
```json
"dowdiness/json": { "path": "./loom/examples/json" }
```

- [ ] **Step 3: Write projection builder tests**

Create `lang/json/proj/proj_node_wbtest.mbt`:

```moonbit
///|
test "syntax_to_proj_node — null" {
  let (proj, errors) = parse_to_proj_node("null")
  inspect(errors.length(), content="0")
  inspect(proj.kind, content="Null")
  inspect(proj.children.length(), content="0")
}

///|
test "syntax_to_proj_node — number" {
  let (proj, errors) = parse_to_proj_node("42")
  inspect(errors.length(), content="0")
  match proj.kind {
    @json.Number(n) => inspect(n, content="42")
    _ => fail!("expected Number")
  }
}

///|
test "syntax_to_proj_node — string" {
  let (proj, errors) = parse_to_proj_node("\"hello\"")
  inspect(errors.length(), content="0")
  match proj.kind {
    @json.String(s) => inspect(s, content="hello")
    _ => fail!("expected String")
  }
}

///|
test "syntax_to_proj_node — boolean true" {
  let (proj, errors) = parse_to_proj_node("true")
  inspect(errors.length(), content="0")
  match proj.kind {
    @json.Bool(b) => inspect(b, content="true")
    _ => fail!("expected Bool")
  }
}

///|
test "syntax_to_proj_node — boolean false" {
  let (proj, errors) = parse_to_proj_node("false")
  inspect(errors.length(), content="0")
  match proj.kind {
    @json.Bool(b) => inspect(b, content="false")
    _ => fail!("expected Bool")
  }
}

///|
test "syntax_to_proj_node — array" {
  let (proj, errors) = parse_to_proj_node("[1, 2, 3]")
  inspect(errors.length(), content="0")
  inspect(proj.kind is @json.Array(_), content="true")
  inspect(proj.children.length(), content="3")
  // Check children have correct kinds
  match proj.children[0].kind {
    @json.Number(n) => inspect(n, content="1")
    _ => fail!("expected Number child")
  }
}

///|
test "syntax_to_proj_node — object" {
  let (proj, errors) = parse_to_proj_node("{\"a\": 1, \"b\": true}")
  inspect(errors.length(), content="0")
  inspect(proj.kind is @json.Object(_), content="true")
  // Object children are values, but spans cover full members
  inspect(proj.children.length(), content="2")
  match proj.children[0].kind {
    @json.Number(n) => inspect(n, content="1")
    _ => fail!("expected Number child for 'a'")
  }
  match proj.children[1].kind {
    @json.Bool(b) => inspect(b, content="true")
    _ => fail!("expected Bool child for 'b'")
  }
}

///|
test "syntax_to_proj_node — object child spans cover full member" {
  // For input {"a": 1}, the child ProjNode span should cover "a": 1 (the full member)
  let (proj, _) = parse_to_proj_node("{\"a\": 1}")
  // Root object spans 0..8
  inspect(proj.start, content="0")
  inspect(proj.end, content="8")
  // Child spans the MemberNode: "a": 1 = bytes 1..7
  inspect(proj.children[0].start, content="1")
  inspect(proj.children[0].end, content="7")
}

///|
test "syntax_to_proj_node — nested" {
  let (proj, errors) = parse_to_proj_node("{\"data\": [1, 2]}")
  inspect(errors.length(), content="0")
  inspect(proj.children.length(), content="1")
  inspect(proj.children[0].kind is @json.Array(_), content="true")
  inspect(proj.children[0].children.length(), content="2")
}

///|
test "syntax_to_proj_node — error recovery" {
  let (proj, _errors) = parse_to_proj_node("{\"a\": }")
  // Should produce a node even for malformed JSON
  inspect(proj.kind is @json.Object(_), content="true")
}

///|
test "SourceMap positions match spans" {
  let (proj, _) = parse_to_proj_node("{\"a\": 1}")
  let sm = @core.SourceMap::from_ast(proj)
  // Root object spans the entire input
  let root_range = sm.get_range(proj.id())
  match root_range {
    Some(r) => {
      inspect(r.start, content="0")
      inspect(r.end, content="8")
    }
    None => fail!("expected root range")
  }
}

///|
test "reconcile preserves IDs on value edit" {
  let (old, _) = parse_to_proj_node("{\"a\": 1, \"b\": 2}")
  let (new_, _) = parse_to_proj_node("{\"a\": 99, \"b\": 2}")
  let counter = Ref::new(1000)
  let reconciled = @core.reconcile(old, new_, counter)
  // Root Object ID preserved
  inspect(reconciled.node_id == old.node_id, content="true")
  // Second child (unchanged "b": 2) preserves ID
  inspect(reconciled.children[1].node_id == old.children[1].node_id, content="true")
}

///|
test "member delete removes full member text" {
  // Given {"a": 1, "b": 2}, deleting the first child should remove "a": 1
  let source = "{\"a\": 1, \"b\": 2}"
  let (proj, _) = parse_to_proj_node(source)
  let sm = @core.SourceMap::from_ast(proj)
  // First child range should cover the full member "a": 1
  let child_range = sm.get_range(proj.children[0].id())
  match child_range {
    Some(r) => {
      let member_text = source.substring(start=r.start, end=r.end)
      // Should include key, colon, and value
      inspect(member_text, content="\"a\": 1")
    }
    None => fail!("expected child range")
  }
}
```

- [ ] **Step 4: Implement `syntax_to_proj_node`**

Create `lang/json/proj/proj_node.mbt`:

```moonbit
// CST -> ProjNode[JsonValue] builder for JSON.
//
// Key design: Object ProjNode children use the MemberNode's span (not the value's span).
// This ensures SourceMap::get_range() for a child covers the full "key": value text,
// so that delete removes the entire member.

using @core {type ProjNode, type NodeId}
using @loomcore {type Range}

///|
pub fn syntax_to_proj_node(
  node : @seam.SyntaxNode,
  counter : Ref[Int],
) -> ProjNode[@json.JsonValue] {
  let kind = node.kind()
  if kind == @json.ObjectNode.to_raw() {
    build_object_node(node, counter)
  } else if kind == @json.ArrayNode.to_raw() {
    build_array_node(node, counter)
  } else if kind == @json.StringValue.to_raw() {
    // StringValue node contains a StringToken child. Extract its text.
    let raw = node.token_text(@json.StringToken.to_raw())
    let inner = @json.parse_json_string(raw)
    ProjNode::new(
      @json.String(inner),
      node.start(), node.end(),
      @core.next_proj_node_id(counter),
      [],
    )
  } else if kind == @json.NumberValue.to_raw() {
    // NumberValue node contains a NumberToken child. Extract its text.
    let text = node.token_text(@json.NumberToken.to_raw())
    let n = try { @strconv.parse_double(text) } catch { _ => 0.0 }
    ProjNode::new(
      @json.Number(n),
      node.start(), node.end(),
      @core.next_proj_node_id(counter),
      [],
    )
  } else if kind == @json.BoolValue.to_raw() {
    // BoolValue node contains either TrueKeyword or FalseKeyword token.
    let b = node.find_token(@json.TrueKeyword.to_raw()) is Some(_)
    ProjNode::new(
      @json.Bool(b),
      node.start(), node.end(),
      @core.next_proj_node_id(counter),
      [],
    )
  } else if kind == @json.NullValue.to_raw() {
    ProjNode::new(
      @json.Null,
      node.start(), node.end(),
      @core.next_proj_node_id(counter),
      [],
    )
  } else if kind == @json.ErrorNode.to_raw() {
    ProjNode::new(
      @json.Error("parse error"),
      node.start(), node.end(),
      @core.next_proj_node_id(counter),
      [],
    )
  } else if kind == @json.RootNode.to_raw() {
    // Root node: recurse into single child value
    match node.nth_child(0) {
      Some(child) => syntax_to_proj_node(child, counter)
      None =>
        ProjNode::new(
          @json.Null,
          node.start(), node.end(),
          @core.next_proj_node_id(counter),
          [],
        )
    }
  } else if kind == @json.MemberNode.to_raw() {
    // MemberNode shouldn't be visited directly — parent Object handles it.
    // But handle gracefully if called.
    match node.nth_child(0) {
      Some(value_node) => syntax_to_proj_node(value_node, counter)
      None =>
        ProjNode::new(
          @json.Error("empty member"),
          node.start(), node.end(),
          @core.next_proj_node_id(counter),
          [],
        )
    }
  } else {
    ProjNode::new(
      @json.Error("unknown node kind"),
      node.start(), node.end(),
      @core.next_proj_node_id(counter),
      [],
    )
  }
}

///|
fn build_object_node(
  node : @seam.SyntaxNode,
  counter : Ref[Int],
) -> ProjNode[@json.JsonValue] {
  let members : Array[(String, @json.JsonValue)] = []
  let children : Array[ProjNode[@json.JsonValue]] = []
  for child in node.children() {
    if child.kind() == @json.MemberNode.to_raw() {
      let (key, value_kind, value_proj) = extract_member(child, counter)
      members.push((key, value_kind))
      // Use the MemberNode's span for the child ProjNode, not the value's span.
      // This ensures SourceMap::get_range() covers "key": value for delete.
      let member_proj = ProjNode::new(
        value_proj.kind,
        child.start(),  // MemberNode start
        child.end(),    // MemberNode end
        value_proj.node_id,
        value_proj.children,
      )
      children.push(member_proj)
    }
  }
  ProjNode::new(
    @json.Object(members),
    node.start(), node.end(),
    @core.next_proj_node_id(counter),
    children,
  )
}

///|
fn build_array_node(
  node : @seam.SyntaxNode,
  counter : Ref[Int],
) -> ProjNode[@json.JsonValue] {
  let items : Array[@json.JsonValue] = []
  let children : Array[ProjNode[@json.JsonValue]] = []
  for child in node.children() {
    let proj = syntax_to_proj_node(child, counter)
    items.push(proj.kind)
    children.push(proj)
  }
  ProjNode::new(
    @json.Array(items),
    node.start(), node.end(),
    @core.next_proj_node_id(counter),
    children,
  )
}

///|
/// Extract key, value kind, and value ProjNode from a MemberNode.
///
/// MemberNode CST structure:
/// - Token children: StringToken (the key), ColonToken
/// - Node children: the value node (first node child, via nth_child(0))
///
/// Key extraction: iterate all_children(), find first SyntaxElement::Token
/// where kind == StringToken.to_raw(), use token.text().
fn extract_member(
  member_node : @seam.SyntaxNode,
  counter : Ref[Int],
) -> (String, @json.JsonValue, ProjNode[@json.JsonValue]) {
  // Extract key from first StringToken child (same pattern as value_convert.mbt)
  let mut key = ""
  for elem in member_node.all_children() {
    match elem {
      @seam.SyntaxElement::Token(t) =>
        if @json.StringToken.to_raw() == t.kind() {
          key = @json.parse_json_string(t.text())
          break
        }
      _ => ()
    }
  }
  // Extract value from first node child
  let value_proj = match member_node.nth_child(0) {
    Some(v) => syntax_to_proj_node(v, counter)
    None =>
      ProjNode::new(
        @json.Error("missing value"),
        member_node.start(), member_node.end(),
        @core.next_proj_node_id(counter),
        [],
      )
  }
  (key, value_proj.kind, value_proj)
}

///|
/// Parse JSON text and return a ProjNode tree.
pub fn parse_to_proj_node(
  text : String,
) -> (ProjNode[@json.JsonValue], Array[String]) {
  let (cst, diagnostics) = @json.parse_cst(text) catch {
    _ => abort("JSON parse failed")
  }
  let syntax_node = @seam.SyntaxNode::from_cst(cst)
  let errors = diagnostics.map(fn(d) { d.message })
  let root = syntax_to_proj_node(syntax_node, Ref::new(0))
  (root, errors)
}
```

- [ ] **Step 5: Implement `populate_token_spans`**

Create `lang/json/proj/populate_token_spans.mbt`:

```moonbit
// Token span extraction for JSON objects.
// Extracts key name spans from MemberNode StringToken children.
// Key spans are stored as "key:0", "key:1", etc. in the SourceMap token_spans.

using @core {type NodeId, type ProjNode, type SourceMap}
using @loomcore {type Range}

///|
/// Populate token-level spans for JSON object keys.
/// Key spans cover the entire quoted StringToken (including quotes).
pub fn populate_token_spans(
  source_map : SourceMap,
  syntax_root : @seam.SyntaxNode,
  proj_root : ProjNode[@json.JsonValue],
) -> Unit {
  // Unwrap RootNode — syntax_to_proj_node does this, so the proj_root
  // corresponds to the child under RootNode, not RootNode itself.
  let syntax_node = if syntax_root.kind() == @json.RootNode.to_raw() {
    match syntax_root.first_child() {
      Some(child) => child
      None => return
    }
  } else {
    syntax_root
  }
  collect_key_spans(source_map, syntax_node, proj_root)
}

///|
fn collect_key_spans(
  source_map : SourceMap,
  syntax_node : @seam.SyntaxNode,
  proj_node : ProjNode[@json.JsonValue],
) -> Unit {
  match proj_node.kind {
    @json.Object(_) => {
      // Walk MemberNode children to extract key StringToken spans
      let mut member_idx = 0
      for child in syntax_node.children() {
        if child.kind() == @json.MemberNode.to_raw() {
          // Find the key StringToken (first StringToken among direct children)
          let mut key_token : @seam.SyntaxToken? = None
          for elem in child.all_children() {
            match elem {
              @seam.SyntaxElement::Token(t) =>
                if @json.StringToken.to_raw() == t.kind() {
                  key_token = Some(t)
                  break
                }
              _ => ()
            }
          }
          match key_token {
            Some(tok) => {
              let role = "key:" + member_idx.to_string()
              source_map.set_token_span(
                proj_node.id(),
                role,
                Range::new(tok.start(), tok.end()),
              )
            }
            None => ()
          }
          // Recurse into value child
          if member_idx < proj_node.children.length() {
            // The value node is the first node child of the MemberNode
            match child.nth_child(0) {
              Some(value_syntax) =>
                collect_key_spans(
                  source_map,
                  value_syntax,
                  proj_node.children[member_idx],
                )
              None => ()
            }
          }
          member_idx = member_idx + 1
        }
      }
    }
    @json.Array(_) => {
      let syntax_children = syntax_node.children()
      for i = 0; i < proj_node.children.length(); i = i + 1 {
        if i < syntax_children.length() {
          collect_key_spans(source_map, syntax_children[i], proj_node.children[i])
        }
      }
    }
    _ => ()
  }
}
```

- [ ] **Step 6: Run tests**

```bash
moon check && moon test
```

Fix any compilation errors. The tests from Step 3 should now pass.

- [ ] **Step 7: `moon info && moon fmt`**

- [ ] **Step 8: Commit**

```bash
git add lang/json/ moon.mod.json
git commit -m "feat(json): add projection builder — syntax_to_proj_node and populate_token_spans"
```

---

## Task 6: Create memo builder for JSON

**Why:** SyncEditor needs a `build_memos` callback that produces ProjNode, registry, and SourceMap memos from the parser signals.

**Files:**
- Create: `lang/json/proj/json_memo.mbt` — build_json_projection_memos

- [ ] **Step 1: Update `lang/json/proj/moon.pkg` with all needed imports**

```
import {
  "dowdiness/canopy/framework/core" @core,
  "dowdiness/incr" @incr,
  "dowdiness/json" @json,
  "dowdiness/loom" @loom,
  "dowdiness/loom/core" @loomcore,
  "dowdiness/seam" @seam,
  "moonbitlang/core/strconv",
}
```

> **Note:** No `@lambda_flat` dependency — uses `SyncEditor::new_generic` (3-memo callback from Task 2).

- [ ] **Step 2: Implement `build_json_projection_memos`**

Create `lang/json/proj/json_memo.mbt`:

```moonbit
// Memo builder for JSON projection pipeline.
// Simpler than lambda: no FlatProj, full rebuild each cycle.

using @core {type ProjNode, type NodeId, type SourceMap}

///|
pub fn build_json_projection_memos(
  rt : @incr.Runtime,
  source_text : @incr.Signal[String],
  syntax_tree : @incr.Signal[@seam.SyntaxNode?],
  parser : @loom.ImperativeParser[@json.JsonValue],
) -> (
  @incr.Memo[ProjNode[@json.JsonValue]?],
  @incr.Memo[Map[NodeId, ProjNode[@json.JsonValue]]],
  @incr.Memo[SourceMap],
) {
  let _ = (source_text, parser) // available for future incremental use
  let prev_proj_ref : Ref[ProjNode[@json.JsonValue]?] = Ref::new(None)
  let counter = Ref::new(0)

  // ProjNode memo: rebuild from syntax tree, reconcile with previous
  let proj_memo : @incr.Memo[ProjNode[@json.JsonValue]?] = @incr.Memo::new_no_backdate(
    rt,
    fn() -> ProjNode[@json.JsonValue]? {
      match syntax_tree.get() {
        None => {
          prev_proj_ref.val = None
          None
        }
        Some(syntax_root) => {
          let new_proj = syntax_to_proj_node(syntax_root, counter)
          let result = match prev_proj_ref.val {
            Some(old) => @core.reconcile(old, new_proj, counter)
            None => new_proj
          }
          prev_proj_ref.val = Some(result)
          Some(result)
        }
      }
    },
  )

  // Registry memo: NodeId -> ProjNode lookup
  let registry_memo : @incr.Memo[Map[NodeId, ProjNode[@json.JsonValue]]] = @incr.Memo::new_no_backdate(
    rt,
    fn() -> Map[NodeId, ProjNode[@json.JsonValue]] {
      let reg : Map[NodeId, ProjNode[@json.JsonValue]] = {}
      match proj_memo.get() {
        Some(root) => collect_registry(root, reg)
        None => ()
      }
      reg
    },
  )

  // SourceMap memo: position tracking
  let source_map_memo : @incr.Memo[SourceMap] = @incr.Memo::new_no_backdate(
    rt,
    fn() -> SourceMap {
      match (proj_memo.get(), syntax_tree.get()) {
        (Some(root), Some(syntax_root)) => {
          let sm = SourceMap::from_ast(root)
          populate_token_spans(sm, syntax_root, root)
          sm
        }
        _ => SourceMap::new()
      }
    },
  )

  (proj_memo, registry_memo, source_map_memo)
}

///|
fn collect_registry(
  node : ProjNode[@json.JsonValue],
  reg : Map[NodeId, ProjNode[@json.JsonValue]],
) -> Unit {
  reg[node.id()] = node
  for child in node.children {
    collect_registry(child, reg)
  }
}
```

- [ ] **Step 3: Run `moon check` and fix compilation errors**

```bash
moon check
```

Iterate until clean.

- [ ] **Step 4: Commit**

```bash
git add lang/json/proj/
git commit -m "feat(json): add memo builder for JSON projection pipeline"
```

---

## Task 7: Create lang/json/edits/ — edit handlers

**Why:** Provides structural JSON edit operations (add member, delete, wrap, rename key, etc.).

**Key design decisions:**
1. **Delete uses member span:** Because Object ProjNode children have MemberNode spans (from Task 3 fix #3), `source_map.get_range(child_id)` returns the full member span. Delete removes the entire `"key": value` text plus trailing/leading comma.
2. **Edit handlers use `json_escape` for keys:** AddMember, WrapInObject, RenameKey all insert key strings and must escape special characters.
3. **Error unparse:** `Error(_)` produces `"null"` (valid JSON), not a comment.
4. **compute_unwrap guards:** Only unwraps single-element arrays and single-member objects. Returns Err for multi-element containers. For objects, finds the value node span within the member rather than string splitting.

**Files:**
- Create: `lang/json/edits/moon.pkg`
- Create: `lang/json/edits/json_edit_op.mbt` — JsonEditOp enum
- Create: `lang/json/edits/compute_json_edit.mbt` — edit dispatch
- Create: `lang/json/edits/compute_json_edit_wbtest.mbt` — tests

- [ ] **Step 1: Create `lang/json/edits/moon.pkg`**

```
import {
  "dowdiness/canopy/framework/core" @core,
  "dowdiness/canopy/lang/json/proj" @json_proj,
  "dowdiness/json" @json,
  "dowdiness/loom/core" @loomcore,
  "dowdiness/seam" @seam,
}
```

- [ ] **Step 2: Create JsonEditOp enum**

Create `lang/json/edits/json_edit_op.mbt`:

```moonbit
using @core {type NodeId}

///|
pub(all) enum JsonEditOp {
  Delete(node_id~ : NodeId)
  AddMember(object_id~ : NodeId, key~ : String)
  AddElement(array_id~ : NodeId)
  WrapInArray(node_id~ : NodeId)
  WrapInObject(node_id~ : NodeId, key~ : String)
  Unwrap(node_id~ : NodeId)
  ChangeType(node_id~ : NodeId, new_type~ : String)
  RenameKey(object_id~ : NodeId, key_index~ : Int, new_key~ : String)
  CommitEdit(node_id~ : NodeId, new_value~ : String)
} derive(Show, Eq)

// SpanEdit and FocusHint are imported from @core (framework/core/types.mbt).
// No duplicate definitions needed — use @core.SpanEdit and @core.FocusHint directly.
```

- [ ] **Step 3: Write edit handler tests**

Create `lang/json/edits/compute_json_edit_wbtest.mbt`:

```moonbit
///|
fn make_edit_context(
  source : String,
) -> (@core.ProjNode[@json.JsonValue], @core.SourceMap) {
  let (proj, _) = @json_proj.parse_to_proj_node(source)
  let sm = @core.SourceMap::from_ast(proj)
  (proj, sm)
}

///|
test "Delete member from object" {
  let source = "{\"a\": 1, \"b\": 2}"
  let (proj, sm) = make_edit_context(source)
  // Delete first member (child 0)
  let child_id = proj.children[0].id()
  let result = compute_json_edit(
    Delete(node_id=child_id),
    source,
    proj,
    sm,
  )
  match result {
    Ok(Some((edits, _))) => {
      inspect(edits.length() > 0, content="true")
      // The edit should remove "a": 1 and the trailing comma+space
      let edit = edits[0]
      inspect(edit.inserted, content="")
    }
    _ => fail!("Expected Ok(Some(...))")
  }
}

///|
test "AddMember to empty object" {
  let source = "{}"
  let (proj, sm) = make_edit_context(source)
  let result = compute_json_edit(
    AddMember(object_id=proj.id(), key="name"),
    source,
    proj,
    sm,
  )
  match result {
    Ok(Some((edits, _))) => {
      inspect(edits.length(), content="1")
      let edit = edits[0]
      inspect(edit.inserted, content="\"name\": null")
    }
    _ => fail!("Expected Ok(Some(...))")
  }
}

///|
test "AddMember to non-empty object" {
  let source = "{\"a\": 1}"
  let (proj, sm) = make_edit_context(source)
  let result = compute_json_edit(
    AddMember(object_id=proj.id(), key="b"),
    source,
    proj,
    sm,
  )
  match result {
    Ok(Some((edits, _))) => {
      inspect(edits.length(), content="1")
      let edit = edits[0]
      inspect(edit.inserted, content=", \"b\": null")
    }
    _ => fail!("Expected Ok(Some(...))")
  }
}

///|
test "WrapInArray" {
  let source = "42"
  let (proj, sm) = make_edit_context(source)
  let result = compute_json_edit(
    WrapInArray(node_id=proj.id()),
    source,
    proj,
    sm,
  )
  match result {
    Ok(Some((edits, _))) => {
      inspect(edits.length(), content="2")
    }
    _ => fail!("Expected Ok(Some(...))")
  }
}

///|
test "WrapInObject escapes key" {
  let source = "42"
  let (proj, sm) = make_edit_context(source)
  let result = compute_json_edit(
    WrapInObject(node_id=proj.id(), key="a\"b"),
    source,
    proj,
    sm,
  )
  match result {
    Ok(Some((edits, _))) => {
      let prefix_edit = edits[0]
      inspect(prefix_edit.inserted, content="{\"a\\\"b\": ")
    }
    _ => fail!("Expected Ok(Some(...))")
  }
}

///|
test "RenameKey" {
  let source = "{\"old\": 1}"
  let (proj, sm) = make_edit_context(source)
  // Populate token spans so key spans are available
  let (cst, _) = @json.parse_cst(source) catch { _ => abort("parse fail") }
  let syntax_root = @seam.SyntaxNode::from_cst(cst)
  @json_proj.populate_token_spans(sm, syntax_root, proj)
  let result = compute_json_edit(
    RenameKey(object_id=proj.id(), key_index=0, new_key="new"),
    source,
    proj,
    sm,
  )
  match result {
    Ok(Some((edits, _))) => {
      inspect(edits.length(), content="1")
      inspect(edits[0].inserted, content="\"new\"")
    }
    _ => fail!("Expected Ok(Some(...))")
  }
}

///|
test "RenameKey escapes special chars" {
  let source = "{\"old\": 1}"
  let (proj, sm) = make_edit_context(source)
  let (cst, _) = @json.parse_cst(source) catch { _ => abort("parse fail") }
  let syntax_root = @seam.SyntaxNode::from_cst(cst)
  @json_proj.populate_token_spans(sm, syntax_root, proj)
  let result = compute_json_edit(
    RenameKey(object_id=proj.id(), key_index=0, new_key="a\nb"),
    source,
    proj,
    sm,
  )
  match result {
    Ok(Some((edits, _))) => {
      inspect(edits[0].inserted, content="\"a\\nb\"")
    }
    _ => fail!("Expected Ok(Some(...))")
  }
}

///|
test "Unwrap single-element array" {
  let source = "[42]"
  let (proj, sm) = make_edit_context(source)
  let result = compute_json_edit(
    Unwrap(node_id=proj.id()),
    source,
    proj,
    sm,
  )
  match result {
    Ok(Some((edits, _))) => {
      inspect(edits.length(), content="1")
      inspect(edits[0].inserted, content="42")
    }
    _ => fail!("Expected Ok(Some(...))")
  }
}

///|
test "Unwrap multi-element array fails" {
  let source = "[1, 2]"
  let (proj, sm) = make_edit_context(source)
  let result = compute_json_edit(
    Unwrap(node_id=proj.id()),
    source,
    proj,
    sm,
  )
  inspect(result is Err(_), content="true")
}

///|
test "Unwrap single-member object" {
  let source = "{\"a\": 42}"
  let (proj, sm) = make_edit_context(source)
  let result = compute_json_edit(
    Unwrap(node_id=proj.id()),
    source,
    proj,
    sm,
  )
  match result {
    Ok(Some((edits, _))) => {
      inspect(edits.length(), content="1")
      inspect(edits[0].inserted, content="42")
    }
    _ => fail!("Expected Ok(Some(...))")
  }
}
```

- [ ] **Step 4: Implement `compute_json_edit`**

Create `lang/json/edits/compute_json_edit.mbt`:

```moonbit
using @core {type ProjNode, type NodeId, type SourceMap, type SpanEdit, type FocusHint}
using @loomcore {type Range}

///|
pub fn compute_json_edit(
  op : JsonEditOp,
  source : String,
  proj : ProjNode[@json.JsonValue],
  source_map : SourceMap,
) -> Result[(Array[SpanEdit], FocusHint)?, String] {
  match op {
    Delete(node_id~) => compute_delete(node_id, source, proj, source_map)
    AddMember(object_id~, key~) => compute_add_member(object_id, key, source, proj, source_map)
    AddElement(array_id~) => compute_add_element(array_id, source, proj, source_map)
    WrapInArray(node_id~) => compute_wrap_in_array(node_id, source, source_map)
    WrapInObject(node_id~, key~) => compute_wrap_in_object(node_id, key, source, source_map)
    Unwrap(node_id~) => compute_unwrap(node_id, source, proj, source_map)
    ChangeType(node_id~, new_type~) => compute_change_type(node_id, new_type, source_map)
    RenameKey(object_id~, key_index~, new_key~) =>
      compute_rename_key(object_id, key_index, new_key, source_map)
    CommitEdit(node_id~, new_value~) => compute_commit(node_id, new_value, source_map)
  }
}

///|
fn compute_delete(
  node_id : NodeId,
  source : String,
  _proj : ProjNode[@json.JsonValue],
  source_map : SourceMap,
) -> Result[(Array[SpanEdit], FocusHint)?, String] {
  let range = match source_map.get_range(node_id) {
    Some(r) => r
    None => return Err("node not in source map")
  }
  // The range covers the full member/element span (including key+colon for objects).
  // Try to consume a trailing comma + whitespace.
  let delete_start = range.start
  let delete_end = range.end
  let mut end = delete_end
  while end < source.length() {
    let ch = source[end]
    if ch == ',' {
      end = end + 1
      // Skip whitespace after comma
      while end < source.length() && is_json_ws(source[end]) {
        end = end + 1
      }
      break
    } else if is_json_ws(ch) {
      end = end + 1
    } else {
      // No trailing comma. Try consuming a leading comma instead.
      // Look backward from delete_start for ", " pattern.
      let mut start = delete_start
      while start > 0 && is_json_ws(source[start - 1]) {
        start = start - 1
      }
      if start > 0 && source[start - 1] == ',' {
        start = start - 1
        let edits = [SpanEdit::{ start, delete_len: delete_end - start, inserted: "" }]
        return Ok(Some((edits, RestoreCursor)))
      }
      break
    }
  }
  let edits = [SpanEdit::{ start: delete_start, delete_len: end - delete_start, inserted: "" }]
  Ok(Some((edits, RestoreCursor)))
}

///|
fn is_json_ws(ch : Char) -> Bool {
  ch == ' ' || ch == '\n' || ch == '\t' || ch == '\r'
}

///|
fn compute_add_member(
  object_id : NodeId,
  key : String,
  source : String,
  _proj : ProjNode[@json.JsonValue],
  source_map : SourceMap,
) -> Result[(Array[SpanEdit], FocusHint)?, String] {
  let range = match source_map.get_range(object_id) {
    Some(r) => r
    None => return Err("object not in source map")
  }
  // Insert before the closing brace
  let insert_pos = range.end - 1
  // Check if there's content between braces (non-empty object)
  let mut has_content = false
  for i = range.start + 1; i < insert_pos; i = i + 1 {
    if not(is_json_ws(source[i])) {
      has_content = true
      break
    }
  }
  let escaped_key = @json.json_escape(key)
  let prefix = if has_content { ", " } else { "" }
  let new_member = prefix + "\"" + escaped_key + "\": null"
  let edits = [SpanEdit::{ start: insert_pos, delete_len: 0, inserted: new_member }]
  let cursor_pos = insert_pos + new_member.length() // after "null"
  Ok(Some((edits, MoveCursor(position=cursor_pos))))
}

///|
fn compute_add_element(
  array_id : NodeId,
  source : String,
  _proj : ProjNode[@json.JsonValue],
  source_map : SourceMap,
) -> Result[(Array[SpanEdit], FocusHint)?, String] {
  let range = match source_map.get_range(array_id) {
    Some(r) => r
    None => return Err("array not in source map")
  }
  let insert_pos = range.end - 1
  let mut has_content = false
  for i = range.start + 1; i < insert_pos; i = i + 1 {
    if not(is_json_ws(source[i])) {
      has_content = true
      break
    }
  }
  let prefix = if has_content { ", " } else { "" }
  let edits = [SpanEdit::{ start: insert_pos, delete_len: 0, inserted: prefix + "null" }]
  Ok(Some((edits, MoveCursor(position=insert_pos + prefix.length()))))
}

///|
fn compute_wrap_in_array(
  node_id : NodeId,
  _source : String,
  source_map : SourceMap,
) -> Result[(Array[SpanEdit], FocusHint)?, String] {
  let range = match source_map.get_range(node_id) {
    Some(r) => r
    None => return Err("node not in source map")
  }
  let edits = [
    SpanEdit::{ start: range.start, delete_len: 0, inserted: "[" },
    SpanEdit::{ start: range.end, delete_len: 0, inserted: "]" },
  ]
  Ok(Some((edits, RestoreCursor)))
}

///|
fn compute_wrap_in_object(
  node_id : NodeId,
  key : String,
  _source : String,
  source_map : SourceMap,
) -> Result[(Array[SpanEdit], FocusHint)?, String] {
  let range = match source_map.get_range(node_id) {
    Some(r) => r
    None => return Err("node not in source map")
  }
  let escaped_key = @json.json_escape(key)
  let prefix = "{\"" + escaped_key + "\": "
  let edits = [
    SpanEdit::{ start: range.start, delete_len: 0, inserted: prefix },
    SpanEdit::{ start: range.end, delete_len: 0, inserted: "}" },
  ]
  Ok(Some((edits, RestoreCursor)))
}

///|
fn compute_unwrap(
  node_id : NodeId,
  source : String,
  proj : ProjNode[@json.JsonValue],
  source_map : SourceMap,
) -> Result[(Array[SpanEdit], FocusHint)?, String] {
  let range = match source_map.get_range(node_id) {
    Some(r) => r
    None => return Err("node not in source map")
  }
  // Find the ProjNode by its ID
  let node = match @core.get_node_in_tree(proj, node_id) {
    Some(n) => n
    None => return Err("node not found in projection tree")
  }
  match node.kind {
    @json.Array(items) => {
      if items.length() != 1 {
        return Err("can only unwrap single-element array, got " + items.length().to_string())
      }
      // Extract the single element's text from source using child's range
      let child = node.children[0]
      let child_range = match source_map.get_range(child.id()) {
        Some(r) => r
        None => return Err("child not in source map")
      }
      let content = source.substring(start=child_range.start, end=child_range.end)
      let edits = [SpanEdit::{ start: range.start, delete_len: range.end - range.start, inserted: content }]
      Ok(Some((edits, RestoreCursor)))
    }
    @json.Object(members) => {
      if members.length() != 1 {
        return Err("can only unwrap single-member object, got " + members.length().to_string())
      }
      // The child ProjNode has the member span. We need the value's text within it.
      // The child's kind IS the value, but its span is the member span.
      // Get the value text by finding its actual position from the child's own children
      // or by using unparse as fallback.
      let child = node.children[0]
      // For a single-member object, the value is the child's kind.
      // We need to find the value's actual text range. Since the child's span covers
      // the full member, we look at the child's sub-children for containers,
      // or use the source_map range for leaf values.
      // Simplest correct approach: unparse the value kind.
      let content = @loomcore.Renderable::unparse(child.kind)
      let edits = [SpanEdit::{ start: range.start, delete_len: range.end - range.start, inserted: content }]
      Ok(Some((edits, RestoreCursor)))
    }
    _ => Err("can only unwrap Array or Object")
  }
}

///|
fn compute_change_type(
  node_id : NodeId,
  new_type : String,
  source_map : SourceMap,
) -> Result[(Array[SpanEdit], FocusHint)?, String] {
  let range = match source_map.get_range(node_id) {
    Some(r) => r
    None => return Err("node not in source map")
  }
  let replacement = match new_type {
    "null" => "null"
    "bool" => "false"
    "number" => "0"
    "string" => "\"\""
    "array" => "[]"
    "object" => "{}"
    _ => return Err("unknown type: " + new_type)
  }
  let edits = [SpanEdit::{ start: range.start, delete_len: range.end - range.start, inserted: replacement }]
  Ok(Some((edits, MoveCursor(position=range.start + replacement.length()))))
}

///|
fn compute_rename_key(
  object_id : NodeId,
  key_index : Int,
  new_key : String,
  source_map : SourceMap,
) -> Result[(Array[SpanEdit], FocusHint)?, String] {
  let role = "key:" + key_index.to_string()
  let span = match source_map.get_token_span(object_id, role) {
    Some(s) => s
    None => return Err("key span not found for " + role)
  }
  // Replace the entire quoted key token, escaping the new key
  let escaped_key = @json.json_escape(new_key)
  let replacement = "\"" + escaped_key + "\""
  let edits = [SpanEdit::{ start: span.start, delete_len: span.end - span.start, inserted: replacement }]
  Ok(Some((edits, RestoreCursor)))
}

///|
fn compute_commit(
  node_id : NodeId,
  new_value : String,
  source_map : SourceMap,
) -> Result[(Array[SpanEdit], FocusHint)?, String] {
  let range = match source_map.get_range(node_id) {
    Some(r) => r
    None => return Err("node not in source map")
  }
  let edits = [SpanEdit::{ start: range.start, delete_len: range.end - range.start, inserted: new_value }]
  Ok(Some((edits, MoveCursor(position=range.start + new_value.length()))))
}
```

- [ ] **Step 5: Run `moon check` and fix compilation errors**

```bash
moon check
```

- [ ] **Step 6: Run tests and update snapshots**

```bash
moon test && moon test --update
```

Review the snapshot outputs to verify correctness.

- [ ] **Step 7: `moon info && moon fmt`**

- [ ] **Step 8: Commit**

```bash
git add lang/json/edits/
git commit -m "feat(json): add edit handlers — delete, add, wrap, unwrap, rename, change type"
```

---

## Task 8: Create JSON edit bridge

**Why:** Connects JsonEditOp to SyncEditor[JsonValue] — applies structural edits through the text CRDT.

**Files:**
- Create: `lang/json/edits/json_edit_bridge.mbt`

> **Note:** `apply_text_edit_internal` was already made pub in Task 3 Step 4. No duplicate change needed here.

- [ ] **Step 1: Update `lang/json/edits/moon.pkg`**

Add editor dependency:
```
import {
  "dowdiness/canopy/editor" @editor,
  "dowdiness/canopy/framework/core" @core,
  "dowdiness/canopy/lang/json/proj" @json_proj,
  "dowdiness/json" @json,
  "dowdiness/loom/core" @loomcore,
  "dowdiness/seam" @seam,
}
```

> **Note:** `@seam` is needed for the RenameKey test which parses CST and calls `SyntaxNode::from_cst`.

- [ ] **Step 2: Implement the bridge**

Create `lang/json/edits/json_edit_bridge.mbt`:

```moonbit
///|
pub fn apply_json_edit(
  editor : @editor.SyncEditor[@json.JsonValue],
  op : JsonEditOp,
  timestamp_ms : Int,
) -> Result[Unit, String] {
  let source = editor.get_text()
  let proj = match editor.get_proj_node() {
    Some(p) => p
    None => return Err("no projection available")
  }
  let source_map = editor.get_source_map()
  match compute_json_edit(op, source, proj, source_map) {
    Ok(Some((edits, focus_hint))) => {
      if edits.is_empty() {
        return Ok(())
      }
      // Apply in reverse document order to avoid position shifts
      let sorted = edits.copy()
      sorted.sort_by(fn(a, b) { b.start.compare(a.start) })
      let old_cursor = editor.get_cursor()
      for edit in sorted {
        editor.apply_text_edit_internal(
          edit.start,
          edit.delete_len,
          edit.inserted,
          timestamp_ms,
          true,
          false,
        )
      }
      match focus_hint {
        RestoreCursor => editor.move_cursor(old_cursor)
        MoveCursor(position~) => editor.move_cursor(position)
      }
      Ok(())
    }
    Ok(None) => Err("unhandled edit op: " + op.to_string())
    Err(msg) => Err(msg)
  }
}
```

- [ ] **Step 3: Run `moon check`**

```bash
moon check
```

- [ ] **Step 4: Commit**

```bash
git add lang/json/edits/
git commit -m "feat(json): add edit bridge connecting JsonEditOp to SyncEditor"
```

---

## Task 9: new_json_editor + end-to-end tests

**Why:** Wire everything together and prove the full pipeline works.

**Files:**
- Create: `lang/json/edits/sync_editor_json.mbt` — new_json_editor constructor
- Create: `lang/json/edits/integration_wbtest.mbt` — end-to-end tests

- [ ] **Step 1: Create `new_json_editor`**

Create `lang/json/edits/sync_editor_json.mbt`:

```moonbit
///|
/// Create a JSON projectional editor.
/// Uses SyncEditor::new_generic (no FlatProj dependency).
pub fn new_json_editor(
  agent_id : String,
  capture_timeout_ms? : Int = 500,
) -> @editor.SyncEditor[@json.JsonValue] {
  @editor.SyncEditor::new_generic(
    agent_id,
    fn(s) { @loom.new_imperative_parser(s, @json.json_grammar) },
    @json_proj.build_json_projection_memos,
    capture_timeout_ms~,
  )
}
```

> **Note:** Uses `new_generic` from Task 2 — returns 3 memos, no FlatProj. `lang/json/edits/moon.pkg` needs `"dowdiness/loom" @loom` if not already present.

- [ ] **Step 4: Write end-to-end integration tests**

Create `lang/json/edits/integration_wbtest.mbt`:

```moonbit
///|
test "new_json_editor — create and get text" {
  let editor = new_json_editor("test")
  editor.set_text("{\"a\": 1}")
  inspect(editor.get_text(), content="{\"a\": 1}")
}

///|
test "new_json_editor — projection pipeline works" {
  let editor = new_json_editor("test")
  editor.set_text("{\"a\": 1, \"b\": true}")
  editor.mark_dirty()
  let proj = editor.get_proj_node()
  match proj {
    Some(p) => {
      inspect(p.kind is @json.Object(_), content="true")
      inspect(p.children.length(), content="2")
      match p.children[0].kind {
        @json.Number(n) => inspect(n, content="1")
        _ => fail!("expected Number child for 'a'")
      }
    }
    None => fail!("expected projection")
  }
}

///|
test "new_json_editor — source map positions" {
  let editor = new_json_editor("test")
  editor.set_text("[1, 2, 3]")
  editor.mark_dirty()
  let sm = editor.get_source_map()
  let proj = editor.get_proj_node()
  match proj {
    Some(p) => {
      let range = sm.get_range(p.id())
      match range {
        Some(r) => {
          inspect(r.start, content="0")
          inspect(r.end, content="9")
        }
        None => fail!("expected range for root")
      }
    }
    None => fail!("expected projection")
  }
}

///|
test "new_json_editor — reconcile preserves IDs after edit" {
  let editor = new_json_editor("test")
  editor.set_text("{\"a\": 1, \"b\": 2}")
  editor.mark_dirty()
  let proj1 = editor.get_proj_node()
  let id1 = match proj1 {
    Some(p) => p.node_id
    None => { fail!("expected projection"); return }
  }
  // Edit: change value of "a"
  editor.set_text("{\"a\": 99, \"b\": 2}")
  editor.mark_dirty()
  let proj2 = editor.get_proj_node()
  let id2 = match proj2 {
    Some(p) => p.node_id
    None => { fail!("expected projection"); return }
  }
  // Root Object ID should be preserved (same_kind match)
  inspect(id1 == id2, content="true")
}

///|
test "new_json_editor — apply WrapInArray edit" {
  let editor = new_json_editor("test")
  editor.set_text("42")
  editor.mark_dirty()
  let proj = editor.get_proj_node()
  match proj {
    Some(p) => {
      let result = apply_json_edit(editor, WrapInArray(node_id=p.id()), 0)
      inspect(result is Ok(_), content="true")
      inspect(editor.get_text(), content="[42]")
    }
    None => fail!("expected projection")
  }
}

///|
test "new_json_editor — apply AddMember edit" {
  let editor = new_json_editor("test")
  editor.set_text("{}")
  editor.mark_dirty()
  let proj = editor.get_proj_node()
  match proj {
    Some(p) => {
      let result = apply_json_edit(editor, AddMember(object_id=p.id(), key="name"), 0)
      inspect(result is Ok(_), content="true")
      let text = editor.get_text()
      // Should contain the key and null value
      inspect(text, content="{\"name\": null}")
    }
    None => fail!("expected projection")
  }
}

///|
test "new_json_editor — error recovery" {
  let editor = new_json_editor("test")
  editor.set_text("{\"a\": }")
  editor.mark_dirty()
  // Should still produce a projection (parser recovers)
  let proj = editor.get_proj_node()
  inspect(proj is Some(_), content="true")
}

///|
test "new_json_editor — get_flat_proj returns None" {
  let editor = new_json_editor("test")
  editor.set_text("{}")
  editor.mark_dirty()
  let fp = editor.get_flat_proj()
  inspect(fp is None, content="true")
}
```

- [ ] **Step 5: Run full test suite**

```bash
moon check && moon test && moon build --target js
```

All tests must pass.

- [ ] **Step 6: Update snapshots if needed**

```bash
moon test --update
```

- [ ] **Step 7: `moon info && moon fmt`**

- [ ] **Step 8: Commit**

```bash
git add lang/json/ editor/sync_editor.mbt editor/pkg.generated.mbti
git commit -m "feat(json): add new_json_editor + end-to-end integration tests"
```

---

## Notes

### CST node text extraction — critical API difference

**SyntaxNode does NOT have a `.text()` method.** Only SyntaxToken has `.text()`. To extract text from CST nodes:

| What you need | How to get it |
|---------------|---------------|
| String value text | `node.token_text(StringToken.to_raw())` |
| Number value text | `node.token_text(NumberToken.to_raw())` |
| Bool detection | `node.find_token(TrueKeyword.to_raw()) is Some(_)` |
| Member key text | Iterate `child.all_children()`, find first `SyntaxElement::Token(t)` where `t.kind() == StringToken.to_raw()`, use `t.text()` |
| Value node in member | `member_node.nth_child(0)` |

Reference: `loom/examples/json/src/value_convert.mbt` lines 153-185, `loom/seam/syntax_node.mbt`.

### MemberNode CST structure

The JSON parser (`cst_parser.mbt` lines 144-156) builds MemberNode as:
```
MemberNode
  Token: StringToken (the key, including quotes)
  Token: ColonToken
  Node:  value node (StringValue, NumberValue, ObjectNode, etc.)
```

- Token children: accessed via `all_children()` or `find_token()`
- Node children: accessed via `nth_child(0)` or `children()`
- Key text: find first StringToken via `all_children()`, use `token.text()`
- Value: `member_node.nth_child(0)` returns the first (and only) node child

### Object child span design

Each Object ProjNode child uses the **MemberNode's span**, not the value's span:
```
Input: {"a": 1, "b": 2}
         ^^^^^   ^^^^^
       member 0  member 1

ProjNode { kind: Number(1.0), start: 1, end: 7, ... }  // "a": 1
ProjNode { kind: Number(2.0), start: 9, end: 15, ... } // "b": 2
```

This ensures:
- `SourceMap::get_range(child_id)` covers key+colon+value
- Delete removes the entire member (not just the value)
- Token spans (`key:0`, `key:1`) provide exact key locations within the member range

### String handling

- `parse_json_string()` in `value_convert.mbt` is made `pub` in Task 3.
- The projection builder uses `@json.parse_json_string(raw)` for both string values and member keys, ensuring proper unescaping of JSON escape sequences (`\"`, `\\`, `\n`, Unicode escapes, etc.).
- `json_escape()` in `proj_traits.mbt` is `pub` so edit handlers can use it for key insertion.
- `unparse` for `Error(_)` produces `"null"` (valid JSON), not `"null /* error: msg */"`.

### Comma handling in edits

Delete and add operations must handle commas correctly:
- Deleting with trailing comma: consume the comma + whitespace after
- Deleting without trailing comma: consume a leading comma + whitespace before
- Adding to empty object/array: no comma prefix
- Adding to non-empty: comma prefix (`, `)

### compute_unwrap guards

- Arrays: only unwrap if exactly 1 element. Returns `Err` for multi-element.
- Objects: only unwrap if exactly 1 member. Returns `Err` for multi-member.
- For objects, uses `Renderable::unparse(child.kind)` to get the value text, because the child's span covers the full member (key+colon+value), not just the value.

### Test count

Current: 524 tests. JSON should add ~30-40 tests across proj_traits, proj_node, and integration.

### Import chain

```
loom/examples/json/ (parser, grammar, JsonValue + TreeNode/Renderable impls, json_escape)
  |
canopy/lang/json/proj/ (projection builders, memo)
  |
canopy/lang/json/edits/ (edit handlers, bridge, new_json_editor)
  |
canopy/editor/ (SyncEditor -- shared infrastructure)
```

No circular dependencies. editor/ does not import lang/json/.

### SyntaxKind matching

The projection builder uses `@json.ObjectNode.to_raw()` etc. to match syntax kinds. The JSON module's `SyntaxKind` has a `to_raw()` method via the `@seam.ToRawKind` trait. This works because `to_raw()` returns `@seam.RawKind` which is what `SyntaxNode::kind()` returns.

### moon.pkg dependencies by package

**`lang/json/proj/moon.pkg`:**
```
dowdiness/canopy/framework/core, dowdiness/incr, dowdiness/json,
dowdiness/loom, dowdiness/loom/core, dowdiness/seam,
moonbitlang/core/strconv
```

**`lang/json/edits/moon.pkg`:**
```
dowdiness/canopy/editor, dowdiness/canopy/framework/core,
dowdiness/canopy/lang/json/proj, dowdiness/json, dowdiness/loom,
dowdiness/loom/core, dowdiness/seam
```
