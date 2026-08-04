///|
test "bigram - basic Japanese" {
  debug_inspect(
    bigram("カレー"),
    content=(
      #|["カレ", "レー"]
    ),
  )
}

///|
test "bigram - mixed ASCII and Japanese" {
  debug_inspect(
    bigram("CRDTの実装"),
    content=(
      #|["CR", "RD", "DT", "Tの", "の実", "実装"]
    ),
  )
}

///|
test "bigram - empty string" {
  debug_inspect(bigram(""), content="[]")
}

///|
test "bigram - single char" {
  debug_inspect(bigram("あ"), content="[]")
}

///|
test "bigram - with spaces" {
  debug_inspect(
    bigram("a b"),
    content=(
      #|["a ", " b"]
    ),
  )
}
