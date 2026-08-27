# Loomark parser-transition performance investigation

**Date:** 2026-08-27

**Status:** The diagnosis remains valid. The implementation recommendation is superseded by [the 2026-08-28 strategy reassessment](2026-08-28-loomark-syntax-parser-strategy-reassessment.md), which compares the keyed syntax attachment with direct MarkdownIR lowering.

**Scheduling update:** The 32 ms references below preserve the measured condition. Loomark later adopted 24 ms after [an independent production-browser comparison](../evidence/2026-08-28-loomark-preview-quiet-window-24ms.md).

**Original decision:** Prototype the syntax-only semantic attachment as a two-repository change. Do not optimize `TextChange`, runtime publication, or block-boundary parsing in the same slice.

## Definition

A Loomark parser transition advances the one live Preview parser from the previous committed Document text to the next text. `PreviewEngine::apply` validates the `TextChange`, maps `ReplaceRange` to `Parser::apply_edit`, and maps `ReplaceAll` to `Parser::set_source` (`apps/loomark/internal/preview/engine.mbt`). Once Preview is `Ready` or `Failed`, the application attempts this transition for each committed edit; `Unrequested` and `Preparing` do not transition a parser. Only semantic read, typed Html construction, and publication wait for the 32 ms quiet window (`apps/loomark/app/update.mbt`).

Inside Loom, `Parser::apply_edit` calls the imperative engine and publishes one coherent snapshot through `Runtime::batch` (`deps/loom/loom/pipeline/parser.mbt`). The engine runs `incremental_parse`, then accepts the resulting tree and computes the grammar AST through `to_ast` (`deps/loom/loom/incremental/imperative_parser.mbt`). Markdown currently supplies a memoized `CstFold` for that compatibility `Block` AST (`deps/loom/loom/factories.mbt`, `deps/loom/loom/core/cst_fold.mbt`).

The parser transition is therefore separate from textarea event handling, the 32 ms quiet window, MarkdownIR semantic read, typed Html construction, and DOM publication.

## Method

The deployment-target investigation used a JavaScript release build in headless Chromium with the production Loomark surface. The fixture contained 250 heading/paragraph units, approximately 500 Markdown blocks and 22,420 UTF-16 code units. Each launch used 20 warm-up edits followed by 44 measured edits at paragraph 248.

Temporary `performance.now()` boundaries divided the transition into:

1. `TextChange` consistency validation;
2. imperative incremental parsing;
3. AST acceptance/folding;
4. snapshot publication;
5. later MarkdownIR semantic read; and
6. typed Html construction.

The instrumentation and prototypes were investigation-only. They were not added to production state or public browser APIs.

The historical production investigation reported a 16.5 ms median and 27.9 ms p95 parser transition (`docs/evidence/2026-08-26-loomark-preview-split-production-performance.md`). That measurement preceded the formal Loom lineage and toolchain update. The new measurements reproduce the same general cost but locate it more precisely.

## Results

### Edit at the paragraph boundary

The edit replaced the first character of `Paragraph 248`. Markdown block reparse requires an edit to be strictly inside the candidate block, so this edit correctly fell through to the normal incremental parser (`deps/loom/loom/core/block_reparse.mbt`).

| Phase | Launch 1 | Launch 2 | Launch 3 |
|---|---:|---:|---:|
| Parser median | 21.0 ms | 20.9 ms | 21.2 ms |
| Parser p95 | 23.7 ms | 22.6 ms | 26.0 ms |
| Parser maximum | 56.9 ms | 59.0 ms | 57.9 ms |
| Incremental parse median | 6.5 ms | 6.2 ms | 6.5 ms |
| AST accept/fold median | 14.4 ms | 14.4 ms | 14.7 ms |
| AST accept/fold maximum | 49.7 ms | 52.1 ms | 51.3 ms |
| Snapshot publication p95 | 0.1 ms | 0.1 ms | 0.1 ms |
| Input-to-visible mean | 80.8 ms | 81.5 ms | 82.1 ms |
| Input-to-visible p95 | 88.6 ms | 88.7 ms | 90.0 ms |

Within incremental parsing, `parse_tokens_indexed` accounted for approximately 6.1–6.4 ms median. Token-buffer update, old-token-cache maintenance, reuse-cursor construction, diagnostics finalization, and the rejected block-reparse precheck were each at or below approximately 0.3 ms.

The periodic maximum occurs inside `CstFold` AST acceptance. Its timing is consistent with the fold cache's documented 64-fold reachability compaction (`deps/loom/loom/core/cst_fold.mbt`), rather than runtime publication or renderer work.

### Edit strictly inside the paragraph

An edit 14 code units into the same paragraph used block reparse successfully.

| Phase | Current `Parser[Block]` result |
|---|---:|
| Parser median | 0.4–0.5 ms |
| Parser p95 | 0.8–1.0 ms |
| Block reparse median | 0.3–0.4 ms |
| Semantic read median | 2.2–2.4 ms |
| Input-to-visible mean | 45.3–46.0 ms |

For this interior-edit path, the compatibility Block fold already reuses cached results. The measured high-cost cases are block-boundary edits, edits that invalidate block ownership, and other normal-incremental fallbacks.

### `ReplaceAll` characterization

One synthetic `historyUndo` run exercised the `ReplaceAll` path. It is characterization only: it did not use a real browser undo stack and is not acceptance evidence.

| Phase | Result |
|---|---:|
| Parser median | 64.7 ms |
| Parser p95 | 81.5 ms |
| Compatibility AST accept median | 53.2 ms |
| Semantic read median | 54.4 ms |
| Input-to-visible median | 158.3 ms |

`ReplaceAll` intentionally performs a full reset. This result does not justify complete-source diffing during normal input or changing native undo ownership.

## Diagnosis

At the time of this measurement, Loomark consumed source-aware MarkdownIR from `MarkdownSemanticAttachment`; it did not consume the parser's compatibility `Block` AST. The attachment required `Parser[Block]`, so every fallback transition first paid for compatibility Block folding and later computed MarkdownIR separately (`deps/loom/examples/markdown/markdown_semantic_attachment.mbt`).

The keyed MarkdownIR implementation already contains a syntax-only attachment core over `SyntaxParser` (`deps/loom/examples/markdown/reactive_keyed_markdown_ir.mbt`). The expensive work is therefore not required by Loomark's semantic output. It results from the current public attachment constructor boundary.

## Prototype result

A temporary prototype constructed Loomark's parser with `new_syntax_parser`, reused `Grammar::to_syntax_grammar`, and exposed the existing syntax-only keyed MarkdownIR attachment core through a prototype attachment.

For the same paragraph-boundary edit:

| Phase | Syntax-only prototype |
|---|---:|
| Parser median | 6.4–6.7 ms |
| Parser p95 | 8.8–9.1 ms |
| Parser maximum | 9.8–10.2 ms |
| Input-to-visible mean | 64.2–64.5 ms |
| Input-to-visible p95 | 69.5–69.9 ms |

Relative to the equally instrumented Block-parser baseline, the prototype reduced parser median by about 68–69%, input-to-visible mean by about 21%, and input-to-visible p95 by about 21–22%. It also removed the compatibility fold's periodic 50 ms-class spike.

For the strictly interior edit, the syntax-only prototype produced no material additional improvement because block reparse and fold reuse already made that path fast.

Prototype correctness checks passed:

- Loom and Canopy targeted JS checks;
- Loomark app test: 1/1; and
- production standalone browser E2E: 16/16, including both 10 ms Text-input gates.

These results establish feasibility, not merge readiness.

## Reuse check

Existing APIs reused or validated:

- `new_syntax_parser` and `Grammar::to_syntax_grammar`;
- the existing private `attach_reactive_keyed_markdown_ir(SyntaxParser)` core;
- `Parser::apply_edit`, `Parser::set_source`, and `Runtime::batch`;
- current block-reparse, token-buffer, reuse-cursor, and `CstFold` mechanisms.

`String` and `StringView` alternatives were considered for consistency validation, but browser validation cost was at most 0.1 ms and does not justify a new helper or API. No additional cache, low-level loop, worker, queue, or parser was justified.

## Original recommended sequence (superseded)

1. **Loom:** add an additive syntax-parser entry point for the existing semantic attachment, for example `MarkdownSemanticAttachment::from_syntax_parser`. Preserve the existing `Parser[Block]` constructor and `source_document` behavior. The syntax entry point needs an equivalent owning conversion from `SyntaxSnapshot`, and the attachment must continue to neither own nor dispose its parser. The exact name and internal representation remain an API-design decision.
2. Add JS release benchmarks that compare Block-parser and syntax-parser semantic attachments for block-boundary, interior, and `ReplaceAll` transitions. Preserve full-parse parity, diagnostics, attachment disposal, and GC recovery tests.
3. Merge and release the Loom API through its normal main lineage.
4. **Canopy:** migrate only `PreviewEngine` to `SyntaxParser` and the new attachment entry point. Keep one live parser/attachment pair, per-edit transitions, `ReplaceAll` recovery, and the 32 ms publication policy unchanged.
5. Re-run production Chromium measurements and the full standalone E2E suite on the exact candidate commit.

A separate investigation may examine boundary-aware block reparse. Relaxing the strict ownership condition is correctness-sensitive and requires a syntax-form × terminator × container × operation matrix before design. It should not be combined with the syntax-parser attachment change.

## Rejected options

- Optimize `TextChange::apply`: measured consistency validation is negligible.
- Optimize `Runtime::batch` publication: measured p95 is at most 0.1 ms.
- Add another cache, parser, worker, queue, or coalescing layer: no measured need.
- Delay parser transitions until the Preview debounce: violates the current parser-per-edit contract.
- Change `ReplaceAll` into normal-input complete-source diffing: conflicts with the native edit boundary and does not address the measured dominant fold.
- Modify structural equality or backdating semantics: unnecessary for the confirmed opportunity.

## Limitations

- Chromium was used; no Safari result is claimed.
- The primary fixture is a large heading/paragraph document and does not cover every Markdown container or malformed boundary.
- Temporary instrumentation adds small overhead, so comparisons are more reliable than absolute sub-millisecond values.
- The synthetic `historyUndo` run is not a real native-undo measurement.
- The syntax-only attachment was a prototype public surface. A production Loom change still requires API review, generated-interface review, package-local tests, and independent review.
