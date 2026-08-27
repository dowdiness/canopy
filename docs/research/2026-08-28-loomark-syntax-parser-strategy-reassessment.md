# Loomark SyntaxParser strategy reassessment

**Date:** 2026-08-28

**Supersedes the implementation recommendation in:** [2026-08-27 Loomark parser-transition performance investigation](2026-08-27-loomark-parser-transition-performance.md)

## Decision

Use one long-lived `SyntaxParser` in Loomark and perform one direct, stateless MarkdownIR lowering from its coherent snapshot at each allowed Preview refresh. Do not add a syntax-specific `MarkdownSemanticAttachment` API for Loomark now.

The intended Preview path is:

```text
committed TextChange
  -> SyntaxParser::apply_edit or set_source
  -> 32 ms candidate-text quiet-window check
  -> SyntaxParser::snapshot().read_or_abort()
  -> experimental_markdown_ir_from_syntax_with_diagnostics
  -> typed Html
  -> publication
```

This retains incremental parsing on every committed edit while treating semantic rendering as a one-shot operation after the quiet window. It removes the compatibility `Block` fold and the retained keyed semantic shell from Loomark. Other `Parser[Block]` and `MarkdownSemanticAttachment` consumers remain unchanged.

## Why the first recommendation was reconsidered

The first investigation compared the current `Parser[Block]` path with a syntax-only parser backed by the existing keyed MarkdownIR shell. That prototype reduced a 500-block boundary-edit parser transition from about 21 ms to 6.4–6.7 ms and input-to-visible latency from about 81 ms to 64–65 ms.

It did not compare the keyed shell with Loom's existing public one-shot MarkdownIR lowering after the parser had already become syntax-only. That comparison changes the decision.

Loom's accepted architecture deliberately keeps both forms:

- retained keyed attachments for consumers that benefit from block-local semantic reuse; and
- stateless one-shot lowering for direct export, rendering, and snapshot reads.

See `deps/loom/docs/decisions/2026-08-04-markdown-semantic-attachment-boundary.md`, `deps/loom/docs/decisions/2026-06-16-markdown-ir-performance-policy.md`, and `deps/loom/examples/markdown/markdown_ir_lowering.mbt`.

Loomark renders one complete Preview after a quiet window. It does not retain or transform the returned MarkdownIR, does not call `source_document()`, and already rebuilds typed Html for the complete document (`apps/loomark/internal/preview/engine.mbt`, `renderer.mbt`). The semantic operation is therefore snapshot-oriented even though the parser is long-lived.

## Alternatives investigated

### 1. SyntaxParser plus keyed semantic attachment

A production-shaped prototype added `attach_markdown_semantics(SyntaxParser)` while preserving the existing `MarkdownSemanticAttachment(Parser[Block])`. Both constructors normalized complete snapshots into the same private keyed shell. `source_document()` read the shell's coherent snapshot, so the attachment no longer needed to store or dispose its parser.

This is the best attachment design if a retained attachment is required. A free `attach_*` function matches `attach_markdown_projection` and `attach_markdown_role_spans` better than an asymmetric `from_syntax_parser` constructor.

It still performs poorly when normal incremental parsing rebases reused CSTs onto the current source. The keyed shell's `CstNode` structural keys then pay expensive equality work across the document (`reactive_keyed_markdown_ir.mbt`).

### 2. SyntaxParser plus direct MarkdownIR lowering

This uses only existing public APIs:

- `new_syntax_parser`;
- `Grammar::to_syntax_grammar`;
- `SyntaxParser::snapshot`; and
- `experimental_markdown_ir_from_syntax_with_diagnostics`.

No Loom public API, additional cache, lifecycle type, or second parser is needed. Source, syntax, and diagnostics come from one `SyntaxSnapshot`; `source_id` comes from that same parser. The direct lowering function is deterministic and non-raising. The returned MarkdownIR is consumed immediately by the typed renderer.

This is the selected design.

### 3. Disable or adapt CstFold while retaining Parser[Block]

A JavaScript release prototype replaced memoized `CstFold` with direct recursive Block folding.

| 500-block parser transition | Memoized CstFold | Direct recursive fold | SyntaxParser |
|---|---:|---:|---:|
| boundary median | 5.53–5.83 ms | 4.01–4.15 ms | 3.34–3.54 ms |
| interior median | 0.41–0.45 ms | 0.63–0.67 ms | 0.14–0.18 ms |

Disabling the cache improved fallback edits but remained slower than SyntaxParser and regressed the fast block-reparse path. It also continued constructing an AST Loomark never reads.

CstFold statistics explained the fallback behavior: a boundary edit reported 499 parser reuses and only two AST recomputations, but the fold still performed about 500 structural cache hits. Parser reuse rebuilds current-source-backed tokens and nodes by contract, so structurally equal nodes are often not physically identical. A general reuse-provenance identity could improve this, but it would cross `seam`, parser events, CstFold, and Markdown derived-map keys. No small, validated prototype justified that redesign for Loomark.

### 4. Lazy or optional AST in Parser[Ast]

Moving AST computation into a lazy Derived would alter the coherent `ParseSnapshot[Ast]` contract and every existing AST consumer. If the semantic attachment then read a syntax-only snapshot to avoid forcing the AST, the result would reproduce SyntaxParser through a larger and riskier interface. `SyntaxParser` already exists for this responsibility (`deps/loom/loom/pipeline/syntax_parser.mbt`, `docs/api/choosing-a-parser.md`).

### 5. Common SyntaxFeed interface

An opaque feed containing `source_id`, runtime, and `Derived[SyntaxSnapshot]` could adapt both parser forms. A public trait cannot enforce that all three capabilities originate from one parser. No second independent consumer currently needs the opaque value. The new type and its methods would exist solely to avoid one Markdown constructor mismatch.

### 6. MarkdownSemanticParser facade

A facade owning SyntaxParser plus the semantic shell would duplicate `apply_edit`, `set_source`, runtime, source identity, failure, and disposal behavior. It would make independent parser attachments harder and add no capability. The parser plus a snapshot read is the deeper existing module.

### 7. Adaptive keyed/direct strategy

The measured ideal would use keyed lowering after successful block reparse and direct lowering after normal fallback. The current public snapshot exposes `reuse_count`, not a stable transition-kind contract. Treating `reuse_count == 1` as block reparse would be a performance heuristic.

A skipped keyed read also leaves the retained shell stale. Warming it after direct output merely moves the expensive work, while disposing and recreating it adds another lifecycle mode. The complexity is not justified. Issue [Loom #933](https://github.com/dowdiness/loom/issues/933) may reduce boundary fallbacks without such a policy.

## Deployment-target results

All browser comparisons used JavaScript release builds, the same Chromium harness, 20 warm-up edits, and 44 measured edits. The 500-block corpus is Loomark's 250 heading/paragraph-unit fixture. The 2,500-block corpus uses 1,250 units. Typed Html and parser policies were unchanged between strategies.

### 500 blocks

| Edit and strategy | Parser median | Semantic median | Html median | Visible median | Visible p95 |
|---|---:|---:|---:|---:|---:|
| boundary, keyed attachment | 6.3 ms | 14.9 ms | 1.8 ms | 64.0 ms | 69.8 ms |
| boundary, direct | 6.3 ms | 3.7 ms | 1.7 ms | 49.6 ms | 60.1 ms |
| interior, keyed attachment | 0.4 ms | 2.2 ms | 1.8 ms | 47.1 ms | 49.6 ms |
| interior, direct | 0.4 ms | 3.8 ms | 1.6 ms | 47.0 ms | 48.8 ms |

Direct lowering materially improves the fallback case and is end-to-end neutral for the fast interior case.

### 2,500 blocks

| Edit and strategy | Parser median | Semantic median | Html median | Visible median | Visible p95 |
|---|---:|---:|---:|---:|---:|
| boundary, keyed attachment | 61.6 ms | 339.4 ms | 9.8 ms | 487.3 ms | 507.1 ms |
| boundary, direct | 60.8 ms | 18.7 ms | 10.0 ms | 159.6 ms | 181.8 ms |
| interior, keyed attachment | 0.6 ms | 8.2 ms | 8.6 ms | 90.4 ms | 107.1 ms |
| interior, direct | 0.6 ms | 16.4 ms | 9.8 ms | 99.7 ms | 123.1 ms |

The keyed shell wins a strictly interior edit by about 9 ms median, but loses a boundary fallback by about 328 ms median. Direct lowering gives a much lower and more predictable tail while retaining acceptable interior behavior.

### Node release controls

The result depends on CST reuse shape, not document size alone:

- Loomark-shaped 500-block boundary cycle: keyed attachment 19.95–20.68 ms; direct 15.34–17.16 ms.
- Loomark-shaped 2,500-block boundary cycle: keyed attachment 287–292 ms; direct 128–132 ms.
- Generic paragraph 2,500-block interior cycle: keyed attachment 20.9–21.7 ms; direct 77.5–80.8 ms.

These controls reject a universal claim that either semantic strategy is always faster. The browser product decision uses Loomark's complete pipeline and values bounded fallback latency over the keyed shell's large-document interior advantage.

A synthetic 500-block `ReplaceAll` characterization measured direct SyntaxParser output at 57 ms median and 80.9 ms p95, versus the earlier `Parser[Block]` attachment characterization at 158.3 ms median. This is not native-undo acceptance evidence.

Cold measurements were noisy and do not select a strategy. Direct 500-block launches ranged from 219–296 ms; syntax attachment launches ranged from 208–303 ms. One 2,500-block observation was 394 ms direct versus 434 ms attachment.

## Semantics and ownership

- `PreviewEngine` continues to own at most one live parser.
- `ReplaceRange` still calls `apply_edit`; `ReplaceAll` still calls `set_source`.
- Parser transitions still happen for every committed edit while Preview is live.
- MarkdownIR lowering happens only in `refresh`, after the existing candidate-text quiet-window check.
- `SyntaxParser::snapshot()` keeps source, syntax, diagnostics, and reuse metadata coherent.
- Direct lowering neither mutates nor owns the parser.
- There is no attachment, scope, watch, cache, or disposal lifecycle to expose or maintain.
- Existing broken-parser replacement and `OutOfSync` checks stay unchanged.

The direct lowering and current attachment `document()` are both total public operations over a healthy parser snapshot. Internal invariant aborts are contract violations in either path; the strategy does not remove a recoverable error channel.

The current candidate-text quiet-window policy, including its deliberate lack of revision epochs or cancellation handles, is unchanged.

## Validation evidence

Temporary direct and syntax-attachment prototypes each passed:

- Loomark production standalone E2E: 16/16;
- both 10 ms Text-input gates;
- Markdown semantic attachment tests, including coherent owning syntax snapshots: 9/9; and
- targeted Markdown JS check.

The selected Canopy implementation then passed the standalone E2E suite, both
10 ms Text-input gates, 13 targeted app and Preview tests, and strict JS checks.
Three fresh uninstrumented production launches measured the 500-block boundary
fixture as follows:

| Launch | Input-to-visible mean | Median | p95 | Maximum |
|---|---:|---:|---:|---:|
| 1 | 50.89 ms | 49.4 ms | 60.2 ms | 64.6 ms |
| 2 | 52.20 ms | 50.3 ms | 61.2 ms | 61.5 ms |
| 3 | 51.52 ms | 49.1 ms | 62.6 ms | 63.8 ms |

The prior formal production confirmation on the keyed `Parser[Block]` path was
79.30–80.19 ms mean and 87.8–88.5 ms p95. The candidate therefore reduces the
complete product latency by about 35% mean while preserving the Text-input gate.

Permanent varying-operand JavaScript release benchmarks recorded:

| Preview cycle | Mean |
|---|---:|
| 500-block boundary | 10.18 ms |
| 500-block interior | 4.78 ms |
| 2,500-block boundary | 67.84 ms |
| 2,500-block interior | 30.59 ms |

Temporary prototypes and instrumentation were removed. The permanent benchmark
uses 16 distributed edit locations followed by the inverse sequence, so every
cycle restores its initial source.

## Implemented sequence

1. Implemented the Canopy-only direct strategy in `apps/loomark/internal/preview/engine.mbt` using existing Loom APIs.
2. Preserved initial lazy parser construction, one live parser, parser-per-edit transitions, candidate-text quiet window, last-completed Preview, and retry boundaries.
3. Updated engine and renderer tests plus Loomark context and planning documentation.
4. Added permanent JS release benchmark rows for 500 and 2,500 blocks, covering boundary fallback and strictly interior block reparse with varying operands.
5. Ran the complete standalone E2E suite and fresh production-browser measurements on the candidate tree.
6. Kept Loom #933 separate. Reconsider a retained syntax attachment only after boundary reparsing or stable reuse provenance removes the keyed shell's fallback pathology.

## Reuse check

Reused:

- `new_syntax_parser`;
- `Grammar::to_syntax_grammar`;
- `SyntaxParser::{apply_edit,set_source,snapshot,source_id}`;
- `experimental_markdown_ir_from_syntax_with_diagnostics`;
- existing typed renderer and Preview refresh policy.

Checked but not selected:

- `MarkdownSemanticAttachment`: retained for other consumers; its keyed lifecycle is not the best Loomark refresh strategy under the measured matrix.
- `attach_markdown_projection`: returns compatibility `Block`, not the MarkdownIR required by Loomark's typed renderer.
- direct recursive Block fold: still performs unused compatibility work.
- common syntax-feed and MarkdownSemanticParser types: too little reuse across callers to justify their added surface.

No new Loom function, helper, type, cache, low-level loop, worker, queue, parser, or public trait is required.

## Limitations

- Chromium is measured; no Safari result is claimed.
- The edit matrix isolates paragraph boundary and interior replacements; Loom #933 owns the broader syntax/terminator/container matrix.
- Allocation and heap retention were not separately measured. Direct lowering allocates one short-lived MarkdownIR per refresh; the attachment retains keyed Incr state and collects it after reads.
- Large-document interior edits remain faster with the keyed attachment. The selection prioritizes the full Loomark pipeline, simpler ownership, and much lower fallback tails.
