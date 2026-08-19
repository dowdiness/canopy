///|
test "uses the lowest then leftmost position" {
  let packer = try! Packer::Packer(width=10)
  let first = try! packer.place(Size::Size(width=6, height=4))
  let second = try! packer.place(Size::Size(width=4, height=3))
  let third = try! packer.place(Size::Size(width=7, height=2))
  debug_inspect(
    first,
    content=(
      #|{ x: 0, y: 0, width: 6, height: 4 }
    ),
  )
  debug_inspect(
    second,
    content=(
      #|{ x: 6, y: 0, width: 4, height: 3 }
    ),
  )
  debug_inspect(
    third,
    content=(
      #|{ x: 0, y: 4, width: 7, height: 2 }
    ),
  )
  debug_inspect(packer.height(), content="6")
}

///|
test "pack_in_order preserves input indices" {
  let result = try! pack_in_order(
    [
      try! Size::Size(width=6, height=4),
      try! Size::Size(width=4, height=3),
      try! Size::Size(width=7, height=2),
    ],
    bin_width=10,
  )
  debug_inspect(result.placements.length(), content="3")
  debug_inspect(
    result.placements[0],
    content=(
      #|{ x: 0, y: 0, width: 6, height: 4 }
    ),
  )
  debug_inspect(
    result.placements[1],
    content=(
      #|{ x: 6, y: 0, width: 4, height: 3 }
    ),
  )
  debug_inspect(
    result.placements[2],
    content=(
      #|{ x: 0, y: 4, width: 7, height: 2 }
    ),
  )
  debug_inspect(result.height, content="6")
}

///|
test "rejects a bin whose width is not positive" {
  let result : Result[Packer, PackError] = Ok(Packer::Packer(width=0)) catch {
    error => Err(error)
  }
  debug_inspect(result, content="Err(InvalidBinWidth(0))")
}

///|
test "rejects a non-positive max height" {
  let result : Result[Packer, PackError] = Ok(
    Packer::Packer(width=10, max_height=-1),
  ) catch {
    error => Err(error)
  }
  debug_inspect(result, content="Err(InvalidMaxHeight(-1))")
}

///|
test "rejects a non-positive size" {
  let result : Result[Size, PackError] = Ok(Size::Size(width=0, height=2)) catch {
    error => Err(error)
  }
  debug_inspect(result, content="Err(InvalidSize(0, 2))")
}

///|
test "rejects an item wider than the bin before searching" {
  let packer = try! Packer::Packer(width=10)
  let result : Result[Placement, PackError] = Ok(
    packer.place(try! Size::Size(width=11, height=1)),
  ) catch {
    error => Err(error)
  }
  debug_inspect(result, content="Err(ItemTooWide(item_width=11, bin_width=10))")
}

///|
test "raises NoPlacement when the item exceeds max_height" {
  let packer = try! Packer::Packer(width=10, max_height=5)
  let result : Result[Placement, PackError] = Ok(
    packer.place(try! Size::Size(width=3, height=6)),
  ) catch {
    error => Err(error)
  }
  debug_inspect(result, content="Err(NoPlacement(width=3, height=6))")
}

///|
test "place_constrained only uses supplied x coordinates" {
  let packer = try! Packer::Packer(width=10)
  ignore(try! packer.place(try! Size::Size(width=4, height=2)))
  let placed = try! packer.place_constrained(
    try! Size::Size(width=3, height=2),
    [0, 4],
  )
  debug_inspect(
    placed,
    content=(
      #|{ x: 4, y: 0, width: 3, height: 2 }
    ),
  )
}

///|
test "place_constrained does not insert probe points" {
  let packer = try! Packer::Packer(width=10)
  let result : Result[Placement, PackError] = Ok(
    packer.place_constrained(try! Size::Size(width=3, height=2), [3]),
  ) catch {
    error => Err(error)
  }
  debug_inspect(
    result,
    content=(
      #|Ok({ x: 3, y: 0, width: 3, height: 2 })
    ),
  )
  let packed = try! packer.place(try! Size::Size(width=3, height=2))
  debug_inspect(packed.x, content="0")
  debug_inspect(packed.y, content="0")
}

///|
test "place_constrained with no valid x raises NoPlacement" {
  let packer = try! Packer::Packer(width=10)
  let result : Result[Placement, PackError] = Ok(
    packer.place_constrained(try! Size::Size(width=3, height=2), [8, 9]),
  ) catch {
    error => Err(error)
  }
  debug_inspect(result, content="Err(NoPlacement(width=3, height=2))")
}

///|
test "merges a uniform top edge after filling a gap" {
  let packer = try! Packer::Packer(width=10)
  ignore(try! packer.place(try! Size::Size(width=6, height=4)))
  ignore(try! packer.place(try! Size::Size(width=4, height=4)))
  debug_inspect(packer.height(), content="4")
  let third = try! packer.place(try! Size::Size(width=10, height=1))
  debug_inspect(
    third,
    content=(
      #|{ x: 0, y: 4, width: 10, height: 1 }
    ),
  )
}

///|
test "same inputs produce the same placements" {
  let sizes = [
    try! Size::Size(width=5, height=2),
    try! Size::Size(width=3, height=4),
    try! Size::Size(width=7, height=1),
  ]
  let first = try! pack_in_order(sizes, bin_width=10)
  let second = try! pack_in_order(sizes, bin_width=10)
  debug_inspect(first == second, content="true")
}

///|
test "overflowing a stacked top raises CoordinateOverflow" {
  let packer = try! Packer::Packer(width=1)
  ignore(try! packer.place(try! Size::Size(width=1, height=@int.MAX_VALUE)))
  let result : Result[Placement, PackError] = Ok(
    packer.place(try! Size::Size(width=1, height=1)),
  ) catch {
    error => Err(error)
  }
  debug_inspect(result, content="Err(CoordinateOverflow)")
}
