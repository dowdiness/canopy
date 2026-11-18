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
- Side-effect-free `preview` of a placement and the area it would trap

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

## Previewing a placement

The skyline forgets empty space once a rectangle covers it from above.
`preview` shows where `place` would put a rectangle and how much area it would
trap that way, without changing the packer. Use it to choose between
alternative sizes before placing one, for example to fall back to a narrower
card when the wide one would leave a gap:

```moonbit
let packer = Packer(width=10)
ignore(packer.place(Size(width=4, height=5)))
let wide = packer.preview(Size(width=10, height=1))
inspect(wide.map(p => (p.y, p.trapped_area)), content="Some((5, 30))")
```

Pass `allowed_x` to preview `place_constrained`.

## Coordinates

MoonBit `Int` is 32-bit. `place` raises `CoordinateOverflow` when a chosen
top edge is not representable. Callers that need fractional canvas units should
quantize before packing; do not put `Double` into this core.
