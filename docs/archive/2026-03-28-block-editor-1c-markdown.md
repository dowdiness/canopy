# Block Editor — 1c: Markdown Import/Export

**Outcome:** `block_doc_to_markdown` and `block_doc_from_markdown` pass a round-trip test.

**Prereq:** [1b-document.md](2026-03-28-block-editor-1b-document.md) complete.
**Next plan:** [1d-web.md](2026-03-28-block-editor-1d-web.md)

---

## Files

- `main/block_export.mbt`
- `main/block_import.mbt`
- tests appended to `main/block_doc_wbtest.mbt`

---

## Export: `block_doc_to_markdown(doc) -> String`

Rules:
- Blank line before/after: headings, dividers, quotes, code blocks
- No blank lines between consecutive list items of the same style
- Different list styles (bullet → numbered) get a blank line between
- Numbered list items are renumbered from 1 (V1; start-number preservation is Phase 2)
- Code: ` ```lang\n…\n``` `
- Divider: `---`
- Raw: verbatim content

---

## Import: `block_doc_from_markdown(md, replica_id) -> BlockDoc`

Line-by-line parser. Recognised patterns:

| Input | Block type |
|-------|-----------|
| `# ` … `###### ` | `Heading(n)` |
| `- ` or `* ` | `ListItem(Bullet)` |
| `- [ ] ` | `ListItem(Todo)`, unchecked |
| `- [x] ` | `ListItem(Todo)`, checked |
| `N. ` | `ListItem(Numbered)` |
| `> ` | `Quote` |
| ` ``` ` … ` ``` ` | `Code(lang)` (fenced) |
| `---` / `***` / `___` | `Divider` |
| consecutive non-blank non-special lines | single `Paragraph` (joined with space) |
| blank line | block separator, skipped |

**V1 deviations:** unknown syntax → `Paragraph` (not `Raw`); no nested block parsing.

---

## Required tests (write first)

```
"export: paragraph"
"export: heading"
"export: mixed blocks"   (heading + paragraph + bullet list)
"export: numbered list"  (renumbered 1, 2)
"export: todo list"      ([ ] and [x])
"export: code block"
"export: divider"

"import: paragraph"
"import: heading levels"
"import: bullet list"
"import: numbered list"
"import: todo list"
"import: code block"
"import: multi-line paragraph accumulated"
  "first line\nsecond line\n\nnew para" → 2 blocks

"round-trip: heading + paragraph + bullet list"
```

---

## Checks

- [ ] All tests pass
- [ ] `moon check` clean
- [ ] Commit: `feat(block-editor): Markdown export and line-by-line import`
