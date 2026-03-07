# Simplify Web Integration Plan

**Status:** Complete

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Move display logic from TypeScript into MoonBit so the web layer is a thin DOM bridge (~80 lines) instead of 500+ lines of format conversion and rendering orchestration.

**Architecture:** Add two new MoonBit exports (`get_ast_svg` and `get_ast_pretty`) that produce ready-to-use strings. The graphviz module is a separate MoonBit module loaded independently via Vite, so `get_ast_svg` calls graphviz from JavaScript (unavoidable — cross-module FFI). `get_ast_pretty` is pure MoonBit. Then delete `syntax-highlighter.ts`, `termJsonToAstNode`, and the dead `network.ts`. Collapse `editor.ts` + `main.ts` into a single file.

**Tech Stack:** MoonBit (crdt module + graphviz module), TypeScript, Vite

**Constraints:**
- `crdt` and `graphviz` are separate MoonBit modules (different `moon.mod.json`). They cannot import each other. The JS layer must bridge them.
- `network.ts` uses exports (`get_operations_json`, `merge_operations`) that don't exist in `crdt.mbt`. It is dead code.

---

## Current State (what we're simplifying)

| File | Lines | Problem |
|------|-------|---------|
| `editor.ts` | 340 | 55-line `termJsonToAstNode` converter, duplicated `updateUI`/`handleRemoteTextChange`, excessive `console.log` |
| `syntax-highlighter.ts` | 168 | `printTermNode` and `formatAST` duplicate MoonBit's `print_term`; `highlight()` is unused |
| `network.ts` | 435 | Dead code — imports non-existent exports |
| `main.ts` | 105 | Separate file just for DOM wiring |
| `crdt.mbt` | 282 | Every function repeats `match editor.val { Some(ed) => ... None => default }` |

**Target:** ~150 lines total TypeScript (down from ~1050), one new MoonBit function.

---

### Task 1: Add `get_ast_pretty` to MoonBit

Add a function that returns the "Expression + AST tree" string directly from MoonBit, eliminating the need for `termJsonToAstNode` and `SyntaxHighlighter.formatAST/printTermNode` in TypeScript.

**Files:**
- Create: `loom/examples/lambda/src/ast/format.mbt`
- Create: `loom/examples/lambda/src/ast/format_wbtest.mbt`
- Modify: `editor/sync_editor.mbt` (add `get_ast_pretty` method)
- Modify: `crdt.mbt` (add `get_ast_pretty` JS export)
- Modify: `moon.pkg` (add to exports list)

**Step 1: Write test for `format_tree`**

Create `loom/examples/lambda/src/ast/format_wbtest.mbt`:

```moonbit
///|
test "format_tree - simple variable" {
  inspect(format_tree(Var("x")), content="Var: x [0:0]")
}

///|
test "format_tree - application" {
  inspect(
    format_tree(App(Var("f"), Int(1))),
    content=
      #|App [0:0]
      #|  Var: f [0:0]
      #|  Int: 1 [0:0]
    ,
  )
}

///|
test "format_tree - lambda" {
  inspect(
    format_tree(Lam("x", Var("x"))),
    content=
      #|Lam: x [0:0]
      #|  Var: x [0:0]
    ,
  )
}

///|
test "format_tree - identity application" {
  let term = App(Lam("x", Var("x")), Int(42))
  let result = format_pretty(term)
  inspect(
    result,
    content=
      #|Expression: ((λx. x) 42)
      #|
      #|AST:
      #|App [0:0]
      #|  Lam: x [0:0]
      #|    Var: x [0:0]
      #|  Int: 42 [0:0]
    ,
  )
}
```

**Step 2: Run tests to verify they fail**

```bash
cd loom/examples/lambda && moon test -p dowdiness/lambda/ast -f format_wbtest.mbt
```

Expected: FAIL — `format_tree` and `format_pretty` not defined.

**Step 3: Implement `format_tree` and `format_pretty`**

Create `loom/examples/lambda/src/ast/format.mbt`:

```moonbit
///|
pub fn format_tree(term : Term, indent~ : Int = 0) -> String {
  let buf = StringBuilder::new()
  format_tree_buf(term, indent, buf)
  // Remove trailing newline
  let s = buf.to_string()
  if s.length() > 0 && s[s.length() - 1] == '\n' {
    s.substring(start=0, end=s.length() - 1)
  } else {
    s
  }
}

///|
fn format_tree_buf(term : Term, indent : Int, buf : StringBuilder) -> Unit {
  let prefix = " ".repeat(indent)
  match term {
    Int(i) => buf.write_string(prefix + "Int: " + i.to_string() + " [0:0]\n")
    Var(x) => buf.write_string(prefix + "Var: " + x + " [0:0]\n")
    Lam(x, body) => {
      buf.write_string(prefix + "Lam: " + x + " [0:0]\n")
      format_tree_buf(body, indent + 2, buf)
    }
    App(t1, t2) => {
      buf.write_string(prefix + "App [0:0]\n")
      format_tree_buf(t1, indent + 2, buf)
      format_tree_buf(t2, indent + 2, buf)
    }
    Bop(op, t1, t2) => {
      let op_str = match op {
        Plus => "Plus"
        Minus => "Minus"
      }
      buf.write_string(prefix + "Bop: " + op_str + " [0:0]\n")
      format_tree_buf(t1, indent + 2, buf)
      format_tree_buf(t2, indent + 2, buf)
    }
    If(t1, t2, t3) => {
      buf.write_string(prefix + "If [0:0]\n")
      format_tree_buf(t1, indent + 2, buf)
      format_tree_buf(t2, indent + 2, buf)
      format_tree_buf(t3, indent + 2, buf)
    }
    Let(x, init, body) => {
      buf.write_string(prefix + "Let: " + x + " [0:0]\n")
      format_tree_buf(init, indent + 2, buf)
      format_tree_buf(body, indent + 2, buf)
    }
    Unit => buf.write_string(prefix + "Unit [0:0]\n")
    Error(msg) => buf.write_string(prefix + "Error: " + msg + " [0:0]\n")
  }
}

///|
pub fn format_pretty(term : Term) -> String {
  "Expression: " + print_term(term) + "\n\nAST:\n" + format_tree(term)
}
```

**Step 4: Run tests to verify they pass**

```bash
cd loom/examples/lambda && moon test -p dowdiness/lambda/ast -f format_wbtest.mbt
```

Expected: PASS. If snapshot content differs, run `moon test -p dowdiness/lambda/ast -f format_wbtest.mbt --update` and verify the output looks correct.

**Step 5: Wire through SyncEditor and crdt.mbt**

Add to `editor/sync_editor.mbt`:

```moonbit
///|
pub fn SyncEditor::get_ast_pretty(self : SyncEditor) -> String {
  @ast.format_pretty(self.get_ast())
}
```

Add to `crdt.mbt`:

```moonbit
///|
pub fn get_ast_pretty(_handle : Int) -> String {
  match editor.val {
    Some(ed) => ed.get_ast_pretty()
    None => ""
  }
}
```

Add `"get_ast_pretty"` to the exports list in `moon.pkg`.

**Step 6: Run full tests**

```bash
moon test  # crdt module — 189 tests
cd loom/examples/lambda && moon test  # lambda module
```

Expected: all pass.

**Step 7: Update interfaces and format**

```bash
moon info && moon fmt
cd loom/examples/lambda && moon info && moon fmt
```

**Step 8: Commit**

```bash
git add loom/examples/lambda/src/ast/format.mbt loom/examples/lambda/src/ast/format_wbtest.mbt
git add editor/sync_editor.mbt crdt.mbt moon.pkg
git add loom/examples/lambda/src/ast/pkg.generated.mbti
git commit -m "feat: add get_ast_pretty MoonBit export for web UI"
```

---

### Task 2: Delete dead code (`network.ts` and `syntax-highlighter.ts`)

Remove files that are dead or will be replaced by MoonBit exports.

**Files:**
- Delete: `web/src/network.ts`
- Delete: `web/src/syntax-highlighter.ts`
- Modify: `web/src/editor.ts` (remove imports of deleted files)

**Step 1: Remove imports and references**

In `editor.ts`, remove:
- `import { SyntaxHighlighter } from './syntax-highlighter';`
- `import { NetworkSync } from './network';`
- The `highlighter` field and its construction (`this.highlighter = new SyntaxHighlighter()`)
- The entire `termJsonToAstNode` function (55 lines)
- The `networkSync` field and all network-related methods: `enableNetworkSync`, `disableNetworkSync`, `getNetworkStatus`, `handleRemoteTextChange`
- The `ASTNode` interface (no longer needed)

In `main.ts`, remove:
- All network sync button handlers (connect/disconnect, ~60 lines)

**Step 2: Delete the files**

```bash
rm web/src/network.ts web/src/syntax-highlighter.ts
```

**Step 3: Verify build**

```bash
cd web && npx vite build 2>&1 | tail -5
```

Expected: Build succeeds. The network.ts import warnings should disappear.

**Step 4: Commit**

```bash
git add -A web/src/
git commit -m "chore: remove dead network.ts and syntax-highlighter.ts"
```

---

### Task 3: Simplify `editor.ts` to thin DOM bridge

Replace the `LambdaEditor` class with a minimal module that just wires MoonBit outputs to DOM elements.

**Files:**
- Rewrite: `web/src/editor.ts`
- Rewrite: `web/src/main.ts`

**Step 1: Rewrite `editor.ts`**

The new editor should be ~60 lines. It needs to:
1. Call `crdt.create_editor(agentId)` to get a handle
2. On input: `crdt.set_text(handle, text)`, then update three panels
3. Panel updates call MoonBit functions that return ready-to-use strings

```typescript
import * as crdt from '@moonbit/crdt';
import * as graphviz from '@moonbit/graphviz';

export function createEditor(agentId: string) {
  const handle = crdt.create_editor(agentId);

  const editorEl = document.getElementById('editor') as HTMLDivElement;
  const astGraphEl = document.getElementById('ast-graph') as HTMLDivElement;
  const astOutputEl = document.getElementById('ast-output') as HTMLPreElement;
  const errorEl = document.getElementById('error-output') as HTMLUListElement;

  let lastText = '';
  let scheduled = false;

  function updateUI() {
    const text = editorEl.textContent || '';
    if (text !== lastText) {
      crdt.set_text(handle, text);
      lastText = text;
    }

    // AST visualization (DOT -> SVG via graphviz module)
    try {
      const dot = crdt.get_ast_dot_resolved(handle);
      const svg = graphviz.render_dot_to_svg(dot);
      astGraphEl.innerHTML = svg;

      // Dark theme: remove white background from SVG
      const polygon = astGraphEl.querySelector('g.graph polygon');
      if (polygon) polygon.setAttribute('fill', 'transparent');
    } catch (e) {
      astGraphEl.innerHTML = `<p style="color:#f44">Error: ${e}</p>`;
    }

    // AST structure (pure MoonBit string)
    astOutputEl.textContent = crdt.get_ast_pretty(handle);

    // Errors
    const errors: string[] = JSON.parse(crdt.get_errors_json(handle));
    if (errors.length === 0) {
      errorEl.innerHTML = '<li>No errors</li>';
    } else {
      errorEl.innerHTML = errors
        .map(e => `<li class="error-item">${escapeHTML(e)}</li>`)
        .join('');
    }
  }

  editorEl.addEventListener('input', () => {
    if (scheduled) return;
    scheduled = true;
    requestAnimationFrame(() => {
      scheduled = false;
      updateUI();
    });
  });

  return {
    handle,
    agentId,
    updateUI,
    getText: () => crdt.get_text(handle),
    setText: (text: string) => {
      editorEl.textContent = text;
      editorEl.dispatchEvent(new Event('input', { bubbles: true }));
    },
  };
}

function escapeHTML(text: string): string {
  const div = document.createElement('div');
  div.textContent = text;
  return div.innerHTML;
}
```

**Step 2: Rewrite `main.ts`**

```typescript
import { createEditor } from './editor';

const agentId = `user-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`;
const editor = createEditor(agentId);

// Example buttons
document.querySelectorAll('.example-btn').forEach(btn => {
  btn.addEventListener('click', () => {
    const example = btn.getAttribute('data-example');
    if (example) editor.setText(example);
  });
});

const statusEl = document.getElementById('status')!;
statusEl.textContent = `Ready! ID: ${agentId}`;
statusEl.className = 'status success';
```

**Step 3: Remove network UI from `index.html`**

Remove the connect/disconnect buttons and network status elements since network.ts is deleted. Keep the HTML structure otherwise unchanged.

**Step 4: Build and verify**

```bash
cd web && npx vite build 2>&1 | tail -5
```

Expected: Clean build, no import warnings.

**Step 5: Manual test**

```bash
cd web && npx vite --host 0.0.0.0 &
sleep 2
agent-browser open http://localhost:5173/
agent-browser snapshot -i
# Click Identity example
agent-browser click @e3
agent-browser wait 1000
agent-browser scroll down 500
agent-browser screenshot /tmp/simplified.png
```

Verify: AST Visualization shows colored graph, AST Structure shows pretty-printed tree, Errors shows "No errors".

**Step 6: Commit**

```bash
git add web/src/editor.ts web/src/main.ts web/index.html
git commit -m "refactor(web): simplify to thin DOM bridge (~80 lines TS)"
```

---

### Task 4: Clean up `crdt.mbt` exports

Remove exports that are no longer used by the web UI (the old network API that was never wired).

**Files:**
- Modify: `crdt.mbt` (remove unused functions)
- Modify: `moon.pkg` (remove from exports list)

**Step 1: Identify unused exports**

After Tasks 1-3, the web UI only uses:
- `create_editor` / `create_editor_with_undo`
- `set_text` / `get_text`
- `get_ast_dot_resolved`
- `get_ast_pretty` (new)
- `get_errors_json`
- Undo API (`insert_and_record`, `backspace_and_record`, etc.)

Still needed for future network sync:
- `export_all_json` / `export_since_json` / `apply_sync_json` / `get_version_json`

Can remove:
- `get_ast_json` (replaced by `get_ast_pretty`)
- `get_ast_dot` (replaced by `get_ast_dot_resolved`)
- `insert` / `delete_` / `backspace` (non-undo versions — web uses `set_text` for bulk sync)
- `get_cursor` / `set_cursor` (contenteditable manages cursor)

**Step 2: Remove unused functions from `crdt.mbt` and `moon.pkg` exports**

Remove the functions listed above and their corresponding export entries.

**Step 3: Rebuild and test**

```bash
moon test
moon build --target js --release
cd web && npx vite build 2>&1 | tail -5
```

Expected: all pass, build succeeds.

**Step 4: Update interfaces**

```bash
moon info && moon fmt
```

**Step 5: Commit**

```bash
git add crdt.mbt moon.pkg
git commit -m "chore: remove unused JS exports from crdt.mbt"
```

---

### Task 5: Final verification and line count

**Step 1: Verify all tests pass**

```bash
moon test
cd loom/examples/lambda && moon test
cd ../../graphviz && moon test
```

**Step 2: Count lines**

```bash
wc -l web/src/*.ts
```

Expected: ~100-150 total lines (down from ~1050).

**Step 3: Manual browser test**

Test all example buttons (Identity, Church 2, Add, Conditional, Apply). Verify AST graph renders with colors, AST structure text is correct, errors show/hide properly.

**Step 4: Build for deploy**

```bash
moon build --target js --release
cd web && npx vite build
```

Expected: Clean build, no warnings except the pre-existing svg alias warning in graphviz.

---

## Summary

| Task | What | Lines removed | Lines added |
|------|------|--------------|-------------|
| 1 | `get_ast_pretty` in MoonBit | 0 | ~50 MoonBit |
| 2 | Delete dead TS files | ~660 | 0 |
| 3 | Rewrite editor.ts + main.ts | ~445 | ~80 |
| 4 | Clean up crdt.mbt exports | ~60 | 0 |
| 5 | Verify | 0 | 0 |

**Net result:** ~1100 lines of TypeScript removed, ~80 lines remaining. ~50 lines of MoonBit added.
