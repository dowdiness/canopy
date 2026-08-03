///|
/// Classifies a character into one of 7 types for TinySegmenter.
/// M (kanji numerals) is matched before H (general kanji) because
/// their Unicode ranges overlap — the match order is load-bearing.
fn char_type(c : Char) -> String {
  match c {
    '一'
    | '二'
    | '三'
    | '四'
    | '五'
    | '六'
    | '七'
    | '八'
    | '九'
    | '十'
    | '百'
    | '千'
    | '万'
    | '億'
    | '兆' => "M"
    '一'..='龠' | '々' | '〆' | 'ヵ' | 'ヶ' => "H"
    'ぁ'..='ん' => "I"
    'ァ'..='ヴ' | 'ー' | 'ｱ'..='ﾝ' | 'ﾞ' | 'ｰ' => "K"
    'a'..='z' | 'A'..='Z' | 'ａ'..='ｚ' | 'Ａ'..='Ｚ' => "A"
    '0'..='9' | '０'..='９' => "N"
    _ => "O"
  }
}

///|
/// Looks up a feature weight, returning 0 for missing keys.
fn lookup(key : String) -> Int {
  weights.get(key).unwrap_or(0)
}

///|
/// Computes the boundary score at position i using 42 feature lookups.
/// p1/p2/p3 are previous boundary decisions: "U" (unknown), "B" (boundary), "O" (no boundary).
fn score_boundary(
  chars : Array[String],
  types : Array[String],
  i : Int,
  p1 : String,
  p2 : String,
  p3 : String,
) -> Int {
  let w1 = chars[i - 3]
  let w2 = chars[i - 2]
  let w3 = chars[i - 1]
  let w4 = chars[i]
  let w5 = chars[i + 1]
  let w6 = chars[i + 2]
  let c1 = types[i - 3]
  let c2 = types[i - 2]
  let c3 = types[i - 1]
  let c4 = types[i]
  let c5 = types[i + 1]
  let c6 = types[i + 2]
  let mut score = lookup("BIAS")
  // Previous-decision features
  score += lookup("UP1:" + p1)
  score += lookup("UP2:" + p2)
  score += lookup("UP3:" + p3)
  score += lookup("BP1:" + p1 + p2)
  score += lookup("BP2:" + p2 + p3)
  // Unigram word features
  score += lookup("UW1:" + w1)
  score += lookup("UW2:" + w2)
  score += lookup("UW3:" + w3)
  score += lookup("UW4:" + w4)
  score += lookup("UW5:" + w5)
  score += lookup("UW6:" + w6)
  // Bigram word features
  score += lookup("BW1:" + w2 + w3)
  score += lookup("BW2:" + w3 + w4)
  score += lookup("BW3:" + w4 + w5)
  // Trigram word features
  score += lookup("TW1:" + w1 + w2 + w3)
  score += lookup("TW2:" + w2 + w3 + w4)
  score += lookup("TW3:" + w3 + w4 + w5)
  score += lookup("TW4:" + w4 + w5 + w6)
  // Unigram type features
  score += lookup("UC1:" + c1)
  score += lookup("UC2:" + c2)
  score += lookup("UC3:" + c3)
  score += lookup("UC4:" + c4)
  score += lookup("UC5:" + c5)
  score += lookup("UC6:" + c6)
  // Bigram type features
  score += lookup("BC1:" + c2 + c3)
  score += lookup("BC2:" + c3 + c4)
  score += lookup("BC3:" + c4 + c5)
  // Trigram type features
  score += lookup("TC1:" + c1 + c2 + c3)
  score += lookup("TC2:" + c2 + c3 + c4)
  score += lookup("TC3:" + c3 + c4 + c5)
  score += lookup("TC4:" + c4 + c5 + c6)
  // Conditional features (previous decision + character types)
  score += lookup("UQ1:" + p1 + c1)
  score += lookup("UQ2:" + p2 + c2)
  score += lookup("UQ3:" + p3 + c3)
  score += lookup("BQ1:" + p2 + c2 + c3)
  score += lookup("BQ2:" + p2 + c3 + c4)
  score += lookup("BQ3:" + p3 + c2 + c3)
  score += lookup("BQ4:" + p3 + c3 + c4)
  score += lookup("TQ1:" + p2 + c1 + c2 + c3)
  score += lookup("TQ2:" + p2 + c2 + c3 + c4)
  score += lookup("TQ3:" + p3 + c1 + c2 + c3)
  score += lookup("TQ4:" + p3 + c2 + c3 + c4)
  score
}

///|
/// TinySegmenter: dictionary-free Japanese word segmenter.
/// Linear classifier at each character boundary using pre-trained weights.
pub fn segment(text : String) -> Array[String] {
  if text.length() == 0 {
    return []
  }
  // Pad with boundary markers
  let chars : Array[String] = ["B3", "B2", "B1"]
  let types : Array[String] = ["O", "O", "O"]
  for ch in text {
    chars.push(ch.to_string())
    types.push(char_type(ch))
  }
  chars.push("E1")
  chars.push("E2")
  chars.push("E3")
  types.push("O")
  types.push("O")
  types.push("O")
  // Segment
  let result : Array[String] = []
  let mut word = chars[3]
  let mut p1 = "U"
  let mut p2 = "U"
  let mut p3 = "U"
  for i in 4..<(chars.length() - 3) {
    let score = score_boundary(chars, types, i, p1, p2, p3)
    if score > 0 {
      result.push(word)
      word = ""
    }
    word = word + chars[i]
    p1 = p2
    p2 = p3
    p3 = if score > 0 { "B" } else { "O" }
  }
  result.push(word)
  result
}
