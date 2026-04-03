///|
struct TermFreq {
  counts : Map[String, Int]
  total : Int
}

///|
fn term_freq(tokens : Array[String]) -> TermFreq {
  let counts : Map[String, Int] = Map::new()
  for token in tokens {
    let n = match counts.get(token) {
      Some(n) => n
      None => 0
    }
    counts[token] = n + 1
  }
  { counts, total: tokens.length() }
}
