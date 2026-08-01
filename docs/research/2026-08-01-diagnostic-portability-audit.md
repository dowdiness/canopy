# Diagnostic portability audit (#1040)

## Decision

**NARROW.** The portable named subset is `SourceId`, `TextOffset`, `TextRange`,
`SourceSpan`, severity/source/code, labels/notes, neutral single-source fixes,
external-source plain rendering, defensive-copy value boundaries, and
source-scoped transforms. The executable boundary is
`probe/diagnostic_portability/top.mbt:4-76`: its source identity is
`standalone-source`; its provider-owned display name is `standalone.lambda`.

The full `Diagnostic` record is not token-erased: it has one optional,
parser-specific `TokenEvidence` field. That field owns `@seam.RawKind`
(`loom/loom/core/diagnostics.mbt:513-543`), so the full model is not the
portable public subset. The second failed gate is label coverage: semantic
production and generic rendering preserve both styles, but the audited parser
path and standalone probe establish only `Primary`. These two failures keep the
verdict narrow.

## Behavioral boundary matrix

| Gate / target | Direct evidence | Verdict |
| --- | --- | --- |
| Core dependency direction | `loom/loom/core/moon.pkg:1-14` imports Loom-adjacent/core packages and no `dowdiness/canopy/*`. | Core has no Canopy dependency. |
| Neutral record shape | `Diagnostic` contains source, severity, code, message, labels, notes, fixes, and optional token (`loom/loom/core/diagnostics.mbt:592-624`); it contains no `NodeId`, entity, `SyntaxNode`, scope graph, or editor view field. | The named fields are portable values; optional `TokenEvidence` is the explicit non-portable exception. |
| Generated-interface audit | Loom core's generated public interface exposes `Diagnostic` construction with `token? : TokenEvidence?` and `Diagnostic::token` (`loom/loom/core/pkg.generated.mbti:94-112`); it also publicly exposes `TokenEvidence`, whose constructor/accessor use `@seam.RawKind` (`:529-534`). | The `.mbti` confirms the parser-specific type crosses the public package seam; the whole record fails extraction. |
| Parser and semantic producers | Lambda parser constructs the named error/fix (`loom/examples/lambda/cst_parser.mbt:132-167`); semantic lowering constructs `Diagnostic` values (`lang/lambda/semantic/semantic_projection.mbt:91-144`). | Both producer classes use one model, but parser token evidence prevents whole-record extraction. |
| Label survival | Semantic production and its test preserve `Primary` and `Secondary` (`lang/lambda/semantic/semantic_projection.mbt:103-141`; `semantic_projection_test.mbt:197-231`), and the generic renderer prints both (`loom/loom/core/diagnostic_renderer_wbtest.mbt:92-130`). The audited Lambda parser diagnostic has only `Primary` (`loom/examples/lambda/cst_parser.mbt:157-165`), and the probe asserts only that output (`probe/diagnostic_portability/top.mbt:61-76`). | Failed full gate: both styles survive the semantic producer and renderer, but both producers/renderers are not established. This independently supports `NARROW`. |
| Renderer isolation | Renderer receives only `SourceProvider`; its implementation references diagnostic/source types and no parser, CST, or editor APIs (`loom/loom/core/diagnostic_renderer.mbt:19-35,295-339`). Package dependency direction is covered by `moon.pkg` above. | External-source renderer is portable. |
| Multi-source diagnostics | A renderer test resolves two source IDs and renders two source groups for one diagnostic (`loom/loom/core/diagnostic_renderer_wbtest.mbt:480-528`). | One diagnostic may span multiple sources; this probe intentionally covers one source only. |
| Source locations | `TextOffset` rejects negatives and `TextRange` rejects reversed order; their documentation defines half-open UTF-16 code-unit positions (`loom/loom/core/diagnostics.mbt:269-339`). `SourceSpan` qualifies the range by source (`:446-467`). Bounds and actual UTF-16 boundaries are checked only when rendering (`diagnostic_renderer_wbtest.mbt:251-318`) or applying a fix (`diagnostic_fixes_wbtest.mbt:231-260`). | Portable source-scoped coordinates with validation deferred until source text is available. |
| Mutable-array closure | Diagnostic construction and access copy labels, notes, and fixes (`loom/loom/core/diagnostics.mbt:620-660`); set access copies items (`:826-848`); mutation regression is `diagnostics_wbtest.mbt:692-711`. | No mutable-array escape across the value seam. |
| Neutral, non-transactional fixes | `TextReplacement` is a source span plus replacement text and `DiagnosticFix` is named normalized replacements (`loom/loom/core/diagnostic_fixes.mbt:8-92`). | No editor transaction, CRDT, undo, or command is carried by a fix. |
| Multi-file fix rejection | Constructor raises `MultiSourceDiagnosticFix` (`loom/loom/core/diagnostic_fixes.mbt:54-69`); regression asserts rejection (`loom/loom/core/diagnostic_fixes_wbtest.mbt:128-145`). | Portable candidates are single-source. |
| Deterministic application | `apply` checks source, bounds, and UTF-16 boundaries before reverse application (`loom/loom/core/diagnostic_fixes.mbt:110-139`). | Source-scoped pure transform; host mutation stays outside. |
| Source-scoped transforms | Two-source shift changes only the edited source label (`loom/loom/core/diagnostics_wbtest.mbt:512-534`); 2–4 source property coverage is `:791-839`. | Labels, rather than unrelated source evidence, drive shifts; validated by the core release test below. |
| Replay and dedup | Parser replay equality intentionally omits token evidence while retaining source/code/labels/fixes (`loom/loom/core/diagnostics.mbt:815-887`); relex tests preserve foreign-source labels (`diagnostics_wbtest.mbt:562-620`). | Remains Loom parser lifecycle machinery, not extracted API. |
| Public parser seam and standalone probe | `@lambda.parse_cst` returns `DiagnosticSet` (`loom/examples/lambda/pkg.generated.mbti:50`); the probe selects exact code, renders, applies, and reparses (`probe/diagnostic_portability/top.mbt:4-76`). | Probe proves the narrow consumer path without CST/seam/editor imports. |
| Probe result | `moon test --release probe/diagnostic_portability` passed: 1/1. The exact expected rendering, fixed text, and absent code are asserted at `probe/diagnostic_portability/top.mbt:61-76`. | Concrete evidence for `if x then y`. |
| Host revision/fix registry | `ViewUpdateState` owns snapshot ID, source ID, `@text.Version`, and registered Loom fixes (`editor/view_updater.mbt:36-57,190-270`); stale-version tests reject (`editor/diagnostic_fix_wbtest.mbt:93-150`). | Host-only publication lifetime and fix registry; not portable diagnostic data. |
| Protocol DTO separation | Protocol diagnostic exposes offsets, message, IDs, and summaries (`protocol/view_patch.mbt:70-104`); inbound intent carries opaque IDs only (`protocol/user_intent.mbt:11-25`). | DTO is host protocol, not the Loom model. |
| Async/project safety | No ticket, cancellation, dependency, configuration, or generation state appears in this probe. | #1089 owns those host-side concerns; this audit proves none of them. |

## Ownership and reconsideration

Loom owns validation, rendering, token evidence, parser replay, and dedup.
Lambda owns grammar-specific production and acceptance. Canopy owns editor/CRDT
mutation, undo, revision-bound publication, registry lifetime, and protocol
mapping. Reconsider widening only for a second independent consumer, a
multi-source/project snapshot contract, a source-provider lifetime interface,
or token evidence that must cross the seam without `@seam`.

## Validation

Ran `moon check --deny-warn probe/diagnostic_portability`,
`moon test --release probe/diagnostic_portability`, scoped `moon fmt` and
`moon info` for that package, plus `git diff --check`; all passed. The
source-transform property also passed in `moon test --release loom/loom/core`:
379/379 tests.
