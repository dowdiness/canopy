# Loomark Split Preview prototype evidence

**Issue:** [#1156](https://github.com/dowdiness/canopy/issues/1156)

**Decision:** `NO-GO`

**Measured prototype commit:** `4734c57f363cdc189e568fb546c260f492509a81`

**Baseline commit:** `f2e3e98a55b02d58b635ebed175262fe760d4699`

The prototype validates a simple one-authority architecture, but the complete-source text-diff stage alone exceeds the 10 ms CPU budget at the provisional practical corpus. The investigation stops before any Loom, Markdown, Incr, Rabbita, or text-change foundation edit.

## Behavioral boundary matrix

| Boundary | Text | Preview | Split |
|---|---|---|---|
| Editable authority | One Document text textarea | None | The same Document text textarea only |
| First result absent | Text remains usable | `Preparing preview…` | Text remains usable beside `Preparing preview…` |
| Matching result | Not presented | Present matching read-only result | Present matching result beside textarea |
| Replacement running | Text remains immediate | Last completed result remains | Last completed result remains |
| Generation failure | Document text remains valid | Layout and last result remain; status is outside content | Layout and last result remain; status is outside content |
| IME composition | Document text follows the existing textarea contract | No preparation begins during composition | No preparation begins during composition |
| Autosave | Existing 250 ms quiet policy | Independent of Preview | Independent of Preview |
| Returning to Text | No automatic focus or selection restoration | — | No automatic focus or selection restoration |

| Markdown form | Preview behavior |
|---|---|
| Heading, paragraph, emphasis, strong, code, list, quote, break | Typed semantic HTML |
| Link and autolink | Visible label/display and destination text; no `href` |
| Image | Visible alternative and destination text; no `img` or `src` |
| Raw or inline HTML | Source displayed as text; never interpreted |
| Unsupported, raw, or recovered node | Remains visibly represented |
| Markdown diagnostic | Not Preview content |

## Prototype architecture

The prototype uses standard Rabbita `Model / Msg / update / view` with `create_state_with_init`.

- Document text remains the only editable authority.
- The Rabbita Model contains immutable layout, Preview result, preparation, and failure values. It contains no Parser, Runtime, Scope, Watch, callback, or Cmd.
- One application-lifetime `PreviewEngine` is captured by the app shell and created without initializing a Parser.
- The first Preview intent schedules a zero-delay managed command. The command initializes one Parser and one `MarkdownSemanticAttachment` after the browser input task returns.
- Later source changes use `dowdiness/text_change::compute_text_change`, `Parser::apply_edit`, one semantic read, and exhaustive typed Rabbita Html materialization.
- One active preparation converges through current Document text. No queue, revision, generation, acknowledgement, cancellation, Worker, or public patch protocol is introduced.
- A Parser edit failure marks the engine broken rather than guessing whether a partially advanced Parser remains reusable.
- Link, image, autolink, raw HTML, inline HTML, unsupported, and recovered forms remain inert and visible.

The initial Warren production E2E tracer failed before implementation because no Preview control existed. It then passed through the production page after the smallest vertical slice. The final targeted production suite passes 10/10 tests.

## Test seams

1. The standalone Warren production page is the primary behavioral seam.
2. User Timing entries observe preparation and after-render completion. They do not mutate application state.
3. The JS release white-box benchmark isolates `compute_text_change` at the deployment target.
4. External Chrome tracing would be used only if the pre-presentation phases met the budget and the remaining Rabbita/VDOM/DOM cost required attribution. That condition was not reached.

## Environment

- Moon: `0.1.20260819 (fc2a4ee 2026-08-19)`
- Moon compiler: `v0.10.9+6e6c44045 (2026-08-19)`
- Node.js: `v24.14.1`
- Pinned Playwright Chromium: `149.0.7827.55`
- Target: JavaScript release
- Fixture: 250 units, 22,419 UTF-16 code units, 1,000 lines, approximately 500 Markdown blocks

## Integrated browser characterization

Command, with the Warren production output already served:

```text
LOOMARK_STANDALONE_URL=http://127.0.0.1:4318 npm run measure:preview
```

The runner performed five measured repetitions for every combination of operation (`insert`, `delete`, `replace`) and position (`beginning`, `middle`, `end`), for 45 samples total. Every measured transition followed a completed unmeasured setup transition and verified that visible Preview content converged.

Raw samples: [`2026-08-25-loomark-split-preview-browser-samples.json`](2026-08-25-loomark-split-preview-browser-samples.json)

| Phase | Median | p95 | Maximum |
|---|---:|---:|---:|
| Complete-source diff | 23.6 ms | 27.8 ms | 34.5 ms |
| Incremental Parser update | 0.8 ms | 1.9 ms | 4.6 ms |
| Semantic attachment read | 2.2 ms | 4.0 ms | 6.1 ms |
| Typed Html materialization | 0.7 ms | 2.0 ms | 2.7 ms |
| Preparation sum | 27.7 ms | 35.0 ms | 43.7 ms |
| After-render wall time | 37.4 ms | 47.2 ms | 48.0 ms |

`loomark-preview-total` is wall time through Rabbita's after-render command and includes frame-scheduling wait. It is reported but is not treated as CPU time. The preparation sum excludes Rabbita propagation, VNode construction, VDOM diff, DOM patch, layout, and paint. It already exceeds the complete 10 ms budget, so the decision does not depend on the after-render measure.

Removing the first sample as warm-up would not change the decision: all 45 complete-source diff samples exceeded 10 ms.

## Isolated deployment-target benchmark

Command:

```text
cd apps/loomark
NEW_MOON_MOD=0 moon bench --release --target js internal/preview
```

The benchmark varies ten operands per scenario rather than repeatedly diffing one hot operand.

| Operation | Beginning | Middle | End |
|---|---:|---:|---:|
| Insert | 21.57 ms | 22.34 ms | 24.92 ms |
| Delete | 22.64 ms | 20.76 ms | 24.09 ms |
| Replace | 21.57 ms | 21.08 ms | 20.39 ms |

Values are benchmark means. Observed benchmark ranges were 19.87–29.86 ms. All nine scenarios exceed the entire product budget before parsing or presentation begins.

## Existing mitigation check

`dowdiness/text_change::compute_text_change` computes grapheme boundaries for both strings during the prefix scan and computes both arrays again during the suffix scan. Its cluster comparison also materializes owning strings. The measured cost is nearly position-invariant because all localized operations scan the practical corpus.

Canopy already contains `fast_append_text_change`, and its existing JS release benchmark measures approximately 54.46 µs for a 250-block append versus 17.29 ms through the shared general diff. That mitigation applies only to strict append. It does not cover the beginning/middle/end insert/delete/replace matrix and therefore cannot change this decision.

Relevant existing APIs checked before any child design:

- `dowdiness/text_change::compute_text_change`
- Canopy's private `fast_append_text_change`
- `String` / `StringView` UTF-16 views and code-unit access
- `dowdiness/moji::grapheme_boundaries`
- `Parser::apply_edit`
- the operation-based Text Authority direction tracked by #1351

No optimization was prototyped because #1156 authorizes identification and a child specification, not a foundation correction.

## Decision

`NO-GO`: the architecture is behaviorally viable, but the provisional practical corpus cannot meet the 10 ms CPU contract while every Preview update first reconstructs a grapheme-safe Edit from two complete Strings through the current general text-change function.

The narrowest reproduced owner is the `dowdiness/text_change` leaf module in the Loom repository. A separate child specification must compare a bounded correction in that owner against bypassing complete-source diff through the future operation-based Text Authority. It must retain non-BMP and combining-mark correctness, use a deployment-target microbenchmark, and return to the integrated #1156 path only after the isolated stage has enough budget for Parser, semantic, typed Html, and presentation work.

The prototype does not authorize production Preview rollout.
