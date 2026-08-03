///|
/// Build a detached snapshot of SpanEdits suitable for logging, with
/// codepoint-bounded truncation of `inserted` text. The full text is
/// still applied to the CRDT; only the log copy is truncated.
///
/// Truncation iterates codepoints (not UTF-16 code units) so a surrogate
/// pair mid-slice cannot abort. When truncation occurs, appends '…'.
pub fn snapshot_span_edits(
  edits : Array[@core.SpanEdit],
  max_chars : Int,
) -> Array[@core.SpanEdit] {
  edits.map(fn(e) {
    let inserted = if e.inserted.length() > max_chars {
      let buf = StringBuilder::new(size_hint=max_chars)
      let mut count = 0
      for ch in e.inserted {
        if count >= max_chars {
          break
        }
        buf.write_char(ch)
        count = count + 1
      }
      buf.write_char('…')
      buf.to_string()
    } else {
      e.inserted
    }
    { start: e.start, delete_len: e.delete_len, inserted }
  })
}
