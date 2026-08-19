///|
fn skyline_pairs(packer : Packer) -> Array[(Int, Int)] {
  packer.skyline.map(node => (node.x, node.y))
}

///|
fn assert_skyline_invariants(packer : Packer) -> Unit raise {
  let nodes = packer.skyline
  guard nodes.length() >= 2 else {
    fail("skyline must keep a start and sentinel")
  }
  @debug.assert_eq(nodes[0].x, 0)
  let sentinel = nodes[nodes.length() - 1]
  @debug.assert_eq(sentinel.x, packer.width)
  @debug.assert_eq(sentinel.y, 0)
  for window in nodes.windows(2) {
    guard window[1].x > window[0].x else {
      fail("skyline x coordinates must be strictly increasing")
    }
  }
  for i in 0..<(nodes.length() - 2) {
    guard nodes[i].y != nodes[i + 1].y else {
      fail("adjacent non-sentinel nodes must not share a height")
    }
  }
}

///|
fn placements_in_bin(
  placements : ArrayView[Placement],
  bin_width : Int,
) -> Bool {
  placements
  .iter()
  .all(placement => {
    placement.x >= 0 && placement.x <= bin_width - placement.width
  })
}

///|
fn placements_overlap(a : Placement, b : Placement) -> Bool {
  a.x < b.x + b.width &&
  b.x < a.x + a.width &&
  a.y < b.y + b.height &&
  b.y < a.y + a.height
}

///|
fn any_interior_overlap(placements : ArrayView[Placement]) -> Bool {
  for i in 0..<placements.length() {
    for j in (i + 1)..<placements.length() {
      if placements_overlap(placements[i], placements[j]) {
        return true
      }
    }
  }
  false
}

///|
fn covering_top(
  placements : ArrayView[Placement],
  left : Int,
  right : Int,
) -> Int {
  placements.fold(init=0, (acc, placement) => {
    if placement.x < right && left < placement.x + placement.width {
      acc.max(placement.y + placement.height)
    } else {
      acc
    }
  })
}

///|
fn skyline_matches_placements(
  packer : Packer,
  placements : ArrayView[Placement],
) -> Bool {
  packer.skyline
  .windows(2)
  .iter()
  .all(window => {
    let left = window[0].x
    let right = window[1].x
    window[0].y == covering_top(placements, left, right)
  })
}

///|
test "empty packer starts with a flat skyline" {
  let packer = Packer(width=10)
  assert_skyline_invariants(packer)
  debug_inspect(skyline_pairs(packer), content="[(0, 0), (10, 0)]")
}

///|
test "placing the article's 7-wide rectangle sits on the covered max" {
  let packer = Packer(width=10)
  ignore(packer.place(Size(width=6, height=4)))
  assert_skyline_invariants(packer)
  debug_inspect(skyline_pairs(packer), content="[(0, 4), (6, 0), (10, 0)]")
  let placed = packer.place(Size(width=7, height=2))
  debug_inspect(
    placed,
    content=(
      #|{ x: 0, y: 4, width: 7, height: 2 }
    ),
  )
  assert_skyline_invariants(packer)
  debug_inspect(skyline_pairs(packer), content="[(0, 6), (7, 0), (10, 0)]")
}

///|
test "right-edge placement does not duplicate the sentinel x" {
  let packer = Packer(width=10)
  ignore(packer.place(Size(width=6, height=4)))
  ignore(packer.place(Size(width=4, height=3)))
  assert_skyline_invariants(packer)
  debug_inspect(skyline_pairs(packer), content="[(0, 4), (6, 3), (10, 0)]")
}

///|
test "constrained probing leaves the skyline unchanged on failure" {
  let packer = Packer(width=10)
  ignore(packer.place(Size(width=6, height=4)))
  let before = skyline_pairs(packer)
  let result : Result[Placement, PackError] = Ok(
    packer.place_constrained(Size(width=5, height=1), [6]),
  ) catch {
    error => Err(error)
  }
  debug_inspect(result, content="Err(NoPlacement(width=5, height=1))")
  debug_inspect(skyline_pairs(packer) == before, content="true")
}
