# canvas-layout

Layout policies for Canopy canvas graphs. Each policy computes positions and
returns a `LayoutPlan`. Applying the plan is the caller's job: lower it to
`WorkflowAction::MoveNodes` and reuse the existing graph operation log.

`canvas-graph` does not depend on this module. Skyline packing stays a generic
integer algorithm in `dowdiness/skyline`; this adapter owns quantization from
world-space `Double` coordinates.

## Skyline

`dowdiness/canvas-layout/skyline` packs selected `CanvasNode` sizes into a
fixed-width strip and returns node positions. Use it for explicit arrange
actions, not for free-form collision search.
