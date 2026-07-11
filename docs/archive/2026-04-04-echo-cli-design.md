# Echo CLI — Dogfooding Tool Design

**Status:** Approved
**Date:** 2026-04-04

## Goal

Build a one-shot CLI tool for posting memos and querying similar posts. Persists posts to a JSON file. Used for dogfooding the echo TF-IDF pipeline with real data.

## Commands

```bash
moon run echo/cmd -- post "CRDTのmerge操作でバグを見つけた"
# → Added post #42. Similar:
# →   #12 (0.72) CRDTの実装でFugueMaxアルゴリズムを使う
# →   #8  (0.65) 共同編集にはCRDTかOTが必要

moon run echo/cmd -- similar "CRDTのmerge"
# → #12 (0.72) CRDTの実装でFugueMaxアルゴリズムを使う
# → #8  (0.65) 共同編集にはCRDTかOTが必要

moon run echo/cmd -- list
# → #0 2026-04-04T10:00:00Z CRDTのmerge操作でバグを見つけた
# → #1 2026-04-04T11:30:00Z 今日はカレーを作った
# → ...

moon run echo/cmd -- similar-to 42
# → (queries by stored post ID instead of raw text)
```

`post` also shows similar posts after adding — this is the core "auto-structuring" feedback loop.

## Persistence

- File: `~/.echo/posts.json`
- Format: JSON array of objects
  ```json
  [
    {"text": "CRDTのmerge操作でバグを見つけた", "ts": "2026-04-04T10:00:00Z"},
    {"text": "今日はカレーを作った", "ts": "2026-04-04T11:30:00Z"}
  ]
  ```
- On startup: read file (create empty `[]` if missing), `add_post` for each → rebuild corpus
- On `post`: append to array, write entire file back
- TF-IDF vectors are always recomputed from text, never stored
- Post IDs are array indices (0-based, stable across sessions since we never delete)

## Package Structure

```
echo/cmd/          — CLI entry point
echo/cmd/moon.pkg  — is-main: true, imports echo/ and echo/tokenizer/
echo/cmd/main.mbt  — arg parsing, file I/O, output formatting
```

All I/O lives in `echo/cmd/`. The `echo/` library stays pure (no FFI, no file access).

## Target

JS target (Node.js). File I/O via `node:fs` FFI. Arg parsing via `process.argv` FFI.

## Tokenizer

Uses `@tokenizer.blended` (bigram + TinySegmenter) — best overall P@5.

## Edge Cases

- No posts file → create `~/.echo/posts.json` with `[]`
- Empty corpus → `similar` and `similar-to` return "No posts yet"
- No arguments → print usage help
- Invalid command → print usage help
- `similar-to` with invalid ID → "Post not found"
- Empty text in `post` → "Text cannot be empty"

## Out of Scope

- Interactive REPL mode
- Post deletion/editing
- Tags or categories (the whole point is no manual organization)
- Web UI (Phase 2 is the block editor, not a standalone web app)
