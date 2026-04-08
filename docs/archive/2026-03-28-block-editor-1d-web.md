# Block Editor — 1d: JS Bridge + Web Shell

**Outcome:** Dev server runs. Users can type, press Enter/Backspace, autoformat with Markdown prefixes, and download/upload `.md` files.

**Prereq:** [1c-markdown.md](2026-03-28-block-editor-1c-markdown.md) complete.

---

## Files

- `main/block_init.mbt` — handle registry + exported bridge functions
- `main/moon.pkg` — updated with full JS export list
- `web/src/main.ts` — TypeScript shell

---

## Bridge API (`block_init.mbt`)

```moonbit
// Handle registry (same pattern as canvas)
pub fn create_editor() -> Int
pub fn get_render_state(handle) -> String   // JSON: { blocks: BlockJson[] }
pub fn editor_insert_block_after(handle, after_id_str, block_type_str) -> String  // returns new id
pub fn editor_set_block_text(handle, id_str, text)
pub fn editor_delete_block(handle, id_str)
pub fn editor_set_block_type(handle, id_str, type_str, level)
pub fn editor_import_markdown(handle, md)
pub fn editor_export_markdown(handle) -> String
```

`BlockJson` fields: `id: String` ("agent:counter"), `block_type`, `level`, `list_style`, `checked`, `text`.

`id_str` parsing: split on last `:` → `{agent, counter}`. Agent IDs must not contain `:`.

---

## TypeScript shell (`web/src/main.ts`)

Architecture:
- `create_editor()` → handle
- Seed document with `editor_import_markdown`
- RAF render loop: `get_render_state` → JSON → patch `contenteditable` divs
- Each div: `data-block-id`, `data-type`, `data-level`, `data-bullet`

Event handlers per block div:
- `input` → `editor_set_block_text`
- `Enter` (not Shift) → `editor_insert_block_after`, focus new div
- `Backspace` on empty block → `editor_delete_block`, focus prev div
- `Space` after autoformat prefix → `editor_set_block_type` + clear text

Autoformat prefixes (detected on Space):
| Typed | Converts to |
|-------|------------|
| `#` … `######` | `Heading(n)` |
| `-` or `*` | `ListItem(Bullet)` |
| `N.` | `ListItem(Numbered)` |
| `- [ ]` | `ListItem(Todo)` |
| `>` | `Quote` |

Toolbar:
- **Download .md** — `editor_export_markdown` → `Blob` → `<a download>` click
- **Upload .md** — `<input type="file">` → `FileReader` → `editor_import_markdown`, clear `blockDivs` Map

---

## Smoke test checklist

- [ ] Editor loads with seeded document
- [ ] Typing in a block updates state
- [ ] Enter creates block below cursor position
- [ ] Backspace on empty block removes it
- [ ] `##` + Space → Heading(2)
- [ ] `-` + Space → bullet list item
- [ ] Download .md produces correct Markdown
- [ ] Upload .md replaces document

---

## Checks

- [ ] `moon test` passes
- [ ] `moon build --target js --release` succeeds
- [ ] All exported symbols present in built JS
- [ ] Smoke test passes
- [ ] `moon info && moon fmt`
- [ ] Commit: `feat(block-editor): JS bridge and TypeScript web shell`
