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
