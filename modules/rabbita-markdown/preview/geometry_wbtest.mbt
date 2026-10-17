///|
test "source ranges survive the Preview content attribute" {
  let ranges = [{ start: 0, end: 7, }, { start: 8, end: 20, }]
  let encoded = encode_source_ranges(ranges)
  assert_eq(encoded, "0:7 8:20")
  assert_true(decode_source_ranges(encoded) == Some(ranges))
  assert_true(decode_source_ranges("0:7 8") is None)
}

///|
test "block position follows an offset through and between blocks" {
  // "Alpha.\n\n- one\n- two\n\nGamma.\n"
  let ranges = [
    { start: 0, end: 7, },
    { start: 8, end: 20, },
    { start: 21, end: 28, },
  ]
  assert_eq(block_position(ranges, 0), (0, 0.0))
  assert_eq(block_position(ranges, 14), (1, 0.5))
  // A blank line belongs to the end of the block above it.
  assert_eq(block_position(ranges, 20), (1, 1.0))
  assert_eq(block_position(ranges, 21), (2, 0.0))
  assert_eq(block_position(ranges, 40), (2, 1.0))
  // Leading blank lines precede the first block.
  assert_eq(block_position([{ start: 2, end: 6, }], 0), (0, 0.0))
}

///|
test "block offset inverts block position inside a block" {
  let ranges = [{ start: 0, end: 4, }, { start: 4, end: 24, }]
  assert_eq(block_offset(ranges[1], 0.5), 14)
  assert_eq(block_position(ranges, block_offset(ranges[1], 0.5)), (1, 0.5))
  // A block ending where the next starts must not hand off to the next one.
  assert_eq(block_offset(ranges[0], 0.99), 3)
  assert_eq(block_position(ranges, block_offset(ranges[0], 0.99)), (0, 0.75))
}
