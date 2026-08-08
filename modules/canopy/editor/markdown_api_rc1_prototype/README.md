# PROTOTYPE — Markdown public API RC1

This is throwaway logic on branch `prototype/markdown-api-rc1`. It does not
implement the production API.

## Question

Can the proposed public model satisfy both of these properties?

1. A detached document mounts as one live writing instance, failed unmount
   leaves that instance usable, successful unmount is idempotent, and remount
   receives a fresh writer identity.
2. Internal sequential UTF-16 edits can be projected into a sentinel-free
   public source so that applying the public transforms produces exactly the
   projected post-edit source, including empty paragraphs, CRLF, non-BMP text,
   and multiple transforms.

The prototype has two layers. The synthetic layer receives explicit hidden
ranges and exercises sequential transforms. The integration layer constructs
the real Markdown façade, derives hidden ranges from empty-paragraph block
snapshots, applies real structural edits, and checks the mapped transforms and
block ranges against sentinel-free portable source.

## Run

From the primary checkout root:

```bash
make -C .worktrees/markdown-api-rc1-prototype prototype-markdown-api-rc1
```

The terminal frame lists all actions. Useful sequences:

- `m`, `e`, `f`, `u`, `e`, `u`, `u`, `m` exercises failed unmount, successful
  unmount, repeated unmount, rejected detached edit, and remount.
- Press `a` until the current coordinate scenario is exhausted, then `n` for
  the next scenario. Every step should keep `projection invariant: PASS`.
- Press `i` to run the real Markdown integration matrix: LF and CRLF empty
  paragraph splits, non-BMP replacement, sentinel deletion, visible ZWSP,
  ATX/Setext headings, fenced code, and ordered-list ranges.

## Reuse check

The prototype uses MoonBit core `String`/`StringView` UTF-16 slicing,
`StringBuilder`, `Array::fold`, `Array::filter_map`, `Array::sort_by`,
`Int::max`, and `Option`, plus the existing `MarkdownEditor`, immutable
snapshots, commit receipts, and exact text transforms. Existing Canopy
`export_markdown_text` covers final portable export but does not expose the
internal-to-public offset map. Existing `text_change::compute_text_change`
can produce one consolidated diff but cannot preserve a sequential accepted
transform trace. The prototype therefore introduces only the hidden-range
projection and transform-mapping logic needed to answer this question.

No tests or persistence are included by design.

## Captured result

The synthetic lifecycle and coordinate scenarios pass. The real Markdown
integration matrix currently passes 8 of 9 cases.

The failing case merges `Hello` into a preceding empty paragraph produced by a
split. The accepted internal transform maps to portable `Hello\n`, but the real
post-edit source is `\u200BHello\n`. The current merge lowering removes the
sentinel only when the merge target text is the sentinel; it does not remove a
sentinel owned by the previous block. Consequently the sentinel ceases to be a
standalone empty paragraph and can no longer be discovered or stripped by
portable export.

Verdict: hidden-range UTF-16 projection is viable once ranges are known, and
actual LF/CRLF insertion, non-BMP edits, visible non-sentinel ZWSP, headings,
fenced code, and ordered-list ranges agree with it. The proposed guarantee that
`MarkdownSnapshot::source()` is always sentinel-free cannot be frozen until the
empty-previous-block merge invariant is repaired and re-run through this
matrix.
