// Local parse_json_string — process JSON string escapes from raw token text.
// Ported from loom/examples/json/src/value_convert.mbt because @json no longer
// exports parse_json_string.

///|
/// Parse JSON string escapes from raw token text (includes quotes).
fn parse_json_string(raw : String) -> String {
  // Strip surrounding quotes only when both delimiters are actual double quotes
  if raw.length() < 2 ||
    raw.code_unit_at(0).to_int() != 0x22 ||
    raw.code_unit_at(raw.length() - 1).to_int() != 0x22 {
    return raw
  }
  let inner = raw[1:raw.length() - 1]
  // Process escape sequences
  let buf = StringBuilder::new()
  let len = inner.length()
  let mut i = 0
  while i < len {
    let code = inner.code_unit_at(i).to_int()
    match code.to_char() {
      Some('\\') =>
        if i + 1 < len {
          let next_code = inner.code_unit_at(i + 1).to_int()
          match next_code.to_char() {
            Some('"') => {
              buf.write_char('"')
              i = i + 2
            }
            Some('\\') => {
              buf.write_char('\\')
              i = i + 2
            }
            Some('/') => {
              buf.write_char('/')
              i = i + 2
            }
            Some('b') => {
              buf.write_char('\u0008')
              i = i + 2
            }
            Some('f') => {
              buf.write_char('\u000C')
              i = i + 2
            }
            Some('n') => {
              buf.write_char('\n')
              i = i + 2
            }
            Some('r') => {
              buf.write_char('\r')
              i = i + 2
            }
            Some('t') => {
              buf.write_char('\t')
              i = i + 2
            }
            Some('u') =>
              // \uXXXX — parse 4 hex digits
              if i + 5 < len {
                let hex = inner[i + 2:i + 6].to_string()
                let cp = @string.parse_int(hex, base=16) catch {
                  _ => {
                    buf.write_char('\\')
                    i = i + 1
                    continue
                  }
                }
                if cp >= 0xD800 && cp <= 0xDBFF {
                  // High surrogate — look for low surrogate \uXXXX
                  if i + 11 < len && inner[i + 6:i + 8].to_string() == "\\u" {
                    let low_hex = inner[i + 8:i + 12].to_string()
                    let low = @string.parse_int(low_hex, base=16) catch {
                      _ => -1
                    }
                    if low >= 0xDC00 && low <= 0xDFFF {
                      let codepoint = (cp - 0xD800) * 1024 +
                        (low - 0xDC00) +
                        0x10000
                      match codepoint.to_char() {
                        Some(ch) => buf.write_char(ch)
                        None => buf.write_char('\uFFFD')
                      }
                      i = i + 12 // consumed both \uXXXX\uXXXX
                    } else {
                      buf.write_char('\uFFFD') // invalid low surrogate
                      i = i + 6
                    }
                  } else {
                    buf.write_char('\uFFFD') // lone high surrogate
                    i = i + 6
                  }
                } else if cp >= 0xDC00 && cp <= 0xDFFF {
                  buf.write_char('\uFFFD') // lone low surrogate
                  i = i + 6
                } else {
                  match cp.to_char() {
                    Some(ch) => buf.write_char(ch)
                    None => buf.write_char('\uFFFD')
                  }
                  i = i + 6
                }
              } else {
                buf.write_char('\\')
                i = i + 1
              }
            _ => {
              buf.write_char('\\')
              i = i + 1
            }
          }
        } else {
          buf.write_char('\\')
          i = i + 1
        }
      Some(c) => {
        buf.write_char(c)
        i = i + 1
      }
      None =>
        // Could be a UTF-16 surrogate pair (non-BMP character)
        if code >= 0xD800 && code <= 0xDBFF && i + 1 < len {
          // High surrogate — read low surrogate
          let low = inner.code_unit_at(i + 1).to_int()
          if low >= 0xDC00 && low <= 0xDFFF {
            let codepoint = (code - 0xD800) * 1024 + (low - 0xDC00) + 0x10000
            match codepoint.to_char() {
              Some(ch) => buf.write_char(ch)
              None => buf.write_char('\uFFFD')
            }
            i = i + 2
          } else {
            buf.write_char('\uFFFD')
            i = i + 1
          }
        } else {
          buf.write_char('\uFFFD')
          i = i + 1
        }
    }
  }
  buf.to_string()
}
