///|
pub fn bigram(text : String) -> Array[String] {
  let len = text.length()
  if len < 2 {
    return []
  }
  let result = Array::new(capacity=len - 1)
  for i in 0..<(len - 1) {
    result.push(text[i:i + 2].to_string())
  }
  result
}

///|
/// Blended tokenizer: combines bigram + TinySegmenter tokens.
/// Bigrams capture exact character-pair matches (technical terms like CRDT, MoonBit).
/// Word tokens capture semantic units (particles, compound words).
/// TF-IDF's IDF weighting naturally balances their contributions.
pub fn blended(text : String) -> Array[String] {
  let tokens = bigram(text)
  let words = segment(text)
  for word in words {
    tokens.push(word)
  }
  tokens
}
