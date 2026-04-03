///|
test "bigram - basic Japanese" {
  inspect(
    bigram("カレー"),
    content=(
      #|["カレ", "レー"]
    ),
  )
}

///|
test "bigram - mixed ASCII and Japanese" {
  inspect(
    bigram("CRDTの実装"),
    content=(
      #|["CR", "RD", "DT", "Tの", "の実", "実装"]
    ),
  )
}

///|
test "bigram - empty string" {
  inspect(bigram(""), content="[]")
}

///|
test "bigram - single char" {
  inspect(bigram("あ"), content="[]")
}

///|
test "bigram - with spaces" {
  inspect(
    bigram("a b"),
    content=(
      #|["a ", " b"]
    ),
  )
}
