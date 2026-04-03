///|
priv struct TermFreq {
  counts : Map[String, Int]
  total : Int
}

///|
fn term_freq(tokens : Array[String]) -> TermFreq {
  let counts : Map[String, Int] = Map::new()
  for token in tokens {
    counts[token] = counts.get(token).unwrap_or(0) + 1
  }
  { counts, total: tokens.length() }
}
