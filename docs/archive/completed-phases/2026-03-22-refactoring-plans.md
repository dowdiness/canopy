**Status:** Complete

# Refactoring Plans: File Decomposition

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Decompose 3 oversized files into focused modules for maintainability.

**Architecture:** All splits are within the same MoonBit package — no import changes needed. Functions stay in the same package, just in different files. MoonBit compiles all `.mbt` files in a package together, so private functions remain accessible across files in the package.

**Tech Stack:** MoonBit

---

## Plan A: Split `projection/text_edit.mbt` (1,348 lines → 3 files)

### File Map

| File | Action | Content |
|------|--------|---------|
| `projection/text_edit.mbt` | Keep | `SpanEdit` struct + `compute_text_edit` dispatcher (~1,060 lines) |
| `projection/text_edit_rename.mbt` | Create | 4 rename functions: `rename_lam_param`, `rename_from_var`, `rename_binding_by_id`, `rename_module_binding` (~230 lines) |
| `projection/text_edit_utils.mbt` | Create | `placeholder_term_for_kind`, `find_let_start`, `get_binding_text_range` (~55 lines) |

### Task A1: Extract text_edit_utils.mbt

- [ ] **Step 1:** Create `projection/text_edit_utils.mbt` with functions cut from `text_edit.mbt`:
  - `placeholder_term_for_kind` (lines 11-24)
  - `find_let_start` (lines 29-42)
  - `get_binding_text_range` (lines 47-59)

- [ ] **Step 2:** Remove those functions from `text_edit.mbt`

- [ ] **Step 3:** Verify: `cd projection && moon check && moon test`

- [ ] **Step 4:** Commit
```bash
moon info && moon fmt
git add projection/text_edit.mbt projection/text_edit_utils.mbt
git add -A
git commit -m "refactor(projection): extract text_edit_utils.mbt"
```

### Task A2: Extract text_edit_rename.mbt

- [ ] **Step 1:** Create `projection/text_edit_rename.mbt` with functions cut from `text_edit.mbt`:
  - `rename_lam_param` (lines 63-141)
  - `rename_from_var` (lines 145-186)
  - `rename_binding_by_id` (lines 190-224)
  - `rename_module_binding` (lines 228-291)

  These form a call hierarchy (rename_from_var → rename_lam_param/rename_module_binding). Keep them together.

- [ ] **Step 2:** Remove those functions from `text_edit.mbt`

- [ ] **Step 3:** Verify: `cd projection && moon check && moon test`

- [ ] **Step 4:** Commit
```bash
moon info && moon fmt
git add projection/text_edit.mbt projection/text_edit_rename.mbt
git add -A
git commit -m "refactor(projection): extract text_edit_rename.mbt"
```

### Task A3: Verify final state

- [ ] **Step 1:** Run full test suite: `moon test`
- [ ] **Step 2:** Verify line counts: `wc -l projection/text_edit*.mbt`
  - Expected: text_edit.mbt ~1,060, text_edit_rename.mbt ~230, text_edit_utils.mbt ~55

---

## Plan B: Decompose `editor/ephemeral_hub.mbt` (19 methods → focused responsibilities)

The EphemeralHub has 19 public methods mixing local state writes, peer reads, and lifecycle. Split typed methods into two focused files.

### File Map

| File | Action | Content |
|------|--------|---------|
| `editor/ephemeral_hub.mbt` | Keep | `EphemeralHub` struct, `EphemeralNamespace` enum, constructor, `get_store`, encode/apply/lifecycle methods (~150 lines) |
| `editor/ephemeral_hub_state.mbt` | Create | Typed write methods: `set_cursor`, `set_edit_mode`, `clear_edit_mode`, `set_drag`, `clear_drag`, `set_presence` (~80 lines) |
| `editor/ephemeral_hub_readers.mbt` | Create | Typed read methods: `get_cursor`, `get_edit_mode`, `get_all_editing`, `get_presence`, `get_online_peers` (~90 lines) |

### Task B1: Extract ephemeral_hub_state.mbt

- [ ] **Step 1:** Create `editor/ephemeral_hub_state.mbt` — move all typed write methods from `ephemeral_hub.mbt`:
  - `EphemeralHub::set_cursor`
  - `EphemeralHub::set_edit_mode`
  - `EphemeralHub::clear_edit_mode`
  - `EphemeralHub::set_drag`
  - `EphemeralHub::clear_drag`
  - `EphemeralHub::set_presence`

  These all follow the same pattern: encode domain type → call `store.set(wire_peer_id, value)`.

- [ ] **Step 2:** Remove from `ephemeral_hub.mbt`

- [ ] **Step 3:** Verify: `cd editor && moon check && moon test`

- [ ] **Step 4:** Commit
```bash
moon info && moon fmt
git add editor/ephemeral_hub.mbt editor/ephemeral_hub_state.mbt
git add -A
git commit -m "refactor(editor): extract ephemeral_hub_state.mbt (typed writes)"
```

### Task B2: Extract ephemeral_hub_readers.mbt

- [ ] **Step 1:** Create `editor/ephemeral_hub_readers.mbt` — move all typed read methods:
  - `EphemeralHub::get_cursor`
  - `EphemeralHub::get_edit_mode`
  - `EphemeralHub::get_all_editing`
  - `EphemeralHub::get_presence`
  - `EphemeralHub::get_online_peers`

  These all follow: `store.get(key)` → unpack `EphemeralValue` → return domain type.

- [ ] **Step 2:** Remove from `ephemeral_hub.mbt`

- [ ] **Step 3:** Verify: `cd editor && moon check && moon test`

- [ ] **Step 4:** Commit
```bash
moon info && moon fmt
git add editor/ephemeral_hub.mbt editor/ephemeral_hub_readers.mbt
git add -A
git commit -m "refactor(editor): extract ephemeral_hub_readers.mbt (typed reads)"
```

### Task B3: Verify final state

- [ ] **Step 1:** Run full test suite: `moon test`
- [ ] **Step 2:** Verify `ephemeral_hub.mbt` is ~150 lines (struct + namespace + constructor + encode/apply/lifecycle)

---

## Plan C: Split `cmd/main/crdt.mbt` (57 JS exports → 6 files)

### File Map

| File | Action | Content |
|------|--------|---------|
| `cmd/main/crdt.mbt` | Keep | `editors` map, `create_editor`, `destroy_editor`, `get_text`, `set_text`, `get_ast_dot_resolved`, `get_ast_pretty`, `get_errors_json`, `get_version_json` (8 functions) |
| `cmd/main/crdt_undo.mbt` | Create | `create_editor_with_undo`, `insert_and_record`, `delete_and_record`, `backspace_and_record`, `set_text_and_record`, `insert_at`, `delete_at`, undo/redo manager functions (15 functions) |
| `cmd/main/crdt_ephemeral.mbt` | Create | `ephemeral_*` functions (7 functions) |
| `cmd/main/crdt_projection.mbt` | Create | `get_proj_node_json`, `get_source_map_json`, `apply_tree_edit_json` (3 functions) |
| `cmd/main/crdt_relay.mbt` | Create | `relay_on_connect`, `relay_on_message`, `relay_on_disconnect` (3 functions) |
| `cmd/main/crdt_websocket.mbt` | Create | `ws_on_open`, `ws_on_message`, `ws_on_close`, `ws_broadcast_edit`, `ws_broadcast_cursor` (5 functions) |

**Note:** The `editors` map and handle-lookup pattern stay in `crdt.mbt`. All other files reference it since they're in the same package.

### Task C1: Extract crdt_undo.mbt

- [ ] **Step 1:** Create `cmd/main/crdt_undo.mbt` — move 15 undo-related functions from `crdt.mbt`

- [ ] **Step 2:** Verify: `moon check && moon build --target js`

- [ ] **Step 3:** Commit
```bash
moon info && moon fmt
git add cmd/main/crdt.mbt cmd/main/crdt_undo.mbt
git add -A
git commit -m "refactor(cmd): extract crdt_undo.mbt (15 undo/edit functions)"
```

### Task C2: Extract crdt_ephemeral.mbt

- [ ] **Step 1:** Create `cmd/main/crdt_ephemeral.mbt` — move 7 ephemeral functions

- [ ] **Step 2:** Verify: `moon check && moon build --target js`

- [ ] **Step 3:** Commit
```bash
moon info && moon fmt
git add cmd/main/crdt.mbt cmd/main/crdt_ephemeral.mbt
git add -A
git commit -m "refactor(cmd): extract crdt_ephemeral.mbt (7 presence functions)"
```

### Task C3: Extract crdt_projection.mbt, crdt_relay.mbt, crdt_websocket.mbt

- [ ] **Step 1:** Create the 3 remaining files, moving functions from `crdt.mbt`:
  - `crdt_projection.mbt` — 3 functions
  - `crdt_relay.mbt` — 3 functions
  - `crdt_websocket.mbt` — 5 functions

- [ ] **Step 2:** Verify: `moon check && moon build --target js`

- [ ] **Step 3:** Run JS build to verify exports still work: `moon build --target js --release`

- [ ] **Step 4:** Commit
```bash
moon info && moon fmt
git add cmd/main/crdt*.mbt
git add -A
git commit -m "refactor(cmd): extract crdt_projection, crdt_relay, crdt_websocket"
```

### Task C4: Verify final state

- [ ] **Step 1:** Full test suite: `moon test`
- [ ] **Step 2:** JS build: `moon build --target js --release`
- [ ] **Step 3:** Verify `crdt.mbt` is ~100-150 lines (editors map + 8 core functions)
- [ ] **Step 4:** Verify: `wc -l cmd/main/crdt*.mbt`

---

## Dependency Graph

```text
Plan A (text_edit split)     — independent
Plan B (ephemeral hub split) — independent
Plan C (crdt FFI split)      — independent

All three can be done in parallel or any order.
```

---

## Notes for Implementer

1. **MoonBit same-package rule:** All `.mbt` files in a directory compile as one package. Moving a function to a new file in the same directory requires zero import changes. Private functions remain accessible.

2. **Cut, don't copy:** Move functions from old file to new file. Don't duplicate. The old file should shrink by exactly the lines moved.

3. **`///|` block separators:** Each function should start with `///|`. When moving functions, keep the separator.

4. **moon.pkg.json unchanged:** No package config changes needed for any of these splits.

5. **JS exports unchanged:** For Plan C, the `link.js.exports` in root `moon.pkg.json` references function names, not file names. Splitting files doesn't affect exports.

6. **Test files stay put:** Test files (`*_test.mbt`, `*_wbtest.mbt`) don't need changes — they test package-level functions regardless of which file they're in.
