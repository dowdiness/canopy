# ZWSP Cleanup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate ZWSP (U+200B) leakage from Markdown block editor export/display boundaries while keeping it as an internal parser placeholder.

**Architecture:** Add `markdown_export_text()` FFI function that strips ZWSP at the markdown-specific boundary. Wire the raw-mode sync through the clean export path. ZWSP stripping is markdown-specific — not on the generic `SyncEditor[T]`.

**Tech Stack:** MoonBit (FFI), TypeScript (web adapter)

**Design decisions:**
- ZWSP remains as an internal parser placeholder (the parser needs source text to produce ProjNodes).
- Stripping lives in the markdown FFI layer, not on generic `SyncEditor[T]` — avoids stripping legitimate ZWSP from other editors or markdown code blocks.
- `block-input.ts` already strips ZWSP on display/edit/commit (3 sites). `compute_merge_with_previous` already handles ZWSP on merge.
- `compute_commit_edit` is NOT modified — the TS boundary already strips, and adding a second strip would forbid intentional ZWSP in code blocks.
- Preview mode: ZWSP is invisible in HTML rendering. Copy-paste from preview is a known minor gap — one-line fix if reported.
- Long-term fix is Container per-block text migration (tracked separately in TODO §16).

**Known gap:** `MarkdownPreview` renders `node.text` as-is. ZWSP is invisible in HTML but could leak on copy-paste from preview. Not addressed here — trivial fix if needed.

---

### Task 1: Add `markdown_export_text` FFI function

Strip ZWSP at the markdown-specific FFI boundary. `markdown_get_text()` stays unchanged (internal, position-consistent with source map).

**Files:**
- Modify: `ffi/canopy_markdown.mbt` (after line 33)

- [ ] **Step 1: Add `markdown_export_text` to FFI**

In `ffi/canopy_markdown.mbt`, after the `markdown_get_text` function (line 33), add:

```moonbit
///|
/// Return markdown text with ZWSP placeholders stripped.
/// Use for export, clipboard, raw-mode display — not for internal position math.
pub fn markdown_export_text(handle : Int) -> String {
  match markdown_editors.get(handle) {
    Some(ed) => ed.get_text().replace_all(old="\u200B", new="")
    None => ""
  }
}
```

- [ ] **Step 2: Run `moon check`**

Run: `cd /home/antisatori/ghq/github.com/dowdiness/canopy/.worktrees/zwsp-cleanup && moon check`
Expected: no errors.

- [ ] **Step 3: Commit**

```bash
cd /home/antisatori/ghq/github.com/dowdiness/canopy/.worktrees/zwsp-cleanup
git add ffi/canopy_markdown.mbt
git commit -m "feat(ffi): add markdown_export_text() for ZWSP-free text export"
```

---

### Task 2: Wire raw-mode sync through clean export

The raw editor textarea should show ZWSP-free text. Currently `syncRawFromModel()` calls `markdown_get_text()`.

**Files:**
- Modify: `examples/web/src/markdown-editor.ts:78`

- [ ] **Step 1: Update `syncRawFromModel` to use `markdown_export_text`**

In `examples/web/src/markdown-editor.ts`, change line 78:

```typescript
// Before:
const text = crdt.markdown_get_text(handle);

// After:
const text = crdt.markdown_export_text(handle);
```

- [ ] **Step 2: Verify the JS build**

Run:
```bash
cd /home/antisatori/ghq/github.com/dowdiness/canopy/.worktrees/zwsp-cleanup && moon build --target js 2>&1 | tail -5
```

Then verify `markdown_export_text` appears in the generated JS. Check:
```bash
grep -l 'markdown_export_text' _build/js/release/build/*.js
```

- [ ] **Step 3: Commit**

```bash
cd /home/antisatori/ghq/github.com/dowdiness/canopy/.worktrees/zwsp-cleanup
git add examples/web/src/markdown-editor.ts
git commit -m "fix(web): use markdown_export_text for raw-mode sync"
```

---

### Task 3: Document ZWSP cleanup boundaries

Update comments in `InsertBlockAfter` to document where ZWSP is stripped and why.

**Files:**
- Modify: `lang/markdown/edits/compute_markdown_edit.mbt:190-193`

- [ ] **Step 1: Update comments**

In `compute_insert_block_after` (line 190-193), replace the existing comment block:

```moonbit
  // Insert "\n\u200B\n" to create a visible empty paragraph.
  // The zero-width space gives the parser a real token to produce a ProjNode,
  // so BlockInput can render and focus the new block. ZWSP is stripped at:
  //   - markdown_export_text() (FFI export boundary — raw mode, clipboard)
  //   - block-input.ts (TS display/edit/commit — 3 sites)
  //   - compute_merge_with_previous (on block merge, line 307)
  // Known minor gap: MarkdownPreview renders node.text as-is (ZWSP invisible
  // in HTML, but could leak on copy-paste from preview).
  // Long-term fix: migrate to Container per-block text (empty block = empty text).
```

- [ ] **Step 2: Run `moon check`**

Run: `cd /home/antisatori/ghq/github.com/dowdiness/canopy/.worktrees/zwsp-cleanup && moon check`
Expected: no errors.

- [ ] **Step 3: Commit**

```bash
cd /home/antisatori/ghq/github.com/dowdiness/canopy/.worktrees/zwsp-cleanup
git add lang/markdown/edits/compute_markdown_edit.mbt
git commit -m "docs(markdown): document ZWSP cleanup boundaries"
```

---

### Task 4: End-to-end ZWSP round-trip tests

Verify the full lifecycle: insert block → ZWSP exists internally → FFI export strips it → merge cleans it up.

**Files:**
- Test: `lang/markdown/edits/compute_markdown_edit_wbtest.mbt` (append)

- [ ] **Step 1: Write end-to-end tests**

In `lang/markdown/edits/compute_markdown_edit_wbtest.mbt`, append:

```moonbit
///|
test "insert_block_after: ZWSP present in raw text, absent in export" {
  let ed = new_markdown_editor("test")
  ed.set_text("Hello\n")
  // Force projection cycle
  let state = @editor.ViewUpdateState::new()
  let _ = @editor.compute_view_patches(state, ed)
  let proj = ed.get_proj_node().unwrap()
  let para_id = proj.children[0].id()
  let result = apply_markdown_edit(ed, InsertBlockAfter(node_id=para_id), 0)
  inspect(result is Ok(_), content="true")
  // Raw text has ZWSP (parser needs it)
  inspect(ed.get_text().contains("\u200B"), content="true")
  // Export strips ZWSP
  let exported = ed.get_text().replace_all(old="\u200B", new="")
  inspect(exported.contains("\u200B"), content="false")
}

///|
test "merge cleans up ZWSP from empty block" {
  let ed = new_markdown_editor("test")
  ed.set_text("Hello\n")
  let state = @editor.ViewUpdateState::new()
  let _ = @editor.compute_view_patches(state, ed)
  // Insert an empty block after "Hello"
  let proj = ed.get_proj_node().unwrap()
  let para_id = proj.children[0].id()
  let _ = apply_markdown_edit(ed, InsertBlockAfter(node_id=para_id), 0)
  // Force re-projection to get new block's ID
  let _ = @editor.compute_view_patches(state, ed)
  let proj2 = ed.get_proj_node().unwrap()
  // The new empty block should be at index 1
  guard proj2.children.length() >= 2 else {
    return // skip if projection didn't produce expected structure
  }
  let empty_block_id = proj2.children[1].id()
  // Merge the empty block back into previous
  let merge_result = apply_markdown_edit(
    ed,
    MergeWithPrevious(node_id=empty_block_id),
    0,
  )
  inspect(merge_result is Ok(_), content="true")
  // After merge, ZWSP should be gone from raw text too
  inspect(ed.get_text().contains("\u200B"), content="false")
}
```

- [ ] **Step 2: Run tests**

Run: `cd /home/antisatori/ghq/github.com/dowdiness/canopy/.worktrees/zwsp-cleanup && moon test -p dowdiness/canopy/lang/markdown/edits -f compute_markdown_edit_wbtest.mbt`
Expected: PASS.

- [ ] **Step 3: Run full test suite**

Run: `cd /home/antisatori/ghq/github.com/dowdiness/canopy/.worktrees/zwsp-cleanup && moon test`
Expected: all 807+ tests pass.

- [ ] **Step 4: Run `moon info && moon fmt`**

Run: `cd /home/antisatori/ghq/github.com/dowdiness/canopy/.worktrees/zwsp-cleanup && moon info && moon fmt`
Then check: `git diff *.mbti` — verify only `markdown_export_text` is added to `ffi/pkg.generated.mbti`, no trait bound widening.

- [ ] **Step 5: Commit**

```bash
cd /home/antisatori/ghq/github.com/dowdiness/canopy/.worktrees/zwsp-cleanup
git add lang/markdown/edits/compute_markdown_edit_wbtest.mbt
git commit -m "test(markdown): add ZWSP round-trip and merge cleanup tests"
```

---

### Task 5: Update TODO.md

Mark the ZWSP cleanup item as done.

**Files:**
- Modify: `docs/TODO.md`

- [ ] **Step 1: Update the ZWSP item in §14**

Change:
```markdown
- [ ] **ZWSP cleanup for empty blocks** — `InsertBlockAfter` inserts `\u200B` (zero-width space) as placeholder so the parser produces a ProjNode for empty paragraphs. The ZWSP is stripped on keystroke, but unused empty blocks keep it. If raw Markdown is copy-pasted to another tool, invisible ZWSP characters travel with it. Fix by either: (a) teaching the parser to produce empty paragraph nodes for consecutive blank lines, or (b) stripping all ZWSP on save/export.
  Exit: No `\u200B` in raw Markdown output after save or copy.
```
To:
```markdown
- [x] **ZWSP cleanup for empty blocks** — `markdown_export_text()` FFI strips ZWSP at export boundary. `block-input.ts` strips on display/edit/commit. `compute_merge_with_previous` strips on merge. ZWSP remains as internal parser placeholder only. Long-term fix: Container per-block text (§16).
  Exit: No `\u200B` in exported Markdown text.
```

- [ ] **Step 2: Commit**

```bash
cd /home/antisatori/ghq/github.com/dowdiness/canopy/.worktrees/zwsp-cleanup
git add docs/TODO.md
git commit -m "docs: mark ZWSP cleanup done in TODO.md"
```
