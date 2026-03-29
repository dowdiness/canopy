# JSON Projectional Editor — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a JSON projection pipeline that proves framework/core works with a second real language, validated by tests.

**Architecture:** Trait impls in loom JSON module (type owner), projection builders in `canopy/lang/json/proj/`, edit handlers in `canopy/lang/json/edits/`. SyncEditor generalized to support languages without FlatProj.

**Tech Stack:** MoonBit, loom parser framework, framework/core (ProjNode, SourceMap, reconcile)

**Design spec:** `docs/design/2026-03-29-json-projectional-editor-design.md`

---

## Phase overview

| Phase | Tasks | What |
|-------|-------|------|
| A — Prerequisite | 1 | Generalize SyncEditor proj_memo to optional |
| B — Loom submodule | 2 | TreeNode + Renderable impls for JsonValue |
| C — Projection pipeline | 3–4 | syntax_to_proj_node, populate_token_spans, memo builder |
| D — Edit handlers | 5–6 | JsonEditOp, compute_json_edit, edit bridge |
| E — Integration | 7 | SyncEditor::new_json, end-to-end tests |

Each task must pass all tests before proceeding.

---

## Task 1: Generalize SyncEditor proj_memo to optional

**Why:** SyncEditor hard-wires `proj_memo: Memo[VersionedFlatProj]`. JSON has no FlatProj. Make it optional so non-FlatProj languages can use SyncEditor.

**Files:**
- Modify: `editor/sync_editor.mbt` — change `proj_memo` field type, `new` constructor signature
- Modify: `editor/projection_memo.mbt` — update `build_lambda_projection_memos` return type, `get_flat_proj`

- [ ] **Step 1: Change `proj_memo` field to optional**

In `editor/sync_editor.mbt`, change the struct field:
```moonbit
// Before:
priv proj_memo : @incr.Memo[@lambda_flat.VersionedFlatProj]

// After:
priv proj_memo : @incr.Memo[@lambda_flat.VersionedFlatProj]?
```

- [ ] **Step 2: Update `SyncEditor::new` constructor signature**

Change the `build_memos` callback return type and the struct construction:

```moonbit
fn[T] SyncEditor::new(
  agent_id : String,
  make_parser : (String) -> @loom.ImperativeParser[T],
  build_memos : (
    @incr.Runtime,
    @incr.Signal[String],
    @incr.Signal[@seam.SyntaxNode?],
    @loom.ImperativeParser[T],
  ) -> (
    @incr.Memo[@lambda_flat.VersionedFlatProj]?,  // <- Optional now
    @incr.Memo[@proj.ProjNode[T]?],
    @incr.Memo[Map[@proj.NodeId, @proj.ProjNode[T]]],
    @incr.Memo[@proj.SourceMap],
  ),
  capture_timeout_ms? : Int = 500,
) -> SyncEditor[T] {
```

- [ ] **Step 3: Update `build_lambda_projection_memos` to return `Some(...)`**

In `editor/projection_memo.mbt`, change the return type to match:
```moonbit
pub fn build_lambda_projection_memos(
  ...
) -> (
  @incr.Memo[@lambda_flat.VersionedFlatProj]?,
  ...
)
```

And wrap the return value: `(Some(proj_memo), cached_proj_node, registry_memo, source_map_memo)`

- [ ] **Step 4: Update `get_flat_proj` to handle None**

```moonbit
pub fn[T] SyncEditor::get_flat_proj(self : SyncEditor[T]) -> @proj.FlatProj? {
  match self.proj_memo {
    Some(memo) => Some(memo.get().flat_proj)
    None => None
  }
}
```

- [ ] **Step 5: Run `moon check` and fix any compilation errors**

The `apply_tree_edit` bridge in `tree_edit_bridge.mbt` calls `self.get_flat_proj()` which already returns `Option` — no change needed there.

```bash
moon check && moon test
```

Expected: all 524+ tests pass.

- [ ] **Step 6: `moon info && moon fmt`**

- [ ] **Step 7: Commit**

```bash
git add editor/sync_editor.mbt editor/projection_memo.mbt editor/pkg.generated.mbti
git commit -m "refactor(editor): make SyncEditor proj_memo optional for non-FlatProj languages"
```

---

## Task 2: Add TreeNode + Renderable impls for JsonValue

**Why:** JsonValue needs these traits for reconciliation and rendering in the projection pipeline.

**Files:**
- Modify: `loom/examples/json/src/moon.pkg` — may need alias adjustment
- Create: `loom/examples/json/src/proj_traits.mbt` — trait impls
- Create: `loom/examples/json/src/proj_traits_test.mbt` — tests

- [ ] **Step 1: Check if `@core.TreeNode` is accessible**

In the JSON module, `@core` already refers to `dowdiness/loom/core` which defines TreeNode and Renderable. Verify:

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
    Object(members) => members.map(m => m.1)
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
      if s.ends_with(".0") {
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
    Object(members) => "{" + members.map(m => m.0).join(", ") + "}"
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
      if s.ends_with(".0") { s.substring(end=s.length() - 2) } else { s }
    }
    String(s) => "\"" + json_escape(s) + "\""
    Array(items) =>
      if items.is_empty() {
        "[]"
      } else {
        let indent = "  ".repeat(depth + 1)
        let close_indent = "  ".repeat(depth)
        let parts = items.map(item => indent + json_unparse(item, depth + 1))
        "[\n" + parts.join(",\n") + "\n" + close_indent + "]"
      }
    Object(members) =>
      if members.is_empty() {
        "{}"
      } else {
        let indent = "  ".repeat(depth + 1)
        let close_indent = "  ".repeat(depth)
        let parts = members.map(m =>
          indent + "\"" + json_escape(m.0) + "\": " + json_unparse(m.1, depth + 1)
        )
        "{\n" + parts.join(",\n") + "\n" + close_indent + "}"
      }
    Error(msg) => "null /* error: " + msg + " */"
  }
}

///|
fn json_escape(s : String) -> String {
  let buf = @buffer.new()
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
git add src/proj_traits.mbt src/proj_traits_test.mbt src/moon.pkg src/pkg.generated.mbti
git commit -m "feat(json): implement TreeNode and Renderable for JsonValue"
```

- [ ] **Step 9: Push loom and bump submodule in canopy**

```bash
cd loom && git push
cd .. && git add loom && git commit -m "chore: bump loom (TreeNode/Renderable for JsonValue)"
```

---

## Task 3: Create lang/json/proj/ — projection builder

**Why:** Converts JSON CST (SyntaxNode) → ProjNode[JsonValue] for the framework pipeline.

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
  inspect(proj.kind is @json.Number(_), content="true")
}

///|
test "syntax_to_proj_node — string" {
  let (proj, errors) = parse_to_proj_node("\"hello\"")
  inspect(errors.length(), content="0")
  inspect(proj.kind is @json.String(_), content="true")
}

///|
test "syntax_to_proj_node — array" {
  let (proj, errors) = parse_to_proj_node("[1, 2, 3]")
  inspect(errors.length(), content="0")
  inspect(proj.kind is @json.Array(_), content="true")
  inspect(proj.children.length(), content="3")
}

///|
test "syntax_to_proj_node — object" {
  let (proj, errors) = parse_to_proj_node("{\"a\": 1, \"b\": true}")
  inspect(errors.length(), content="0")
  inspect(proj.kind is @json.Object(_), content="true")
  // Object children are values only (keys are metadata)
  inspect(proj.children.length(), content="2")
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
  inspect(root_range is Some(_), content="true")
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
```

- [ ] **Step 4: Implement `syntax_to_proj_node`**

Create `lang/json/proj/proj_node.mbt`:

```moonbit
// CST → ProjNode[JsonValue] builder for JSON.

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
    let text = node.text()
    // Strip surrounding quotes
    let inner = if text.length() >= 2 {
      text.substring(start=1, end=text.length() - 1)
    } else {
      text
    }
    ProjNode::new(
      @json.String(inner),
      node.start(), node.end(),
      @core.next_proj_node_id(counter),
      [],
    )
  } else if kind == @json.NumberValue.to_raw() {
    let text = node.text()
    let n = try { @strconv.parse_double(text) } catch { _ => 0.0 }
    ProjNode::new(
      @json.Number(n),
      node.start(), node.end(),
      @core.next_proj_node_id(counter),
      [],
    )
  } else if kind == @json.BoolValue.to_raw() {
    let text = node.text()
    let b = text == "true"
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
    let children = node.children()
    if children.length() > 0 {
      syntax_to_proj_node(children[0], counter)
    } else {
      ProjNode::new(
        @json.Null,
        node.start(), node.end(),
        @core.next_proj_node_id(counter),
        [],
      )
    }
  } else if kind == @json.MemberNode.to_raw() {
    // MemberNode shouldn't be visited directly — parent Object handles it
    // But handle gracefully if called
    let children = node.children()
    if children.length() > 0 {
      syntax_to_proj_node(children[children.length() - 1], counter)
    } else {
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
      let (key, value_node) = extract_member(child, counter)
      members.push((key, value_node.kind))
      children.push(value_node)
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
    let child_kind = child.kind()
    // Skip token children (brackets, commas)
    if not(@json.SyntaxKind::is_token(@json.SyntaxKind::from_raw(child_kind))) {
      let proj = syntax_to_proj_node(child, counter)
      items.push(proj.kind)
      children.push(proj)
    }
  }
  ProjNode::new(
    @json.Array(items),
    node.start(), node.end(),
    @core.next_proj_node_id(counter),
    children,
  )
}

///|
fn extract_member(
  member_node : @seam.SyntaxNode,
  counter : Ref[Int],
) -> (String, ProjNode[@json.JsonValue]) {
  let mut key = ""
  let mut value_proj : ProjNode[@json.JsonValue]? = None
  for child in member_node.children() {
    let child_kind = child.kind()
    if child_kind == @json.StringValue.to_raw() && key == "" {
      // First StringValue is the key
      let text = child.text()
      key = if text.length() >= 2 {
        text.substring(start=1, end=text.length() - 1)
      } else {
        text
      }
    } else if not(@json.SyntaxKind::is_token(@json.SyntaxKind::from_raw(child_kind))) && value_proj is None {
      // First non-token, non-key child is the value
      value_proj = Some(syntax_to_proj_node(child, counter))
    }
  }
  let value = match value_proj {
    Some(v) => v
    None =>
      ProjNode::new(
        @json.Error("missing value"),
        member_node.start(), member_node.end(),
        @core.next_proj_node_id(counter),
        [],
      )
  }
  (key, value)
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
  let errors = diagnostics.map(d => d.message)
  let root = syntax_to_proj_node(syntax_node, Ref::new(0))
  (root, errors)
}
```

> **Note:** The exact SyntaxKind matching may need adjustment. Check if `@json.SyntaxKind::from_raw` exists; if not, use raw int comparisons or add a helper. Also verify `@json.parse_cst` signature — it may be `parse_cst(source)` returning `(CstNode, Array[Diagnostic])`.

- [ ] **Step 5: Implement `populate_token_spans`**

Create `lang/json/proj/populate_token_spans.mbt`:

```moonbit
// Lambda-specific token span extraction for JSON objects.
// Extracts key name spans from MemberNode StringToken children.

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
  collect_key_spans(source_map, syntax_root, proj_root)
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
          // Find the key StringToken (first token child that is a StringToken)
          let key_token = child.find_token(@json.StringValue.to_raw())
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
            // Find the value syntax node within this MemberNode
            for member_child in child.children() {
              let mk = member_child.kind()
              if not(@json.SyntaxKind::is_token(@json.SyntaxKind::from_raw(mk))) {
                // First non-key node child
                if mk != @json.StringValue.to_raw() || member_idx > 0 {
                  collect_key_spans(
                    source_map,
                    member_child,
                    proj_node.children[member_idx],
                  )
                }
                break
              }
            }
          }
          member_idx = member_idx + 1
        }
      }
    }
    @json.Array(_) => {
      let mut child_idx = 0
      for child in syntax_node.children() {
        let ck = child.kind()
        if not(@json.SyntaxKind::is_token(@json.SyntaxKind::from_raw(ck))) {
          if child_idx < proj_node.children.length() {
            collect_key_spans(source_map, child, proj_node.children[child_idx])
          }
          child_idx = child_idx + 1
        }
      }
    }
    _ => ()
  }
}
```

> **Note:** The `find_token` method may not match StringValue (a node kind, not token kind). The key token is actually a `StringToken` inside the MemberNode. Adjust the lookup to scan for `StringToken.to_raw()` instead of `StringValue.to_raw()`. Verify against the actual CST structure by inspecting a parsed JSON object's SyntaxNode tree.

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

## Task 4: Create memo builder for JSON

**Why:** SyncEditor needs a `build_memos` callback that produces ProjNode, registry, and SourceMap memos from the parser signals.

**Files:**
- Create: `lang/json/proj/json_memo.mbt` — build_json_projection_memos

- [ ] **Step 1: Implement `build_json_projection_memos`**

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
  @incr.Memo[@lambda_flat.VersionedFlatProj]?,
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

  // Registry memo: NodeId → ProjNode lookup
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

  (None, proj_memo, registry_memo, source_map_memo)
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

> **Note:** This imports `@lambda_flat.VersionedFlatProj` for the return type (to match SyncEditor's `build_memos` callback). Add `"dowdiness/canopy/lang/lambda/flat" @lambda_flat` to `lang/json/proj/moon.pkg`. Also add `"dowdiness/incr" @incr` and `"dowdiness/loom" @loom`.

- [ ] **Step 2: Update `lang/json/proj/moon.pkg` with all needed imports**

```
import {
  "dowdiness/canopy/framework/core" @core,
  "dowdiness/canopy/lang/lambda/flat" @lambda_flat,
  "dowdiness/incr" @incr,
  "dowdiness/json" @json,
  "dowdiness/loom" @loom,
  "dowdiness/loom/core" @loomcore,
  "dowdiness/seam" @seam,
  "moonbitlang/core/buffer" @buffer,
  "moonbitlang/core/strconv",
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

## Task 5: Create lang/json/edits/ — edit handlers

**Why:** Provides structural JSON edit operations (add member, delete, wrap, rename key, etc.).

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

///|
pub(all) struct JsonSpanEdit {
  start : Int
  delete_len : Int
  inserted : String
} derive(Show, Eq)

///|
pub(all) enum JsonFocusHint {
  RestoreCursor
  MoveCursor(position~ : Int)
} derive(Show, Eq)
```

- [ ] **Step 3: Write edit handler tests**

Create `lang/json/edits/compute_json_edit_wbtest.mbt`:

```moonbit
///|
test "Delete member from object" {
  let result = apply_edit("{\"a\": 1, \"b\": 2}", Delete(node_id=find_first_child_id("{\"a\": 1, \"b\": 2}")))
  // After deleting first value, object should have one member
  inspect(result is Ok(_), content="true")
}

///|
test "AddMember to object" {
  let (proj, _) = @json_proj.parse_to_proj_node("{\"a\": 1}")
  let sm = @core.SourceMap::from_ast(proj)
  let result = compute_json_edit(
    AddMember(object_id=proj.id(), key="b"),
    "{\"a\": 1}",
    proj,
    sm,
  )
  inspect(result is Ok(_), content="true")
}

///|
test "WrapInArray" {
  let (proj, _) = @json_proj.parse_to_proj_node("42")
  let sm = @core.SourceMap::from_ast(proj)
  let result = compute_json_edit(
    WrapInArray(node_id=proj.id()),
    "42",
    proj,
    sm,
  )
  match result {
    Ok(Some((edits, _))) => {
      // Should produce edits that wrap 42 → [42]
      inspect(edits.length() > 0, content="true")
    }
    _ => fail("Expected Ok(Some(...))")
  }
}
```

> **Note:** These tests are sketches. The actual assertions will depend on the exact edit output. Use `moon test --update` for snapshot-based verification after implementation.

- [ ] **Step 4: Implement `compute_json_edit`**

Create `lang/json/edits/compute_json_edit.mbt`:

```moonbit
using @core {type ProjNode, type NodeId, type SourceMap}
using @loomcore {type Range}

///|
pub fn compute_json_edit(
  op : JsonEditOp,
  source : String,
  proj : ProjNode[@json.JsonValue],
  source_map : SourceMap,
) -> Result[(Array[JsonSpanEdit], JsonFocusHint)?, String] {
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
  proj : ProjNode[@json.JsonValue],
  source_map : SourceMap,
) -> Result[(Array[JsonSpanEdit], JsonFocusHint)?, String] {
  let range = match source_map.get_range(node_id) {
    Some(r) => r
    None => return Err("node not in source map")
  }
  // For object members, we need to delete the entire member including key and comma
  // For array elements, delete element and adjacent comma
  // Simple approach: replace with placeholder or delete the span
  let delete_start = range.start
  let delete_end = range.end
  // Try to consume a trailing comma + whitespace
  let mut end = delete_end
  while end < source.length() {
    let ch = source[end]
    if ch == ',' {
      end = end + 1
      // Skip whitespace after comma
      while end < source.length() && (source[end] == ' ' || source[end] == '\n' || source[end] == '\t' || source[end] == '\r') {
        end = end + 1
      }
      break
    } else if ch == ' ' || ch == '\n' || ch == '\t' || ch == '\r' {
      end = end + 1
    } else {
      break
    }
  }
  let edits = [JsonSpanEdit::{ start: delete_start, delete_len: end - delete_start, inserted: "" }]
  Ok(Some((edits, RestoreCursor)))
}

///|
fn compute_add_member(
  object_id : NodeId,
  key : String,
  source : String,
  _proj : ProjNode[@json.JsonValue],
  source_map : SourceMap,
) -> Result[(Array[JsonSpanEdit], JsonFocusHint)?, String] {
  let range = match source_map.get_range(object_id) {
    Some(r) => r
    None => return Err("object not in source map")
  }
  // Insert before the closing brace
  let insert_pos = range.end - 1
  let needs_comma = source.substring(start=range.start + 1, end=insert_pos).trim(" \n\t\r").length() > 0
  let prefix = if needs_comma { ", " } else { "" }
  let new_member = prefix + "\"" + key + "\": null"
  let edits = [JsonSpanEdit::{ start: insert_pos, delete_len: 0, inserted: new_member }]
  let cursor_pos = insert_pos + prefix.length() + key.length() + 4 // after ": "
  Ok(Some((edits, MoveCursor(position=cursor_pos))))
}

///|
fn compute_add_element(
  array_id : NodeId,
  source : String,
  _proj : ProjNode[@json.JsonValue],
  source_map : SourceMap,
) -> Result[(Array[JsonSpanEdit], JsonFocusHint)?, String] {
  let range = match source_map.get_range(array_id) {
    Some(r) => r
    None => return Err("array not in source map")
  }
  let insert_pos = range.end - 1
  let needs_comma = source.substring(start=range.start + 1, end=insert_pos).trim(" \n\t\r").length() > 0
  let prefix = if needs_comma { ", " } else { "" }
  let edits = [JsonSpanEdit::{ start: insert_pos, delete_len: 0, inserted: prefix + "null" }]
  Ok(Some((edits, MoveCursor(position=insert_pos + prefix.length()))))
}

///|
fn compute_wrap_in_array(
  node_id : NodeId,
  _source : String,
  source_map : SourceMap,
) -> Result[(Array[JsonSpanEdit], JsonFocusHint)?, String] {
  let range = match source_map.get_range(node_id) {
    Some(r) => r
    None => return Err("node not in source map")
  }
  let edits = [
    JsonSpanEdit::{ start: range.start, delete_len: 0, inserted: "[" },
    JsonSpanEdit::{ start: range.end, delete_len: 0, inserted: "]" },
  ]
  Ok(Some((edits, RestoreCursor)))
}

///|
fn compute_wrap_in_object(
  node_id : NodeId,
  key : String,
  _source : String,
  source_map : SourceMap,
) -> Result[(Array[JsonSpanEdit], JsonFocusHint)?, String] {
  let range = match source_map.get_range(node_id) {
    Some(r) => r
    None => return Err("node not in source map")
  }
  let prefix = "{\"" + key + "\": "
  let edits = [
    JsonSpanEdit::{ start: range.start, delete_len: 0, inserted: prefix },
    JsonSpanEdit::{ start: range.end, delete_len: 0, inserted: "}" },
  ]
  Ok(Some((edits, RestoreCursor)))
}

///|
fn compute_unwrap(
  node_id : NodeId,
  source : String,
  _proj : ProjNode[@json.JsonValue],
  source_map : SourceMap,
) -> Result[(Array[JsonSpanEdit], JsonFocusHint)?, String] {
  let range = match source_map.get_range(node_id) {
    Some(r) => r
    None => return Err("node not in source map")
  }
  let text = source.substring(start=range.start, end=range.end)
  // For arrays: [value] → value (only if single element)
  // For objects: {"key": value} → value (only if single member)
  // Simple approach: extract content between delimiters
  let inner = if text.length() >= 2 {
    text.substring(start=1, end=text.length() - 1).trim(" \n\t\r")
  } else {
    return Err("cannot unwrap: too short")
  }
  // For objects, strip key prefix
  let content = if text[0] == '{' {
    match inner.index_of(":") {
      Some(colon) => inner.substring(start=colon + 1).trim(" \n\t\r")
      None => inner
    }
  } else {
    inner
  }
  let edits = [JsonSpanEdit::{ start: range.start, delete_len: range.end - range.start, inserted: content }]
  Ok(Some((edits, RestoreCursor)))
}

///|
fn compute_change_type(
  node_id : NodeId,
  new_type : String,
  source_map : SourceMap,
) -> Result[(Array[JsonSpanEdit], JsonFocusHint)?, String] {
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
  let edits = [JsonSpanEdit::{ start: range.start, delete_len: range.end - range.start, inserted: replacement }]
  Ok(Some((edits, MoveCursor(position=range.start + replacement.length()))))
}

///|
fn compute_rename_key(
  object_id : NodeId,
  key_index : Int,
  new_key : String,
  source_map : SourceMap,
) -> Result[(Array[JsonSpanEdit], JsonFocusHint)?, String] {
  let role = "key:" + key_index.to_string()
  let span = match source_map.get_token_span(object_id, role) {
    Some(s) => s
    None => return Err("key span not found for " + role)
  }
  // Replace the entire quoted key token
  let replacement = "\"" + new_key + "\""
  let edits = [JsonSpanEdit::{ start: span.start, delete_len: span.end - span.start, inserted: replacement }]
  Ok(Some((edits, RestoreCursor)))
}

///|
fn compute_commit(
  node_id : NodeId,
  new_value : String,
  source_map : SourceMap,
) -> Result[(Array[JsonSpanEdit], JsonFocusHint)?, String] {
  let range = match source_map.get_range(node_id) {
    Some(r) => r
    None => return Err("node not in source map")
  }
  let edits = [JsonSpanEdit::{ start: range.start, delete_len: range.end - range.start, inserted: new_value }]
  Ok(Some((edits, MoveCursor(position=range.start + new_value.length()))))
}
```

- [ ] **Step 5: Run `moon check` and fix compilation errors**

```bash
moon check
```

- [ ] **Step 6: Update tests with snapshot assertions**

```bash
moon test --update
```

Review the snapshot outputs to verify correctness.

- [ ] **Step 7: `moon info && moon fmt`**

- [ ] **Step 8: Commit**

```bash
git add lang/json/edits/
git commit -m "feat(json): add edit handlers — delete, add, wrap, unwrap, rename, change type"
```

---

## Task 6: Create JSON edit bridge

**Why:** Connects JsonEditOp to SyncEditor[JsonValue] — applies structural edits through the text CRDT.

**Files:**
- Create: `lang/json/edits/json_edit_bridge.mbt`
- Modify: `editor/sync_editor_text.mbt` — make `apply_text_edit_internal` pub

- [ ] **Step 1: Make `apply_text_edit_internal` public**

In `editor/sync_editor_text.mbt`, change:
```moonbit
// Before:
fn[T] SyncEditor::apply_text_edit_internal(
// After:
pub fn[T] SyncEditor::apply_text_edit_internal(
```

- [ ] **Step 2: Update `lang/json/edits/moon.pkg`**

Add editor dependency:
```
import {
  "dowdiness/canopy/editor" @editor,
  "dowdiness/canopy/framework/core" @core,
  "dowdiness/canopy/lang/json/proj" @json_proj,
  "dowdiness/json" @json,
  "dowdiness/loom/core" @loomcore,
}
```

- [ ] **Step 3: Implement the bridge**

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
      sorted.sort_by((a, b) => b.start.compare(a.start))
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

- [ ] **Step 4: Run `moon check`**

```bash
moon check
```

- [ ] **Step 5: Commit**

```bash
git add lang/json/edits/ editor/sync_editor_text.mbt editor/pkg.generated.mbti
git commit -m "feat(json): add edit bridge connecting JsonEditOp to SyncEditor"
```

---

## Task 7: SyncEditor::new_json + end-to-end tests

**Why:** Wire everything together and prove the full pipeline works.

**Files:**
- Modify: `editor/sync_editor.mbt` — make `SyncEditor::new` pub
- Create: `lang/json/edits/sync_editor_json.mbt` — new_json constructor
- Create: `lang/json/edits/integration_wbtest.mbt` — end-to-end tests

- [ ] **Step 1: Make `SyncEditor::new` public**

In `editor/sync_editor.mbt`:
```moonbit
// Before:
fn[T] SyncEditor::new(
// After:
pub fn[T] SyncEditor::new(
```

- [ ] **Step 2: Create `SyncEditor::new_json`**

Create `lang/json/edits/sync_editor_json.mbt`:

```moonbit
///|
pub fn new_json_editor(
  agent_id : String,
  capture_timeout_ms? : Int = 500,
) -> @editor.SyncEditor[@json.JsonValue] {
  @editor.SyncEditor::new(
    agent_id,
    fn(s) { @loom.new_imperative_parser(s, @json.json_grammar) },
    @json_proj.build_json_projection_memos,
    capture_timeout_ms~,
  )
}
```

> **Note:** Add `"dowdiness/loom" @loom` to `lang/json/edits/moon.pkg` if not already present.

- [ ] **Step 3: Write end-to-end integration tests**

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
  inspect(proj is Some(_), content="true")
  match proj {
    Some(p) => {
      inspect(p.kind is @json.Object(_), content="true")
      inspect(p.children.length(), content="2")
    }
    None => fail("expected projection")
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
      inspect(range is Some(_), content="true")
    }
    None => fail("expected projection")
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
    None => { fail("expected projection"); return }
  }
  // Edit: change value of "a"
  editor.set_text("{\"a\": 99, \"b\": 2}")
  editor.mark_dirty()
  let proj2 = editor.get_proj_node()
  let id2 = match proj2 {
    Some(p) => p.node_id
    None => { fail("expected projection"); return }
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
    None => fail("expected projection")
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
      // Should insert a new member
      let text = editor.get_text()
      inspect(text.contains("\"name\""), content="true")
      inspect(text.contains("null"), content="true")
    }
    None => fail("expected projection")
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

- [ ] **Step 4: Run full test suite**

```bash
moon check && moon test && moon build --target js
```

All tests must pass.

- [ ] **Step 5: Update snapshots if needed**

```bash
moon test --update
```

- [ ] **Step 6: `moon info && moon fmt`**

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat(json): add SyncEditor::new_json + end-to-end integration tests"
```

---

## Notes

### SyntaxKind matching

The projection builder uses `@json.ObjectNode.to_raw()` etc. to match syntax kinds. Verify that MoonBit resolves these correctly — the JSON module's `SyntaxKind` has a `to_raw()` method via the `@seam.ToRawKind` trait.

### String handling

JSON strings have quotes and escape sequences. The projection builder strips quotes for `String(inner)`. The `unparse` adds them back. Make sure this round-trips correctly for strings with escapes (`\"`, `\\`, `\n`, etc.).

### Comma handling in edits

Delete and add operations must handle commas correctly:
- Deleting the last member: no trailing comma to clean up
- Deleting a middle member: clean up trailing comma
- Adding to empty object/array: no comma prefix
- Adding to non-empty: comma prefix

### Test count

Current: 524 tests. JSON should add ~30-40 tests across proj_traits, proj_node, and integration.

### Import chain

```
loom/examples/json/ (parser, grammar, JsonValue + trait impls)
  ↓
canopy/lang/json/proj/ (projection builders, memo)
  ↓
canopy/lang/json/edits/ (edit handlers, bridge, new_json)
  ↓
canopy/editor/ (SyncEditor — shared infrastructure)
```

No circular dependencies. editor/ does not import lang/json/.
