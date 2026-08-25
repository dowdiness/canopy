# Loomark browser TextEdit prototype evidence

- **Issue:** [#1368](https://github.com/dowdiness/canopy/issues/1368)
- **Parent:** [#1351](https://github.com/dowdiness/canopy/issues/1351)
- **Measured prototype commit:** `5372f9c454dd7f641f3c4f6fffa7ab0e443da7a9`
- **Date:** 2026-08-25

## Decision

**Production Preview rollout: NO-GO.**

The operation-capture hypothesis is validated, but the complete prototype does
not satisfy the predeclared observed-maximum Preview gate.

The operation-capture boundary passed:

- supported ordinary input required no complete textarea value read;
- supported ordinary input required no complete-source diff;
- one exact UTF-16 `TextChange` updated both Document text and the long-lived
  Loom Parser;
- all three practical-corpus runs completed 90 forward/reverse accepted edits
  with zero recovery;
- steady-state Preview preparation passed comfortably at 3.3–3.6 ms median and
  5.1–5.7 ms p95.

The first incremental insert after initial Preview preparation was consistently
cold. It took 11.7–13.7 ms of measured preparation CPU across three fresh
browser launches. Because the contract requires both p95 and observed maximum
at or below 10 ms, the branch remains throwaway evidence and must not be merged
as production Preview.

## Question

Can Warren/Rabbita capture exact native textarea range edits and feed them to
Document text and Loom's Incremental Parser without reconstructing an edit from
complete pre-edit and post-edit strings?

For the measured ordinary-input matrix, **yes**.

## Architecture exercised

```text
native beforeinput/input/composition events
  -> synchronous binding-owned event correlation
  -> immutable UTF-16 observations
  -> pure range resolution and String-backed transition
  -> next Document text + existing dowdiness/text_change::TextChange
  -> PreviewEngine::advance / Parser::apply_edit
```

The standard Rabbita Model still owns one Document text. Parser, semantic
attachment, mutable event-correlation refs, DOM access, and performance marks
remain outside Model.

The textarea is browser-owned during native input. Its Rabbita view has no
controlled `value` property and no named `on_input` callback that materializes
the complete value. Complete text is installed only after open and when a
layout boundary creates a new textarea. Unsupported input invokes an explicitly
named whole-value recovery.

## Critical event-boundary finding

`beforeinput` and `input` cannot be correlated through two ordinary Rabbita
Model messages. Both browser events can occur before the TEA loop processes the
first message. A rapid native `insertText` therefore reached `input` before a
Model-held pending value was dependable.

The smallest correct seam correlates those two event facts synchronously inside
the internal browser binding, then emits the pair as immutable values. This is
imperative-shell state, not document authority. The binding stores no Document
text and no callback, command, Parser, or runtime handle.

The binding reads `HTMLTextAreaElement.textLength`, not
`textarea.value.length`. A production-browser test instruments the native
`value` getter and setter after initial installation and observes zero getter
calls and zero setter calls across insertion, replacement, deletion, line
break, non-BMP and combining text, paste, and cut.

## Supported and recovery boundaries

Validated without complete value reads, diff, or recovery:

- insertion;
- non-empty selection replacement;
- backward and forward deletion;
- Enter/line break normalized to LF;
- paste and cut;
- non-BMP emoji and combining-mark text;
- real Chromium IME update and commit through CDP;
- real Chromium IME cancellation preserving accepted text;
- a Ready Preview Parser consuming replacement, emoji deletion, paste, and cut.

Browser undo is deliberately unsupported by the range resolver. Chromium emits
`historyUndo` with null data and can restore an arbitrary coalesced edit group.
The prototype performs one named whole-value recovery instead of guessing.
`historyRedo` follows the same boundary. Autocorrect, dictation, mobile virtual
keyboard, and drag-and-drop were not established by this prototype and remain
outside its supported claim.

## Practical corpus

All product measurements use the same provisional #1156 corpus:

| Property | Value |
|---|---:|
| Fixture units | 250 |
| UTF-16 code units | 22,419 |
| Lines | 1,000 |
| Approximate Markdown blocks | 500 |
| Operations per launch | 45 measured + 45 unmeasured exact inverses |
| Matrix | insert/delete/replace x beginning/middle/end x 5 repetitions |

The corpus is installed through browser storage before measurement. Every
measured mutation and inverse uses native browser events. No `.fill()` or
programmatic `input` dispatch occurs in the measured matrix.

## Environment

- Moon `0.1.20260819`
- Moon compiler `v0.10.9+6e6c44045`
- Node.js `v24.14.1`
- Playwright Chromium `149.0.7827.55`
- JavaScript release build
- Headless Chromium on the same local host

Raw samples:

- `docs/evidence/2026-08-25-loomark-browser-text-edit-samples-run-1.json`
- `docs/evidence/2026-08-25-loomark-browser-text-edit-samples-run-2.json`
- `docs/evidence/2026-08-25-loomark-browser-text-edit-samples-run-3.json`

## Three fresh-browser launches

Preparation sum is:

```text
Parser::apply_edit
+ semantic attachment read
+ typed Html materialization
+ Preview prepare parser check
```

It excludes paint and frame waiting. The pure String-backed range transition is
measured separately because the deterministic update core contains no clock or
instrumentation side effect.

| Launch | Median | p95 | Maximum |
|---|---:|---:|---:|
| 1 | 3.4 ms | 5.1 ms | 13.7 ms |
| 2 | 3.6 ms | 5.7 ms | 13.0 ms |
| 3 | 3.3 ms | 5.7 ms | 11.7 ms |

Every maximum is the first measured incremental insertion near the beginning.
Its phase breakdown was:

| Launch | Parser edit | Semantic read | Html materialization | Sum |
|---|---:|---:|---:|---:|
| 1 | 3.5 ms | 7.8 ms | 2.4 ms | 13.7 ms |
| 2 | 3.6 ms | 7.0 ms | 2.4 ms | 13.0 ms |
| 3 | 3.9 ms | 6.1 ms | 1.7 ms | 11.7 ms |

Later samples did not reproduce that combined cost. This is consistent with a
cold incremental/JIT path, but the evidence does not prove a runtime cause.
No artificial no-op edit or warm-up operation was added to hide it.

`loomark-preview-total` is after-render wall time and includes frame scheduling.
Its p95 was 15.9–16.0 ms; it is not treated as CPU phase evidence.

## Range-transition diagnostic

The JavaScript release MoonBit benchmark varies ten accepted ranges in each of
nine operation/position scenarios. All nine means were 44.64–50.19 ns in the
measured run.

That number is diagnostic only. JavaScript substring/concatenation may retain
rope-like or lazy representations, so the benchmark is not evidence that all
characters were eagerly copied. The production gate is the Warren integration,
which forces the resulting text through `Parser::apply_edit` and Preview.

## Correctness and validation

- pure range-resolution tests: 9/9;
- JavaScript release range benchmarks: 9/9;
- Warren production E2E: 15/15;
- native value getter/setter instrumentation: zero ordinary reads/writes;
- real Chromium IME commit and cancellation: pass;
- Ready Parser native-edit convergence: pass;
- exact storage/reload and failure/retry behavior: pass;
- targeted MoonBit check: zero errors;
- independent MoonBit/API re-review: `PASS`.

Known warnings are two pre-existing deprecated `StringView::default()` uses in
the vendored Loom submodule.

## Reuse check

Reused:

- Rabbita `Attrs::on_beforeinput`, `Attrs::on_input`, composition handlers,
  `InputEvent`, `CompositionEvent`, `Cmd`, `create_state_with_init`, and typed
  Html;
- Loom `Parser::apply_edit`, `Edit::new`, and
  `MarkdownSemanticAttachment`;
- existing `dowdiness/text_change::TextChange`;
- MoonBit `String::get_view`, `StringView`, `StringBuilder`, `Option`, and
  `Result`/enum pattern matching.

Checked but not used:

- `compute_text_change`: intentionally removed from the ordinary path;
- `String::unsafe_substring`: rejected because it does not validate
  surrogate-pair boundaries;
- `ArrayView`/`String::code_units`: unnecessary once browser UTF-16 ranges and
  `String::get_view` validate the splice boundary;
- `Buffer`: byte-oriented and not suitable for this UTF-16 String transition;
- Canopy DOM-boundary selection APIs: broader than this one-surface throwaway
  binding and owned by a different module;
- Worker, Rope, Piece Tree, revision, generation, queue, cancellation, and a
  Loom/Incr-to-Rabbita bridge: not justified by the evidence.

New responsibility boundaries:

- `internal/text_edit`: deterministic browser-fact-to-`TextChange` resolution
  and String-backed application;
- `internal/text_surface`: browser event correlation, `textLength`, explicit
  install, and explicit whole-value recovery;
- `internal/preview`: exact accepted edit adoption and Preview generation.

Remaining mutation is limited to the binding's two correlation refs and the
application-owned Preview engine. Both are imperative shells around immutable
facts and deterministic Document transitions.

## Consequences

1. Complete-source diff is not required for ordinary supported Preview edits.
2. #1367 should not be executed while this operation boundary remains viable.
3. #1351's eventual production slice can be much smaller than its older
   revision/Worker-oriented sketch: browser-owned textarea, synchronous event
   correlation, deterministic range transition, and explicit recovery first.
4. Production Split Preview remains blocked by the strict cold first-edit
   maximum, not by ordinary edit reconstruction.
5. The next investigation should attribute or redefine the cold first
   incremental Preview boundary. It must not introduce artificial warm-up,
   Worker placement, or scheduler protocols without separate evidence.
