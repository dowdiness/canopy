# Word-Navigation Policy over Raw UAX #29 Boundaries

**Status:** Design approved 2026-07-05 (interview-driven brainstorm). Closes the
first unchecked item of [TODO §16](../TODO.md) ("Word-navigation policy on top
of moji's raw UAX boundaries").

**GitHub context:** [#216](https://github.com/dowdiness/canopy/issues/216)
(Unicode Text Correctness), moji shipped in
[#251](https://github.com/dowdiness/canopy/pull/251).

## Problem

`SyncEditor::move_cursor_left_word` / `move_cursor_right_word`
(`editor/sync_editor_text.mbt`) currently call `@moji.prev_word_boundary` /
`next_word_boundary` directly. Raw UAX #29 word boundaries mark **every**
transition between word, whitespace, and punctuation segments — so raw
navigation stops at the edge of each whitespace run and at every individual
punctuation character. No editor user wants that. Editors layer a policy on
top: skip whitespace, treat punctuation runs as navigable units, land at
word start (left) / word end (right).

moji's contract stays raw — the policy lives entirely in the `editor`
package as a wrapper. No moji API changes.

### Consumer framing (user decision 2026-07-05)

No current front-end reaches these methods: CodeMirror surfaces handle word
navigation client-side, the canvas example uses a native `<input>`, and
there is no FFI export. The intended consumer is **canopy as a headless
editor-engine library** — future self-drawn / TUI / embedded editor
surfaces that drive `SyncEditor` directly. Under that framing these methods
are canonical engine API, and shipping raw UAX #29 behavior behind them is
a library trap (call it and get broken navigation); this policy layer fixes
the canonical surface before any consumer binds to it.

## Decisions (interview 2026-07-05)

| Axis | Decision |
|------|----------|
| Reference semantics | VS Code / Sublime style |
| Right-word landing | **End** of current/next unit (not next unit's start) |
| Left-word landing | **Start** of current/previous unit |
| Whitespace | Never a stop target; always skipped |
| Punctuation | A run of punctuation/symbols is one stop unit |
| CJK | Merged into `Other` runs — one stop per run (VS Code default). Script-boundary splitting is a named follow-up, not built now |
| camelCase / snake_case sub-word | Deferred entirely; **no config flag** (YAGNI — zero consumers) |
| Word-delete / selection | Out of scope; the pure stop-finders are the reserved extension point |

## Design

### Components

1. **`editor/word_nav.mbt`** (new file) — the policy layer:
   - A `priv` three-way segment classification: `Whitespace`, `Word`, `Other`.
   - Two `priv` pure stop-finders, `(text : String, pos : Int) -> Int`:
     one for the next right-word stop, one for the previous left-word stop.
     Pure functions of their arguments; no `SyncEditor` dependency.
2. **`editor/sync_editor_text.mbt`** — the two existing `SyncEditor` word
   methods are rewritten in place to delegate to the stop-finders. Their
   signatures and the existing top/bottom guards (`cursor == 0`,
   `cursor == text.length()`) are unchanged. No consumers exist today
   (verified 2026-07-04: no FFI export, no example/TS caller), so the
   behavior change has zero blast radius.

### Classification rule

A raw UAX segment (the span between two consecutive entries of
`@moji.word_boundaries(text)`) is classified by its **first
non-default-ignorable codepoint** (skipping codepoints where
`@moji.is_default_ignorable_code_point` holds):

- `Whitespace` — the codepoint satisfies `Char::is_whitespace` (Unicode
  White_Space property). This predicate, not `wb_of`, decides whitespace:
  tab (U+0009) has `WB=Other` and would otherwise become a stop target.
- `Word` — `@moji.wb_of` is one of `WbALetter`, `WbHebrewLetter`,
  `WbKatakana`, `WbNumeric`, `WbExtendNumLet`.
- `Other` — everything else: punctuation, symbols, Han/Hiragana ideographs,
  emoji.
- A segment consisting **entirely** of default-ignorable codepoints
  classifies as `Whitespace` (skipped, never a stop target).

Skipping default-ignorable codepoints is load-bearing (Codex validation
2026-07-05): UAX WB4 does *not* attach Format chars at text start or after
hard breaks, so e.g. `"\n\u{200E}a"` yields a raw segment led by an
invisible LRM — naive first-codepoint classification would make an
invisible character a stop target. Non-BMP codepoints are read with
`@moji.decode_codepoint_at`.

### Unit merging

Adjacent `Other` segments merge into one unit. (`Word` segments are already
maximal runs under UAX; `Whitespace` needs no merging because it is never a
target.) Merging makes `->`, `...`, and a CJK stretch each a single stop.

### Navigation semantics

Over the classified, merged unit list:

- **Right:** land at the end of the first non-whitespace unit whose end is
  strictly greater than the cursor. If none exists, land at `text.length()`.
  This yields VS Code behavior in both cases: mid-word → that word's end;
  at a word end → skip whitespace, land at the next unit's end.
- **Left:** land at the start of the last non-whitespace unit whose start is
  strictly less than the cursor. If none exists, land at `0`.

Landing positions are raw UAX word boundaries, but word boundaries are
**not** always grapheme-cluster boundaries (Codex validation 2026-07-05:
U+0600 ARABIC NUMBER SIGN is GCB=Prepend / WB=Numeric, so `"\u{600}!"` has a
word boundary inside one grapheme cluster). To preserve the editor's
cursor-on-boundary invariant, each landing is post-snapped: right-word
through `@moji.next_grapheme_boundary` (at-or-after), left-word through
`@moji.prev_grapheme_boundary` (at-or-before). Both are no-ops in the
common case. Note the shipped raw methods lack this snap — the rewrite
fixes that latent defect.

### Error handling

None required: the stop-finders are total functions. Out-of-range cursor
positions are clamped by the scan formulation itself (`> cursor` / `< cursor`
comparisons); empty text yields the trivial boundary list and the fallback
landings (`0` / `text.length()`).

### Performance

One `@moji.word_boundaries` materialization per keypress plus an O(n)
classification scan — the same complexity class as every existing mutation
path in this file (`utf16_offset_to_item_pos` is O(n) per call). TODO §16's
P3 perf item explicitly defers optimization of this class until a measured
hot path exists (moonbit-perf-investigation gate).

## Testing

- **`editor/word_nav_wbtest.mbt`** (new) — pure stop-finder fixtures:
  - `"foo bar"` — basic left/right from various offsets (mid-word, at
    boundaries, at ends).
  - `"foo->bar"` — punctuation run is one stop unit.
  - `"foo   bar"`, `"foo\tbar"`, `"foo\nbar"` — whitespace runs (space, tab,
    newline) skipped, never a target.
  - `"  foo  "` — leading/trailing whitespace: left from inside leading ws →
    0; right from inside trailing ws → length.
  - `""`, all-whitespace text — fallback landings.
  - CJK: hiragana/kanji stretch = one `Other` unit; katakana run = one
    `Word` unit; mixed `"日本語 test"` pins the merge behavior.
  - Emoji + non-BMP: a fixture with an astral-plane codepoint pinning
    UTF-16 offsets (offsets count code units).
  - Codex-validation counterexamples: `"\u{600}!"` (landing post-snapped to
    a grapheme boundary), `"\n\u{200E}a"` and `"\u{200E}a"` (default-
    ignorable-led segments never become stop targets).
- **`editor/sync_editor_text_wbtest.mbt`** (existing) — two or three
  `SyncEditor`-level integration cases confirming the methods delegate
  correctly and respect the existing guards.

Expected values are worked out by hand from the raw boundary lists (draw the
segment table per fixture), not computed by formula.

## Follow-ups (named, not built)

- **Script-boundary splitting for CJK** (kanji→hiragana boundary as a stop,
  bunsetsu-ish navigation): layers on the same unit-merging step without API
  change; requires a script-classification source moji does not expose today.
- **Word-delete / word-selection** (`Ctrl+Backspace` family): reuse the pure
  stop-finders; promote them from `priv` when the consumer appears.
- **camelCase / snake_case sub-word stops**: VS Code gates these behind
  separate commands, not the default; same here if ever wanted.
