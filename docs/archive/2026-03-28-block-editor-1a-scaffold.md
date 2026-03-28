# Block Editor — 1a: Scaffold + Types

**Outcome:** `examples/block-editor/` compiles with `moon check`. Core types are defined.

**Next plan:** [1b-document.md](2026-03-28-block-editor-1b-document.md)

---

## Files to create

```
examples/block-editor/
├── moon.mod.json          — module (deps: dowdiness/canopy path ../..)
├── main/
│   ├── moon.pkg           — is-main: true, js exports: [] (filled in 1c)
│   ├── block_types.mbt    — BlockType, ListStyle
│   └── ffi.mbt            — empty stub
└── web/
    ├── package.json       — scripts: dev, build (mirrors examples/canvas/web)
    ├── tsconfig.json
    ├── vite.config.ts     — alias @moonbit → _build/js/release/build/…/main
    └── index.html         — #toolbar (Download/Upload buttons), #editor-blocks
```

---

## Types: `block_types.mbt`

```moonbit
pub enum ListStyle { Bullet | Numbered | Todo }
pub enum BlockType {
  Paragraph
  Heading(Int)        // level 1–6
  ListItem(ListStyle)
  Quote
  Code(String)        // language, empty = plain
  Divider             // no text content
  Raw                 // verbatim, no parsing
}
```

Helpers:

```moonbit
// Returns (type_str, extra_props)
pub fn block_type_to_string(t : BlockType) -> (String, Map[String, String])

// Inverse — reads "type" string + prop getter
pub fn block_type_from_props(
  type_str : String,
  get : (String) -> String?,
) -> BlockType
```

---

## Checks

- [x] `moon check` passes
- [x] Commit: `feat(block-editor): scaffold module and block types`
