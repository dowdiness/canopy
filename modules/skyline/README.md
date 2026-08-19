# skyline

Deterministic Bottom-Left skyline packing for a fixed-width strip. The package
owns only rectangle sizes, placements, and the used height. Item identity,
images, and DOM stay with the caller.

This is a packing primitive, not a canvas layout engine. Canopy's canvas adapter
lives in `modules/canvas-layout/skyline` and lowers `Placement` to
`MoveNodes`.

## Install

Workspace member: `./modules/skyline` in the root `moon.work`.

```
moon add dowdiness/skyline
```

## Scope

- Fixed width, unlimited height, or an optional maximum height
- No rotation
- Input order is kept
- Bottom-Left heuristic
- Non-negative `Int` coordinates
- Optional explicit X candidates via `place_constrained`

## Skyline invariants

1. The first point is `(0, y)`.
2. The last point is the sentinel `(bin_width, 0)`.
3. X coordinates are strictly increasing.
4. Adjacent non-sentinel segments with the same height are merged.
5. Point `(xᵢ, yᵢ)` is the height of `[xᵢ, xᵢ₊₁)`.

## Quick start

```moonbit
let packer = Packer(width=10)
let first = packer.place(Size(width=6, height=4))
let second = packer.place(Size(width=4, height=3))
let third = packer.place(Size(width=7, height=2))
inspect((first.x, first.y), content="(0, 0)")
inspect((second.x, second.y), content="(6, 0)")
inspect((third.x, third.y), content="(0, 4)")
```

`pack_in_order` is the batch form that preserves input indices. Lookahead
reordering is intentionally not part of `place`.

## Coordinates

MoonBit `Int` is 32-bit. `place` raises `CoordinateOverflow` when a chosen
top edge is not representable. Callers that need fractional canvas units should
quantize before packing; do not put `Double` into this core.
