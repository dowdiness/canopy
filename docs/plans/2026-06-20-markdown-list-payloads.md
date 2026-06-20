# Replace Markdown ordered-list SourceMap side channel with explicit list payloads

## Context

PR #720 updated Loom and restored ordered-list behavior in Canopy's Markdown editor. The current Loom Markdown `Block` API still folds ordered and unordered list containers into the same list payload, so Canopy temporarily preserves orderedness by recording `ORDERED_LIST_KIND_ROLE` in the Markdown projection `SourceMap` and refining `ViewNode.kind_tag` during Markdown-specific view conversion.

That bridge is intentionally temporary. `SourceMap` token spans are good for source ranges and token locations, but ordered-vs-unordered list kind is semantic AST data. Once Loom's Markdown AST exposes list kind directly, Canopy should stop using a SourceMap side channel for this fact.

## Goal

Represent Markdown list kind explicitly in the Loom Markdown AST/projection payload, then migrate Canopy to read orderedness from the projected node kind/payload rather than from `SourceMap` token metadata.

## Non-goals

- Do not add ordered-list fields to the generic `protocol.ViewNode` wire shape.
- Do not remove token spans used for source ranges, editable text spans, or marker/source display.
- Do not change Markdown edit semantics beyond removing the ordered-list-kind side channel.

## Implementation outline

1. **Loom Markdown API**
   - Add an explicit ordered/unordered distinction to the Markdown block representation, e.g. separate `OrderedList` / `UnorderedList` payloads or a list-kind field.
   - Update Loom Markdown conversion and generated interfaces.

2. **Canopy projection**
   - Update `lang/markdown/proj/proj_node.mbt` to project the explicit ordered-list payload directly.
   - Remove `ORDERED_LIST_KIND_ROLE` from `lang/markdown/proj/populate_token_spans.mbt`.
   - Remove `markdown_view_kind_tag`'s SourceMap side-channel lookup; `proj_to_view_node` may still refine Markdown-specific view details if needed, but not list orderedness.

3. **Canopy editor/FFI paths**
   - Keep `LanguageCapabilities::with_to_view_node` wiring for Markdown if Markdown still needs language-specific ViewNode conversion.
   - Keep BlockInput source-marker display for start numbers and `)` delimiters until list payloads carry enough marker style/start data to replace it.

4. **Tests**
   - Keep PR #720 regressions for projection, FFI, generic editor view patches, preview rendering, block-mode display, and split behavior.
   - Add/adjust a regression proving orderedness comes from the explicit payload, not a `SourceMap` role.

## Exit condition

`ORDERED_LIST_KIND_ROLE` no longer exists; ordered-list rendering and split regressions still pass; and Canopy's Markdown projection/view code obtains orderedness from Loom's explicit Markdown list payload.
