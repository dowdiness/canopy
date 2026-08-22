# Canvas Spatial

Pure spatial and gesture geometry for MoonBit canvases.

This module owns:

- finite `ScreenPoint` and `WorldPoint` values
- positive finite `Scale` values
- screen/world `Viewport` transforms and anchor-preserving zoom
- snapshot-based `Pan` and `Drag[Id]` geometry
- `ItemPosition[Id]` and typed geometry errors

The kernel is deterministic and has no dependency on Canopy graph models,
layout, Rabbita, browser or DOM APIs, JSON, pointer IDs, wheel policy,
selection, rendering, undo, or collaboration.

Consumers should import `dowdiness/canvas-spatial` directly.
