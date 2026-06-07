# ViewNode JSON Serialization — Phase 0 Spike

Date: 2026-04-01
Context: EditorProtocol design validation (`docs/archive/completed-phases/2026-04-01-editor-protocol-design.md`)

## Question

Is JSON serialization of ViewNode trees fast enough for the EditorProtocol?
Target: < 1ms for incremental patches (typical keystroke), acceptable for full-tree on initial load.

## Setup

- `proj_to_view_node(ProjNode[Term], SourceMap) → ViewNode` conversion + `to_json().stringify()`
- Custom object-based `ToJson` (not `derive(ToJson)` array format)
- Source: `let f0 = \x.x + 0\nlet f1 = \x.x + 1\n...` (realistic lambda defs)
- `moon bench --release`

## Results

| Scale | Node count | Serialize + stringify |
|-------|-----------|----------------------|
| 100 defs | 402 | 1.32 ms |
| 200 defs | 802 | 3.24 ms |
| 500 defs | 2002 | 11.46 ms |

~3.3 µs/node, scaling linearly.

## Conclusion

**JSON transport validated for the incremental patch protocol.** Rationale:

- **Incremental patches (hot path):** A typical keystroke emits `TextChange` + 1-5 `UpdateNode`/`ReplaceNode` — a few small JSON objects, well under 0.1ms.
- **Full-tree serialization (cold path):** Only on initial load and mode switches (`FullTree` patch). 1.3ms at 100 defs is ~1 frame at 60fps — acceptable.
- **Escape hatch:** If sub-ms full trees are needed later, direct typed-FFI calls bypass JSON entirely (spec §"Optimized layer").

No need to pull the optimized FFI layer forward into Phase 1.
