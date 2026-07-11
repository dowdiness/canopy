# ProseMirror + CodeMirror 6 Integration — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the contenteditable editor with ProseMirror (structural shell) + CodeMirror 6 (inline leaf editors), keeping eg-walker CRDT as source of truth.

**Architecture:** PM schema mirrors AST (ProjNode). Leaf nodes use CM6 NodeViews for text editing. A TypeScript bridge routes edits through the CRDT and reconciles PM state from ProjNode. Dual-selection model: PM owns structural selection, CM6 owns intra-leaf selection.

**Tech Stack:** ProseMirror, CodeMirror 6, TypeScript, Vite, MoonBit (JS target)

**Spec:** `docs/plans/2026-03-18-prosemirror-codemirror-integration-design.md`

---

## File Structure

### New files (examples/prosemirror/)

| File | Responsibility |
|---|---|
| `examples/prosemirror/package.json` | Dependencies: prosemirror-*, @codemirror/*, vite, typescript |
| `examples/prosemirror/tsconfig.json` | TypeScript config |
| `examples/prosemirror/vite.config.ts` | Vite config importing MoonBit JS (same pattern as `examples/web/`) |
| `examples/prosemirror/index.html` | Entry HTML |
| `examples/prosemirror/src/main.ts` | App entry point — create editor, mount PM |
| `examples/prosemirror/src/schema.ts` | PM schema definition (AST → PM node types) |
| `examples/prosemirror/src/convert.ts` | ProjNode ↔ PM doc bidirectional conversion |
| `examples/prosemirror/src/bridge.ts` | CrdtBridge — outbound (PM→CRDT) + inbound (CRDT→PM) |
| `examples/prosemirror/src/reconciler.ts` | Tree-diff ProjNode vs PM doc → PM transaction |
| `examples/prosemirror/src/leaf-view.ts` | TermLeafView — CM6 NodeView for atom nodes |
| `examples/prosemirror/src/lambda-view.ts` | LambdaView — structural NodeView with inline CM6 for param |
| `examples/prosemirror/src/let-def-view.ts` | LetDefView — structural NodeView with inline CM6 for name |
| `examples/prosemirror/src/peer-cursors.ts` | PeerCursorDistributor + PM/CM6 decoration rendering |
| `examples/prosemirror/src/types.ts` | Shared TypeScript types (ProjNode JSON shape, etc.) |

### Modified files (MoonBit — prerequisites)

| File | Change |
|---|---|
| `projection/proj_node.mbt` | Add `Unbound` to `same_kind_tag` |
| `projection/source_map.mbt` | (Phase 3) Expose token-level spans if needed |
| `projection/flat_proj.mbt` | Stabilize Module node_id across rebuilds |
| `crdt.mbt` | Add position-based FFI: `insert_at`, `delete_at`, `get_proj_node_json`, `get_source_map_json` |
| `editor/sync_editor_text.mbt` | Add `insert_at(pos, char)` / `delete_at(pos)` methods |

---

## Phase 0: MoonBit Prerequisites

### Task 0.1: Add `Unbound` to `same_kind_tag`

**Files:**
- Modify: `projection/proj_node.mbt:304`
- Test: `projection/proj_node_wbtest.mbt` (or `_test.mbt`)

- [ ] **Step 1: Read the current `same_kind_tag` function**

Read `projection/proj_node.mbt` around line 304. The function matches Term variant pairs. `Unbound` is missing.

- [ ] **Step 2: Add the missing arm**

```moonbit
// In same_kind_tag, add before the catch-all:
    (Unbound(_), Unbound(_)) => true
```

- [ ] **Step 3: Run tests**

Run: `moon test`
Expected: PASS (no existing test should break)

- [ ] **Step 4: Commit**

```bash
git add projection/proj_node.mbt
git commit -m "fix(projection): add Unbound to same_kind_tag for reconciler matching"
```

### Task 0.2: Stabilize Module node_id in FlatProj

**Files:**
- Modify: `projection/flat_proj.mbt` (the `to_proj_node` or `FlatProj::to_proj_node` function)
- Modify: `editor/projection_memo.mbt` (pass previous Module ID as seed)

- [ ] **Step 1: Read `FlatProj::to_proj_node` and `projection_memo.mbt`**

Understand where the Module ProjNode ID is allocated. Find where the memo rebuilds the ProjNode.

- [ ] **Step 2: Write a test that checks Module ID stability**

In a whitebox test file, parse the same text twice and verify the Module node_id is preserved when the content hasn't changed structurally.

- [ ] **Step 3: Run test to verify it fails**

Run: `moon test`
Expected: FAIL — Module ID changes on rebuild.

- [ ] **Step 4: Modify `FlatProj::to_proj_node` to accept an optional previous Module ID**

Add parameter `prev_module_id : Int?` to the function. When `Some(id)`, reuse that ID for the new Module node instead of allocating fresh. The memo in `projection_memo.mbt` passes the previous ProjNode's root ID when available.

- [ ] **Step 5: Run test to verify it passes**

Run: `moon test`
Expected: PASS

- [ ] **Step 6: Run full test suite and format**

Run: `moon test && moon info && moon fmt`

- [ ] **Step 7: Commit**

```bash
git add projection/flat_proj.mbt editor/projection_memo.mbt
git commit -m "fix(projection): stabilize Module node_id across FlatProj rebuilds"
```

### Task 0.3: Add position-based edit API to SyncEditor

**Files:**
- Modify: `editor/sync_editor_text.mbt`
- Modify: `crdt.mbt` (FFI exports)

- [ ] **Step 1: Read `sync_editor_text.mbt` to understand existing `insert` / `delete`**

These are cursor-based. We need position-based variants that don't mutate the cursor.

- [ ] **Step 2: Write whitebox tests for `insert_at` and `delete_at`**

```moonbit
test "insert_at inserts at specified position without moving cursor" {
  let editor = SyncEditor::new("test-agent")
  editor.set_text("hello")
  editor.move_cursor(0) // cursor at start
  editor.insert_at(5, "!", 0) // insert at end
  inspect!(editor.get_text(), content="hello!")
  inspect!(editor.get_cursor(), content="0") // cursor unchanged
}

test "delete_at deletes at specified position without moving cursor" {
  let editor = SyncEditor::new("test-agent")
  editor.set_text("hello!")
  editor.move_cursor(0)
  editor.delete_at(5, 0) // delete '!' at position 5
  inspect!(editor.get_text(), content="hello")
  inspect!(editor.get_cursor(), content="0")
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `moon test`
Expected: FAIL — methods not defined.

- [ ] **Step 4: Implement `insert_at` and `delete_at`**

In `editor/sync_editor_text.mbt`. **Important:** Do NOT implement as save/restore cursor — that would interact badly with `apply_local_text_change` and incremental parsing. Instead, implement at the same level as `insert_and_record`, directly calling the CRDT doc API with positional operations and triggering the parser with correct edit spans:

```moonbit
///|
/// Insert a character at a specific position without moving the cursor.
/// Uses @text.Pos::at(position) to target the exact CRDT position.
pub fn SyncEditor::insert_at(
  self : SyncEditor,
  position : Int,
  text : String,
  timestamp_ms : Int,
) -> Unit {
  // Record undo capture at the given position
  self.undo_manager.capture(position, timestamp_ms)
  // Insert directly at position via CRDT doc API
  let ops = self.doc.insert(@text.Pos::at(position), text)
  self.undo_manager.push_ops(ops)
  // Trigger incremental re-parse with correct edit span
  self.apply_local_text_change(@parser.Edit::insert(position, text.length()))
}

///|
/// Delete a character at a specific position without moving the cursor.
pub fn SyncEditor::delete_at(
  self : SyncEditor,
  position : Int,
  timestamp_ms : Int,
) -> Bool {
  let text_len = self.doc.text().length()
  if position >= text_len { return false }
  self.undo_manager.capture(position, timestamp_ms)
  let ops = self.doc.delete(@text.Pos::at(position))
  self.undo_manager.push_ops(ops)
  self.apply_local_text_change(@parser.Edit::delete(position, 1))
  true
}
```

**Note:** The exact API calls (`self.doc.insert`, `self.undo_manager.capture/push_ops`, `self.apply_local_text_change`) must match the patterns used in `insert_and_record` / `delete_and_record`. Read those implementations first and mirror their structure, substituting `position` for `self.cursor` and omitting cursor mutation.

- [ ] **Step 5: Add FFI exports in `crdt.mbt`**

```moonbit
///|
pub fn insert_at(handle : Int, position : Int, text : String, timestamp_ms : Int) -> Unit {
  let editor = get_editor(handle)
  editor.insert_at(position, text, timestamp_ms)
}

///|
pub fn delete_at(handle : Int, position : Int, timestamp_ms : Int) -> Bool {
  let editor = get_editor(handle)
  editor.delete_at(position, timestamp_ms)
}
```

- [ ] **Step 6: Run tests**

Run: `moon test`
Expected: PASS

- [ ] **Step 7: Format and commit**

```bash
moon info && moon fmt
git add editor/sync_editor_text.mbt crdt.mbt
git commit -m "feat(editor): add position-based insert_at/delete_at API for PM bridge"
```

### Task 0.4: Add ProjNode JSON export FFI

**Files:**
- Modify: `crdt.mbt`
- Reference: `projection/proj_node.mbt`, `projection/source_map.mbt`

The PM bridge needs to read ProjNode and SourceMap from JavaScript. These must be exported as JSON.

- [ ] **Step 1: Check if ProjNode already has ToJson**

Read `projection/proj_node.mbt` — check if `ProjNode` derives `ToJson` or has a manual implementation. Also check SourceMap.

- [ ] **Step 2: Implement `ToJson` for `ProjNode` if not already derived**

`ProjNode` contains `@ast.Term` (which derives `ToJson` — produces array-based JSON like `["Lam", "x", ...]`) and recursive `children`. The implementation must handle the recursive structure.

In `projection/proj_node.mbt` (or a new `projection/proj_node_json.mbt`):

```moonbit
///|
pub impl @json.ToJson for ProjNode with to_json(self) {
  @json.JsonValue::Object(
    @immut/sorted_map.from_array([
      ("node_id", self.node_id.to_json()),
      ("kind", self.kind.to_json()),
      ("children", @json.JsonValue::Array(self.children.map(fn(c) { c.to_json() }))),
      ("start", self.start.to_json()),
      ("end", self.end.to_json()),
    ]),
  )
}
```

- [ ] **Step 3: Implement `ToJson` for `SourceMap`**

SourceMap needs to export its `node_to_range` mapping. The bridge needs `[{node_id, start, end}, ...]`:

```moonbit
///|
pub impl @json.ToJson for SourceMap with to_json(self) {
  let entries : Array[@json.JsonValue] = []
  for id, range in self.node_to_range {
    entries.push(@json.JsonValue::Object(
      @immut/sorted_map.from_array([
        ("node_id", id.0.to_json()),
        ("start", range.start.to_json()),
        ("end", range.end.to_json()),
      ]),
    ))
  }
  @json.JsonValue::Array(entries)
}
```

- [ ] **Step 4: Add FFI exports in `crdt.mbt`**

```moonbit
///|
pub fn get_proj_node_json(handle : Int) -> String {
  let editor = get_editor(handle)
  match editor.get_proj_node() {
    Some(proj) => proj.to_json().stringify()
    None => "null"
  }
}

///|
pub fn get_source_map_json(handle : Int) -> String {
  let editor = get_editor(handle)
  let sm = editor.get_source_map()
  sm.to_json().stringify()
}
```

- [ ] **Step 5: Write a snapshot test**

```moonbit
test "ProjNode JSON export for simple expression" {
  let (proj, _) = @proj.parse_to_proj_node("λx.x")
  inspect!(proj.to_json().stringify())
  // Snapshot should show: {"node_id":...,"kind":["Lam","x",["Var","x"]],"children":[...],"start":0,"end":4}
}
```

- [ ] **Step 6: Run tests and format**

Run: `moon test --update && moon info && moon fmt`

- [ ] **Step 7: Commit**

```bash
git add crdt.mbt projection/
git commit -m "feat(ffi): add ToJson for ProjNode/SourceMap and JSON export FFI"
```

### Task 0.5: Expose Token-Level Spans for Param/Name Editing

**Files:**
- Modify: `projection/proj_node.mbt` (add `param_range` / `name_ranges` to ProjNode for Lam nodes)
- Modify: `projection/source_map.mbt` (add token span storage)
- Modify: `projection/flat_proj.mbt` (propagate token spans through reconciliation)
- Reference: `loom/examples/lambda/src/ast/syntax_views.mbt` (parser views have token positions)

The `SourceMap` stores only whole-node `(start, end)` spans. Lambda param names and let_def binding names need their own character ranges for CM6 editing. Without this, `LambdaView` and `LetDefView` cannot compute CRDT text positions for inline edits.

- [ ] **Step 1: Read how the parser exposes param token positions**

Read `LambdaExprView` and `LetDefView` in the loom lambda parser. These view types have methods like `param()` that return the param name string. Check if they also expose the token's start/end positions. If not, the token position can be derived from the `SyntaxNode` children.

- [ ] **Step 2: Add token span fields to ProjNode for Lam nodes**

Option A (simpler): Add an optional `token_spans` map to `SourceMap`:

```moonbit
// In source_map.mbt, add:
  token_spans : Map[NodeId, Map[String, Range]]
  // e.g., NodeId(5) -> {"param": Range(3, 4)} for λx.body where x is at pos 3-4
```

Option B: Add `param_range` directly to ProjNode for Lam-kind nodes. This is more coupled but avoids a separate map.

Choose the option that fits the existing patterns better after reading the code.

- [ ] **Step 3: Populate token spans during `syntax_to_proj_node`**

In `projection/proj_node.mbt`, where `LambdaExprView` is matched, extract the param token's `start()` and `end()` positions and store them.

Similarly for `LetDefView` — extract the name token's range.

- [ ] **Step 4: Include token spans in JSON export**

Update `SourceMap.to_json()` (from Task 0.4) to include token spans. The bridge needs entries like:

```json
{"node_id": 5, "start": 0, "end": 10, "tokens": {"param": {"start": 1, "end": 2}}}
```

- [ ] **Step 5: Write a test**

```moonbit
test "SourceMap exposes lambda param token span" {
  let text = "λx.x"
  let (proj, _) = @proj.parse_to_proj_node(text)
  let sm = @proj.SourceMap::from_ast(proj)
  // The param "x" should have a token span at position 1-2
  // (λ is 1 char in MoonBit string, x starts at position 1)
  inspect!(sm.get_token_span(proj.id(), "param"))
}
```

- [ ] **Step 6: Run tests and format**

Run: `moon test && moon info && moon fmt`

- [ ] **Step 7: Commit**

```bash
git add projection/
git commit -m "feat(projection): expose token-level spans for param and let-def names"
```

---

## Phase 1: Project Scaffold + PM Static Rendering

### Task 1.1: Create examples/prosemirror project skeleton

**Files:**
- Create: `examples/prosemirror/package.json`
- Create: `examples/prosemirror/tsconfig.json`
- Create: `examples/prosemirror/vite.config.ts`
- Create: `examples/prosemirror/index.html`
- Create: `examples/prosemirror/src/main.ts`
- Reference: `examples/web/vite.config.ts` (copy MoonBit plugin pattern)

- [ ] **Step 1: Create `package.json`**

```json
{
  "name": "crdt-prosemirror",
  "private": true,
  "type": "module",
  "scripts": {
    "dev": "vite",
    "build": "vite build"
  },
  "dependencies": {
    "prosemirror-model": "^1.24.0",
    "prosemirror-state": "^1.4.3",
    "prosemirror-view": "^1.37.0",
    "prosemirror-transform": "^1.10.0",
    "prosemirror-keymap": "^1.2.2",
    "prosemirror-commands": "^1.6.0",
    "@codemirror/state": "^6.5.0",
    "@codemirror/view": "^6.35.0",
    "@codemirror/language": "^6.10.0"
  },
  "devDependencies": {
    "typescript": "^5.7.0",
    "vite": "^6.0.0"
  }
}
```

- [ ] **Step 2: Create `vite.config.ts`**

Copy the MoonBit plugin from `examples/web/vite.config.ts`. It registers `@moonbit/crdt` as a virtual module that loads `_build/js/release/build/crdt.js`.

- [ ] **Step 3: Create `tsconfig.json`**

Standard TypeScript config targeting ESNext with strict mode.

- [ ] **Step 4: Create `index.html`**

```html
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>CRDT Projectional Editor — ProseMirror</title>
  <style>
    body { font-family: monospace; margin: 40px; }
    #editor { border: 1px solid #ccc; padding: 8px; min-height: 200px; }
  </style>
</head>
<body>
  <h1>ProseMirror + eg-walker</h1>
  <div id="editor"></div>
  <script type="module" src="/src/main.ts"></script>
</body>
</html>
```

- [ ] **Step 5: Create `src/main.ts` (minimal — just log MoonBit import)**

```typescript
import * as crdt from "@moonbit/crdt";

const handle = crdt.create_editor("pm-agent");
crdt.set_text(handle, "let double = λx.x + x\ndouble 5");
console.log("Text:", crdt.get_text(handle));
console.log("ProjNode:", crdt.get_proj_node_json(handle));
```

- [ ] **Step 6: Build MoonBit and install deps**

```bash
moon build --target js --release
cd examples/prosemirror && npm install
```

- [ ] **Step 7: Test dev server**

Run: `cd examples/prosemirror && npm run dev`
Expected: Browser shows the page, console logs text and ProjNode JSON.

- [ ] **Step 8: Commit**

```bash
git add examples/prosemirror/
git commit -m "feat(prosemirror): scaffold project with Vite + MoonBit integration"
```

### Task 1.2: Define PM Schema

**Files:**
- Create: `examples/prosemirror/src/schema.ts`
- Create: `examples/prosemirror/src/types.ts`

- [ ] **Step 1: Create `types.ts`**

TypeScript types matching the ProjNode JSON shape from MoonBit:

```typescript
export interface ProjNodeJson {
  node_id: number;
  kind: any[];        // Term ToJson: ["Lam", "x", ...] or ["Int", 42] etc.
  children: ProjNodeJson[];
  start: number;
  end: number;
}

export interface SourceMapRangeJson {
  node_id: number;
  start: number;
  end: number;
}

export type TermKindTag =
  | "Int" | "Var" | "Lam" | "App" | "Bop"
  | "If" | "Module" | "Unit" | "Unbound" | "Error";

export function getKindTag(kind: any[]): TermKindTag {
  return kind[0] as TermKindTag;
}
```

- [ ] **Step 2: Create `schema.ts`**

```typescript
import { Schema } from "prosemirror-model";

export const editorSchema = new Schema({
  nodes: {
    doc:          { content: "module | term" },
    module:       { content: "let_def* term",
                    attrs: { nodeId: { default: null } } },
    let_def:      { content: "term",
                    attrs: { name: { default: "x" }, nodeId: { default: null } } },
    lambda:       { content: "term", group: "term",
                    attrs: { param: { default: "x" }, nodeId: { default: null } } },
    application:  { content: "term term", group: "term",
                    attrs: { nodeId: { default: null } } },
    binary_op:    { content: "term term", group: "term",
                    attrs: { op: { default: "Plus" }, nodeId: { default: null } } },
    if_expr:      { content: "term term term", group: "term",
                    attrs: { nodeId: { default: null } } },
    int_literal:  { group: "term", atom: true,
                    attrs: { value: { default: 0 }, nodeId: { default: null } } },
    var_ref:      { group: "term", atom: true,
                    attrs: { name: { default: "x" }, nodeId: { default: null } } },
    unbound_ref:  { group: "term", atom: true,
                    attrs: { name: { default: "x" }, nodeId: { default: null } } },
    error_node:   { group: "term", atom: true,
                    attrs: { message: { default: "" }, nodeId: { default: null } } },
    unit:         { group: "term", atom: true,
                    attrs: { nodeId: { default: null } } },
    text:         {},
  },
  marks: {},
});
```

- [ ] **Step 3: Verify schema is valid**

In `main.ts`, import schema and create a trivial doc:

```typescript
import { editorSchema } from "./schema";
const doc = editorSchema.node("doc", null, [
  editorSchema.node("int_literal", { value: 42, nodeId: 0 })
]);
console.log("Doc:", doc.toString());
```

- [ ] **Step 4: Run dev server and verify console output**

Expected: `Doc: doc(int_literal)` or similar PM toString output.

- [ ] **Step 5: Commit**

```bash
git add examples/prosemirror/src/schema.ts examples/prosemirror/src/types.ts
git commit -m "feat(prosemirror): define PM schema matching AST Term types"
```

### Task 1.3: ProjNode → PM Doc Conversion

**Files:**
- Create: `examples/prosemirror/src/convert.ts`

- [ ] **Step 1: Implement `projNodeToDoc`**

```typescript
import { Node as PmNode, Fragment } from "prosemirror-model";
import { editorSchema } from "./schema";
import { ProjNodeJson, getKindTag } from "./types";

export function projNodeToPmNode(proj: ProjNodeJson): PmNode {
  const tag = getKindTag(proj.kind);

  switch (tag) {
    case "Int":
      return editorSchema.node("int_literal", {
        value: proj.kind[1], nodeId: proj.node_id
      });

    case "Var":
      return editorSchema.node("var_ref", {
        name: proj.kind[1], nodeId: proj.node_id
      });

    case "Unbound":
      return editorSchema.node("unbound_ref", {
        name: proj.kind[1], nodeId: proj.node_id
      });

    case "Unit":
      return editorSchema.node("unit", { nodeId: proj.node_id });

    case "Error":
      return editorSchema.node("error_node", {
        message: proj.kind[1], nodeId: proj.node_id
      });

    case "Lam": {
      const paramName = proj.kind[1]; // "x" in Lam("x", body)
      const bodyPm = projNodeToPmNode(proj.children[0]);
      return editorSchema.node("lambda", {
        param: paramName, nodeId: proj.node_id
      }, [bodyPm]);
    }

    case "App": {
      const funcPm = projNodeToPmNode(proj.children[0]);
      const argPm = projNodeToPmNode(proj.children[1]);
      return editorSchema.node("application", {
        nodeId: proj.node_id
      }, [funcPm, argPm]);
    }

    case "Bop": {
      const op = proj.kind[1]; // "Plus" or "Minus"
      const leftPm = projNodeToPmNode(proj.children[0]);
      const rightPm = projNodeToPmNode(proj.children[1]);
      return editorSchema.node("binary_op", {
        op, nodeId: proj.node_id
      }, [leftPm, rightPm]);
    }

    case "If": {
      const condPm = projNodeToPmNode(proj.children[0]);
      const thenPm = projNodeToPmNode(proj.children[1]);
      const elsePm = projNodeToPmNode(proj.children[2]);
      return editorSchema.node("if_expr", {
        nodeId: proj.node_id
      }, [condPm, thenPm, elsePm]);
    }

    case "Module": {
      // Module([(name, term), ...], body)
      // ProjNode children: [init0, init1, ..., body]
      // Module kind: ["Module", [["name0", ...], ["name1", ...]], ...]
      const defs: [string, any][] = proj.kind[1]; // array of [name, term]
      const children: PmNode[] = [];

      // Synthesize let_def nodes
      for (let i = 0; i < proj.children.length - 1; i++) {
        const name = i < defs.length ? defs[i][0] : "_";
        const initPm = projNodeToPmNode(proj.children[i]);
        children.push(editorSchema.node("let_def", {
          name, nodeId: proj.children[i].node_id
        }, [initPm]));
      }

      // Final child is the body
      const bodyPm = projNodeToPmNode(
        proj.children[proj.children.length - 1]
      );
      children.push(bodyPm);

      return editorSchema.node("module", {
        nodeId: proj.node_id
      }, children);
    }

    default:
      return editorSchema.node("error_node", {
        message: `Unknown kind: ${tag}`, nodeId: proj.node_id
      });
  }
}

export function projNodeToDoc(proj: ProjNodeJson): PmNode {
  const content = projNodeToPmNode(proj);
  return editorSchema.node("doc", null, [content]);
}
```

- [ ] **Step 2: Test the conversion in `main.ts`**

```typescript
import { projNodeToDoc } from "./convert";

const handle = crdt.create_editor("pm-agent");
crdt.set_text(handle, "let double = λx.x + x\ndouble 5");
const projJson = JSON.parse(crdt.get_proj_node_json(handle));
const doc = projNodeToDoc(projJson);
console.log("PM Doc:", doc.toString());
```

- [ ] **Step 3: Run dev server and verify**

Expected: Console shows PM doc structure like `doc(module(let_def(lambda(binary_op(var_ref, var_ref))), application(var_ref, int_literal)))`.

- [ ] **Step 4: Commit**

```bash
git add examples/prosemirror/src/convert.ts examples/prosemirror/src/main.ts
git commit -m "feat(prosemirror): implement ProjNode → PM doc conversion"
```

### Task 1.4: Mount PM EditorView with Static Rendering

**Files:**
- Modify: `examples/prosemirror/src/main.ts`

- [ ] **Step 1: Create PM EditorState + EditorView**

```typescript
import { EditorState } from "prosemirror-state";
import { EditorView } from "prosemirror-view";
import { editorSchema } from "./schema";
import { projNodeToDoc } from "./convert";

const handle = crdt.create_editor("pm-agent");
crdt.set_text(handle, "let double = λx.x + x\ndouble 5");

const projJson = JSON.parse(crdt.get_proj_node_json(handle));
const doc = projNodeToDoc(projJson);

const state = EditorState.create({ doc, schema: editorSchema });
const view = new EditorView(document.getElementById("editor")!, { state });
```

- [ ] **Step 2: Add basic CSS for node rendering**

In `index.html`, add styles for each PM node type so the structure is visible (colored borders, labels).

- [ ] **Step 3: Run dev server and verify**

Expected: Browser renders the AST as nested DOM elements. Not editable yet — just a structural rendering of the PM doc.

- [ ] **Step 4: Commit**

```bash
git add examples/prosemirror/
git commit -m "feat(prosemirror): mount PM EditorView with static AST rendering"
```

---

## Phase 2: CM6 Leaf NodeViews

### Task 2.1: TermLeafView for Atom Nodes

**Files:**
- Create: `examples/prosemirror/src/leaf-view.ts`
- Modify: `examples/prosemirror/src/main.ts`

- [ ] **Step 1: Implement `TermLeafView`**

A PM NodeView that renders a CM6 instance for atom nodes (`int_literal`, `var_ref`, `unbound_ref`). For now, CM6 is read-only — just renders the value. Editing is wired in Phase 3.

```typescript
import { NodeView } from "prosemirror-view";
import { Node as PmNode } from "prosemirror-model";
import { EditorView as PmView } from "prosemirror-view";
import { EditorView as CmView, minimalSetup } from "codemirror";
import { EditorState as CmState } from "@codemirror/state";

export class TermLeafView implements NodeView {
  dom: HTMLElement;
  cm: CmView;
  node: PmNode;
  updating = false;

  constructor(node: PmNode, pmView: PmView, getPos: () => number | undefined) {
    this.node = node;
    this.dom = document.createElement("span");
    this.dom.className = `pm-leaf pm-${node.type.name}`;

    const text = this.getTextFromNode(node);
    this.cm = new CmView({
      state: CmState.create({
        doc: text,
        extensions: [
          // Minimal: single line, no gutters
          CmView.theme({ "&": { display: "inline-block" } }),
        ],
      }),
      parent: this.dom,
    });
  }

  private getTextFromNode(node: PmNode): string {
    switch (node.type.name) {
      case "int_literal": return String(node.attrs.value);
      case "var_ref":
      case "unbound_ref": return node.attrs.name;
      default: return "";
    }
  }

  update(node: PmNode): boolean {
    if (node.type !== this.node.type) return false;
    this.updating = true;
    const newText = this.getTextFromNode(node);
    const oldText = this.cm.state.doc.toString();
    if (newText !== oldText) {
      this.cm.dispatch({
        changes: { from: 0, to: oldText.length, insert: newText },
      });
    }
    this.node = node;
    this.updating = false;
    return true;
  }

  selectNode() { this.cm.focus(); }
  deselectNode() { /* blur */ }
  stopEvent() { return true; }
  ignoreMutation() { return true; }
  destroy() { this.cm.destroy(); }
}
```

- [ ] **Step 2: Register NodeViews in EditorView**

In `main.ts`, pass `nodeViews` to PM:

```typescript
const view = new EditorView(document.getElementById("editor")!, {
  state,
  nodeViews: {
    int_literal: (node, view, getPos) => new TermLeafView(node, view, getPos),
    var_ref: (node, view, getPos) => new TermLeafView(node, view, getPos),
    unbound_ref: (node, view, getPos) => new TermLeafView(node, view, getPos),
  },
});
```

- [ ] **Step 3: Run dev server and verify**

Expected: Leaf nodes render as inline CM6 editors. Typing in them works locally (CM6 handles it) but doesn't affect the CRDT yet.

- [ ] **Step 4: Commit**

```bash
git add examples/prosemirror/src/leaf-view.ts examples/prosemirror/src/main.ts
git commit -m "feat(prosemirror): add CM6 leaf NodeViews for atom nodes"
```

### Task 2.2: LambdaView with Inline CM6 for Param

**Files:**
- Create: `examples/prosemirror/src/lambda-view.ts`
- Modify: `examples/prosemirror/src/main.ts`

- [ ] **Step 1: Implement `LambdaView`**

A PM NodeView with `contentDOM` (for the body) and an inline CM6 for the param name. Structure: `λ[CM6:param].{contentDOM}`.

```typescript
export class LambdaView implements NodeView {
  dom: HTMLElement;
  contentDOM: HTMLElement;
  paramCm: CmView;
  node: PmNode;
  updating = false;

  constructor(node: PmNode, pmView: PmView, getPos: () => number | undefined) {
    this.node = node;
    this.dom = document.createElement("span");
    this.dom.className = "pm-lambda";

    // λ prefix
    const prefix = document.createElement("span");
    prefix.textContent = "λ";
    prefix.className = "pm-lambda-prefix";
    this.dom.appendChild(prefix);

    // CM6 for param name
    const paramWrap = document.createElement("span");
    paramWrap.className = "pm-lambda-param";
    this.paramCm = new CmView({
      state: CmState.create({
        doc: node.attrs.param,
        extensions: [
          CmView.theme({ "&": { display: "inline-block" } }),
        ],
      }),
      parent: paramWrap,
    });
    this.dom.appendChild(paramWrap);

    // dot separator
    const dot = document.createElement("span");
    dot.textContent = ".";
    dot.className = "pm-lambda-dot";
    this.dom.appendChild(dot);

    // contentDOM — PM manages children (the body) here
    this.contentDOM = document.createElement("span");
    this.contentDOM.className = "pm-lambda-body";
    this.dom.appendChild(this.contentDOM);
  }

  update(node: PmNode): boolean {
    if (node.type.name !== "lambda") return false;
    this.updating = true;
    const newParam = node.attrs.param;
    const oldParam = this.paramCm.state.doc.toString();
    if (newParam !== oldParam) {
      this.paramCm.dispatch({
        changes: { from: 0, to: oldParam.length, insert: newParam },
      });
    }
    this.node = node;
    this.updating = false;
    return true;
  }

  ignoreMutation() { return true; }
  destroy() { this.paramCm.destroy(); }
}
```

- [ ] **Step 2: Register in main.ts**

```typescript
nodeViews: {
  // ... existing leaf views
  lambda: (node, view, getPos) => new LambdaView(node, view, getPos),
},
```

- [ ] **Step 3: Run dev server and verify**

Expected: Lambda nodes render as `λ[editable param].{body}`. Param is editable via CM6.

- [ ] **Step 4: Commit**

```bash
git add examples/prosemirror/src/lambda-view.ts examples/prosemirror/src/main.ts
git commit -m "feat(prosemirror): add LambdaView with inline CM6 for param editing"
```

### Task 2.3: LetDefView with Inline CM6 for Name

**Files:**
- Create: `examples/prosemirror/src/let-def-view.ts`
- Modify: `examples/prosemirror/src/main.ts`

- [ ] **Step 1: Implement `LetDefView`**

Same pattern as LambdaView: `let [CM6:name] = {contentDOM}`.

- [ ] **Step 2: Register in main.ts**

- [ ] **Step 3: Run dev server and verify**

Expected: Let definitions render as `let [editable name] = {init expression}`.

- [ ] **Step 4: Commit**

```bash
git add examples/prosemirror/src/let-def-view.ts examples/prosemirror/src/main.ts
git commit -m "feat(prosemirror): add LetDefView with inline CM6 for binding name"
```

---

## Phase 3: Bridge Layer (Outbound + Inbound)

### Task 3.1: CrdtBridge Foundation

**Files:**
- Create: `examples/prosemirror/src/bridge.ts`
- Modify: `examples/prosemirror/src/main.ts`

- [ ] **Step 1: Implement `CrdtBridge` class**

Skeleton with the `dispatchTransaction` override that classifies transactions:

```typescript
import { EditorView as PmView } from "prosemirror-view";
import { Transaction } from "prosemirror-state";

export class CrdtBridge {
  private pmView: PmView;
  private handle: number;
  private crdt: any;  // MoonBit crdt module

  constructor(pmView: PmView, handle: number, crdt: any) {
    this.pmView = pmView;
    this.handle = handle;
    this.crdt = crdt;
  }

  handleTransaction(tr: Transaction): void {
    // Classification:
    if (tr.getMeta("fromCrdt")) {
      // Inbound from reconciler — apply directly
      this.pmView.updateState(this.pmView.state.apply(tr));
      return;
    }
    if (!tr.docChanged) {
      // View-only (selection, scroll, IME) — apply directly
      this.pmView.updateState(this.pmView.state.apply(tr));
      return;
    }
    // Doc-changing transaction — route through CRDT
    // (implemented in subsequent tasks)
    console.warn("Doc-changing transaction — CRDT routing not yet implemented");
  }

  reconcile(): void {
    // (implemented in Task 3.3)
  }
}
```

- [ ] **Step 2: Wire into PM EditorView**

In `main.ts`, create the bridge and set `dispatchTransaction`:

```typescript
const bridge = new CrdtBridge(view, handle, crdt);
// Note: must set after view creation, or pass factory
view.setProps({
  dispatchTransaction: (tr) => bridge.handleTransaction(tr),
});
```

- [ ] **Step 3: Run dev server and verify**

Expected: Selection changes work (view-only transactions apply). Typing in CM6 triggers the console warning (doc-changing not yet routed).

- [ ] **Step 4: Commit**

```bash
git add examples/prosemirror/src/bridge.ts examples/prosemirror/src/main.ts
git commit -m "feat(prosemirror): add CrdtBridge skeleton with transaction classification"
```

### Task 3.2: Outbound — Leaf Text Edits → CRDT

**Files:**
- Modify: `examples/prosemirror/src/bridge.ts`
- Modify: `examples/prosemirror/src/leaf-view.ts`

- [ ] **Step 1: Add `handleLeafEdit` to bridge**

**Critical ordering:** CM6 ChangeSets describe changes as a sequence of `{from, to, insert}` ranges. Each change must be applied sequentially because earlier changes shift positions of later ones. Process changes from the CM6 `ChangeSet` iterator, adjusting a running offset.

```typescript
handleLeafEdit(nodeId: number, changes: ChangeSet): void {
  const smJson: SourceMapRangeJson[] = JSON.parse(
    this.crdt.get_source_map_json(this.handle)
  );
  const range = smJson.find((r) => r.node_id === nodeId);
  if (!range) return;

  const basePos = range.start;
  const ts = Date.now();

  // CM6 ChangeSet.iterChanges gives changes in document order.
  // Each change: from/to in OLD doc coordinates, insert text.
  // We must track a running offset because each CRDT op shifts positions.
  let posOffset = 0;

  changes.iterChanges((fromA, toA, _fromB, _toB, inserted) => {
    const deleteLen = toA - fromA;
    const insertText = inserted.toString();

    // Delete characters (reverse order to preserve positions)
    for (let i = deleteLen - 1; i >= 0; i--) {
      this.crdt.delete_at(this.handle, basePos + fromA + i + posOffset, ts);
    }
    posOffset -= deleteLen;

    // Insert characters (forward order)
    for (let i = 0; i < insertText.length; i++) {
      this.crdt.insert_at(
        this.handle,
        basePos + fromA + posOffset + i,
        insertText[i],
        ts
      );
    }
    posOffset += insertText.length;
  });

  // Schedule reconcile on next frame
  this.scheduleReconcile();
}

private reconcileRafId: number | null = null;

private scheduleReconcile(): void {
  if (this.reconcileRafId !== null) return; // already scheduled
  this.reconcileRafId = requestAnimationFrame(() => {
    this.reconcileRafId = null;
    this.reconcile();
  });
}
```

- [ ] **Step 2: Wire `forwardUpdate` in TermLeafView**

Update `TermLeafView` to call `bridge.handleLeafEdit` when CM6 content changes. Pass the bridge reference through NodeView constructor.

- [ ] **Step 3: Test: type in a var_ref leaf and verify CRDT text changes**

Run dev server. Type in a variable name. Check `crdt.get_text(handle)` in console — it should reflect the edit.

- [ ] **Step 4: Commit**

```bash
git add examples/prosemirror/src/bridge.ts examples/prosemirror/src/leaf-view.ts
git commit -m "feat(prosemirror): wire CM6 leaf edits to CRDT via position-based API"
```

### Task 3.3: Inbound — Reconciler

**Files:**
- Create: `examples/prosemirror/src/reconciler.ts`
- Modify: `examples/prosemirror/src/bridge.ts`

- [ ] **Step 1: Implement tree-diff reconciler**

The reconciler compares the current PM doc against a new ProjNode tree and produces a PM transaction that updates the doc.

```typescript
import { Node as PmNode, Fragment } from "prosemirror-model";
import { Transaction } from "prosemirror-state";
import { EditorState } from "prosemirror-state";
import { projNodeToPmNode, projNodeToDoc } from "./convert";
import { ProjNodeJson } from "./types";

export function reconcile(
  state: EditorState,
  newProj: ProjNodeJson,
): Transaction | null {
  const newDoc = projNodeToDoc(newProj);
  const oldDoc = state.doc;

  // Simple strategy for initial implementation:
  // Compare old and new doc. If different, replace the entire doc content.
  // This is correct but not optimal — it rebuilds all NodeViews.
  // WARNING: This destroys CM6 instances on every reconcile, causing focus
  // loss during typing. This is expected and tolerable during Phase 3 testing.
  // Phase 5 (Task 5.2) replaces this with subtree diffing that preserves
  // NodeViews for unchanged nodes.
  // Optimize to subtree diffing in a later phase.
  if (oldDoc.eq(newDoc)) return null;

  const tr = state.tr;
  tr.replaceWith(0, oldDoc.content.size, newDoc.content);
  tr.setMeta("fromCrdt", true);
  return tr;
}
```

- [ ] **Step 2: Wire reconcile into bridge**

```typescript
reconcile(): void {
  const projJson = JSON.parse(this.crdt.get_proj_node_json(this.handle));
  if (!projJson) return;
  const tr = reconcile(this.pmView.state, projJson);
  if (tr) {
    this.pmView.dispatch(tr);
  }
}
```

- [ ] **Step 3: Test the full loop**

Type in a CM6 leaf → CRDT updates → reconcile → PM doc updates. Verify that typing a character in a `var_ref` results in the updated text showing correctly.

- [ ] **Step 4: Commit**

```bash
git add examples/prosemirror/src/reconciler.ts examples/prosemirror/src/bridge.ts
git commit -m "feat(prosemirror): implement basic reconciler (full-doc replace strategy)"
```

### Task 3.4: Outbound — Structural Edits → TreeEditOp

**Files:**
- Modify: `examples/prosemirror/src/bridge.ts`

This wires structural PM operations (node deletion, wrapping, etc.) through TreeEditOp. For the initial implementation, support `Delete` and `WrapInLambda` as proof of concept. The full set of TreeEditOps can be added incrementally.

- [ ] **Step 1: Add keyboard shortcuts for structural ops**

Add a PM keymap plugin:
- `Backspace` on a selected node → `TreeEditOp::Delete`
- `Ctrl-L` on a selected node → `TreeEditOp::WrapInLambda`

- [ ] **Step 2: Implement structural edit routing in bridge**

When a structural keymap fires, construct the TreeEditOp JSON and call the FFI:

```typescript
handleStructuralEdit(opType: string, nodeId: number, extra?: any): void {
  // Construct TreeEditOp-compatible call
  // Use existing SyncEditor.apply_tree_edit FFI
  // Then reconcile
}
```

- [ ] **Step 3: Add `apply_tree_edit_json` FFI**

This requires two parts: (a) parsing JSON into `TreeEditOp`, and (b) the FFI function.

**Part (a):** Implement a manual JSON→TreeEditOp parser in MoonBit. `TreeEditOp` is an enum and does NOT derive `FromJson`. Write a dedicated function that parses a specific JSON format:

```moonbit
// In a new file: editor/tree_edit_json.mbt
///|
pub fn parse_tree_edit_op(json : @json.JsonValue) -> Result[@proj.TreeEditOp, String] {
  // Expected JSON format: {"type": "Delete", "node_id": 5}
  // or {"type": "WrapInLambda", "node_id": 5, "var_name": "x"}
  match json {
    Object(m) => {
      let op_type = match m.get("type") {
        Some(String(s)) => s
        _ => return Err("missing type field")
      }
      let node_id = match m.get("node_id") {
        Some(Number(n)) => @proj.NodeId(n.to_int())
        _ => return Err("missing node_id field")
      }
      match op_type {
        "Delete" => Ok(@proj.TreeEditOp::Delete(node_id~))
        "WrapInLambda" => {
          let var_name = match m.get("var_name") {
            Some(String(s)) => s
            _ => "x"
          }
          Ok(@proj.TreeEditOp::WrapInLambda(node_id~, var_name~))
        }
        "Select" => Ok(@proj.TreeEditOp::Select(node_id~))
        // Add more cases as needed
        _ => Err("unknown op type: " + op_type)
      }
    }
    _ => Err("expected JSON object")
  }
}
```

**Part (b):** The FFI function:

```moonbit
///|
pub fn apply_tree_edit_json(handle : Int, op_json : String, timestamp_ms : Int) -> String {
  let editor = get_editor(handle)
  let json = @json.parse(op_json) catch { _ => return "error: invalid JSON" }
  let op = match parse_tree_edit_op(json) {
    Ok(op) => op
    Err(msg) => return "error: " + msg
  }
  match editor.apply_tree_edit(op, timestamp_ms) {
    Ok(_) => "ok"
    Err(msg) => "error: " + msg
  }
}
```

Start with `Delete` and `WrapInLambda` for the proof of concept. Add more TreeEditOp variants as the structural editing features expand.

- [ ] **Step 4: Test: select a node, press Backspace, verify it's deleted**

- [ ] **Step 5: Commit**

```bash
git add examples/prosemirror/ crdt.mbt
git commit -m "feat(prosemirror): wire structural edits through TreeEditOp bridge"
```

---

## Phase 4: Collaboration & Presence

### Task 4.1: Peer Cursor Distribution

**Files:**
- Create: `examples/prosemirror/src/peer-cursors.ts`
- Modify: `examples/prosemirror/src/leaf-view.ts`
- Modify: `examples/prosemirror/src/bridge.ts`

- [ ] **Step 1: Implement `PeerCursorDistributor`**

Routes remote cursor positions to the correct rendering layer (PM decorations for structural, CM6 decorations for intra-leaf).

- [ ] **Step 2: Add cursor broadcast on local selection/cursor changes**

PM selection changes → `ephemeral_set_presence_with_selection`.
CM6 cursor changes → same, with SourceMap position conversion.

- [ ] **Step 3: Add PM decoration plugin for structural peer cursors**

Widget decorations for cursor carets at node boundaries.

- [ ] **Step 4: Add CM6 StateField for intra-leaf peer cursors**

Each CM6 instance receives its peer cursors and renders them as CM6 decorations.

- [ ] **Step 5: Test with two browser tabs**

Open two tabs, type in one, see the other's cursor appear.

- [ ] **Step 6: Commit**

```bash
git add examples/prosemirror/src/peer-cursors.ts examples/prosemirror/src/
git commit -m "feat(prosemirror): add dual-layer peer cursor rendering"
```

### Task 4.2: WebSocket Sync Integration

**Files:**
- Modify: `examples/prosemirror/src/main.ts`
- Reference: `examples/web/src/main.ts` (existing WebSocket setup)

- [ ] **Step 1: Copy WebSocket signaling setup from existing web example**

The existing `examples/web/` has WebSocket sync working. Port the connection, `export_since`, `apply_sync` logic.

- [ ] **Step 2: Wire sync events to bridge.reconcile()**

After `apply_sync_json`, call `bridge.reconcile()`.

- [ ] **Step 3: Test with two browser windows**

Type in one → appears in the other. Structural edits sync. Peer cursors visible.

- [ ] **Step 4: Commit**

```bash
git add examples/prosemirror/src/main.ts
git commit -m "feat(prosemirror): add WebSocket sync with remote reconciliation"
```

---

## Phase 5: Polish & Optimization

### Task 5.1: rAF-Batched Reconciliation

**Files:**
- Modify: `examples/prosemirror/src/bridge.ts`

- [ ] **Step 1: Replace immediate reconcile with rAF batching**

Accumulate CRDT ops synchronously, defer reconcile to next animation frame. Deduplicate multiple reconcile requests per frame.

- [ ] **Step 2: Verify typing latency is acceptable**

CM6 shows edits immediately (local state). PM structural view updates on next frame.

- [ ] **Step 3: Commit**

```bash
git add examples/prosemirror/src/bridge.ts
git commit -m "perf(prosemirror): batch reconciliation to requestAnimationFrame"
```

### Task 5.2: Incremental Reconciler (Subtree Diff)

**Files:**
- Modify: `examples/prosemirror/src/reconciler.ts`

- [ ] **Step 1: Replace full-doc replacement with subtree diffing**

Walk PM doc and ProjNode in parallel, matching by `nodeId`. Only emit ReplaceSteps for changed subtrees. This preserves NodeView instances (and CM6 state) for unchanged nodes.

- [ ] **Step 2: Verify focus is preserved during remote edits**

Type in one tab's CM6 leaf. Edit a different node in another tab. Verify the first tab's CM6 keeps focus.

- [ ] **Step 3: Commit**

```bash
git add examples/prosemirror/src/reconciler.ts
git commit -m "perf(prosemirror): incremental subtree-diff reconciler preserving NodeView state"
```

### Task 5.3: Arrow Key Navigation Between CM6 Instances

**Files:**
- Modify: `examples/prosemirror/src/leaf-view.ts`
- Modify: `examples/prosemirror/src/lambda-view.ts`
- Modify: `examples/prosemirror/src/let-def-view.ts`

- [ ] **Step 1: Add arrow key handlers to CM6 instances**

When the cursor hits the edge of a CM6 editor (left arrow at position 0, right arrow at end), transfer focus to the PM selection system so the user can navigate to the next/previous node.

- [ ] **Step 2: Test keyboard navigation through the entire tree**

Tab/arrow through leaves, verify smooth transition between CM6 instances.

- [ ] **Step 3: Commit**

```bash
git add examples/prosemirror/src/
git commit -m "feat(prosemirror): add arrow-key navigation between CM6 NodeViews"
```
