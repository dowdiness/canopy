# Lambda edit bridge boundary after `ModuleProjection` removal

**Date:** 2026-06-15  
**Status:** Accepted  
**Closes:** <https://github.com/dowdiness/canopy/issues/634>  
**Related:**
[#623](https://github.com/dowdiness/canopy/issues/623) ·
[#633](https://github.com/dowdiness/canopy/issues/633) ·
[#661](https://github.com/dowdiness/canopy/issues/661) ·
[#662](https://github.com/dowdiness/canopy/issues/662) ·
[#668](https://github.com/dowdiness/canopy/pull/668)

## Decision

Keep Lambda's thin `apply_lambda_tree_edit` bridge. Do not adapt Lambda to
`LanguageSpec::apply_edit`, and do not introduce a richer generic runtime API
for Lambda alone.

After the `ModuleProjection` cleanup, the required edit context is no longer the
main blocker: Lambda's registry and `DefinitionIndex` can be derived from the
current generic `ProjNode` root. The remaining boundary is the application
contract. Lambda returns typed `TreeEditError`s plus the applied `SpanEdit` trace,
and its `Drop` operation delegates to the editor-owned `move_node` path. Those
are deliberately outside `LanguageSpec`, whose shared contract is
`compute_edit -> apply_span_edits -> Result[Unit, String]` for the JSON/Markdown
shape.

## Audit table

| Dimension | Generic SPI principle | Lambda bridge principle | Boundary decision |
|---|---|---|---|
| Context ownership | Shared bridges should depend only on language-neutral document state. | Language-specific lookup structures may be derived locally from that state. | Do not widen the SPI for derivable context alone. |
| Success and failure shape | The common path reports coarse success or string failure. | Lambda preserves structured failure categories and applied edit traces. | Keep the contracts separate unless consumers migrate deliberately. |
| Error semantics | Generic callers need stable messages, not language-owned categories. | Lambda callers rely on language-owned categories for precise UI behavior. | Preserve the richer channel for Lambda. |
| Trace obligations | The shared bridge applies edits internally and hides patch details. | Lambda must expose the applied patch trace to downstream instrumentation. | Preserve the trace requirement. |
| Move semantics | Generic edits are language-computed text patches. | Some Lambda moves are editor-coupled because validity depends on editor-owned placeholder and separator rules. | Keep editor-coupled moves out of the SPI until another language shares the need. |
| Consumer expectations | JSON and Markdown consumers observe only coarse success or failure. | Lambda consumers expect stable structured messages and patch traces. | Keep the Lambda facade stable. |

## Consequences

- `lang/runtime` remains the Tier 2 SPI for JSON/Markdown-style languages.
- Lambda remains a documented exception and a legacy stress case, not a new
  language template.
- If a future language only needs a registry or index derivable from `ProjNode`,
  derive it in that language's closure rather than widening `LanguageSpec`.
- Revisit the generic SPI only when at least one non-Lambda language needs the
  same richer shape: typed edit errors, successful patch traces, or editor-owned
  move/drop semantics. At that point, design the generic API for both languages
  together instead of creating a Lambda-only `LanguageSpecV2`.
