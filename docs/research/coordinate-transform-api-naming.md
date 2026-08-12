# Coordinate-Transform API Naming Research

This note compares naming used by established first-party coordinate and gesture APIs with Canopy's `spatial` interface.

## Primary sources

- [D3 zoom](https://d3js.org/d3-zoom)
- [D3 drag](https://d3js.org/d3-drag)
- [D3 linear scales](https://d3js.org/d3-scale/linear)
- [MDN: `DOMMatrixReadOnly.transformPoint`](https://developer.mozilla.org/en-US/docs/Web/API/DOMMatrixReadOnly/transformPoint)
- [Mapbox GL JS `Map`](https://docs.mapbox.com/mapbox-gl-js/api/map/)
- [React Flow `ReactFlowInstance`](https://reactflow.dev/api-reference/types/react-flow-instance)

## Observed conventions

| Library | Forward operation | Reverse operation | State/update operation |
|---|---|---|---|
| D3 zoom | `transform.apply(point)` | `transform.invert(point)` | `transform.translate(x, y)`, `transform.scale(k)` |
| D3 scale | callable `scale(value)` | `scale.invert(value)` | `domain(...)`, `range(...)` |
| DOMMatrix | `transformPoint(point)` | `inverse()` followed by `transformPoint` | `translate(...)`, `scale(...)` |
| Mapbox GL JS | `map.project(lngLat)` | `map.unproject(point)` | map state methods, not a bare `to` operation |
| React Flow | `flowToScreenPosition(position)` | `screenToFlowPosition(position)` | direction is encoded in the method name |
| D3 drag | current `event.x` / `event.y` | — | a gesture `subject` is fixed at start; events report current state |

The recurring choices are verbs (`apply`, `project`, `transformPoint`), explicit
coordinate directions (`screenToFlowPosition`), and paired reverse names
(`invert`, `unproject`). A bare `to` is not the dominant convention for a pure
coordinate calculation. In MoonBit, expected invalid input is represented by a
concrete `raise` error at the same operation boundary rather than by a parallel
`try_*` API that discards the failure reason.

## Implications for Canopy

- `Viewport::world_to_screen` and `Viewport::screen_to_world` follow the most
  explicit convention: both coordinate spaces are named.
- `Viewport::with_scale_around` describes the anchor-preserving operation more
  directly than `with_scale_to`; the latter would suggest a target state rather
  than an anchor point. Its `raise ViewportTransformError` signature makes
  invalid anchors, scales, and derived origins explicit.
- `Drag::positions_at(pointer)` makes the result explicit: it evaluates the
  snapshot and returns item positions at the supplied pointer position.
- `Drag::start` and `Drag::positions_at(pointer)` keep the gesture snapshot and
  its evaluation together, so callers do not need a generic callback adapter.
- Semantic constructors such as `Pan::start`, `Drag::start`, `ScreenPoint::from_xy`,
  and `Viewport::validated` communicate construction intent better than
  same-type constructor names while avoiding deprecated `::new`.

## Recommendation

Use explicit result nouns for gesture evaluation (`viewport_at` and
`positions_at`), directional names for coordinate conversion, semantic
constructors for snapshots/value objects, and concrete `raise` errors for
recoverable invalid input. These are now the names used by the `spatial`
interface.
