///|
fn json_ann(category : @pretty.SyntaxCategory) -> @pretty.Ann {
  { category, node_id: None }
}

///|
fn escape_json_string(s : String) -> String {
  let buf = StringBuilder::new()
  for ch in s {
    match ch {
      '"' => buf.write_string("\\\"")
      '\\' => buf.write_string("\\\\")
      '\n' => buf.write_string("\\n")
      '\r' => buf.write_string("\\r")
      '\t' => buf.write_string("\\t")
      '\b' => buf.write_string("\\b")
      '\u000C' => buf.write_string("\\f")
      ch => {
        let code = ch.to_uint()
        if code < 0x20 {
          let hex = b"0123456789abcdef"
          buf.write_string("\\u00")
          buf.write_char(
            hex[(code >> 4).reinterpret_as_int()].to_int().unsafe_to_char(),
          )
          buf.write_char(
            hex[(code & 0xf).reinterpret_as_int()].to_int().unsafe_to_char(),
          )
        } else {
          buf.write_char(ch)
        }
      }
    }
  }
  buf.to_string()
}

///|
pub fn json_to_layout(value : @json.JsonValue) -> @pretty.Layout[@pretty.Ann] {
  match value {
    @json.JsonValue::Null =>
      @pretty.annotate(
        json_ann(@pretty.SyntaxCategory::Keyword),
        @pretty.text("null"),
      )
    @json.JsonValue::Bool(b) =>
      @pretty.annotate(
        json_ann(@pretty.SyntaxCategory::Keyword),
        @pretty.text(b.to_string()),
      )
    @json.JsonValue::Number(n) => {
      let s = n.to_string()
      let display = if s.has_suffix(".0") {
        s[0:s.length() - 2].to_string()
      } else {
        s
      }
      @pretty.annotate(
        json_ann(@pretty.SyntaxCategory::Number),
        @pretty.text(display),
      )
    }
    @json.JsonValue::String(s) =>
      @pretty.annotate(
        json_ann(@pretty.SyntaxCategory::StringLit),
        @pretty.text("\"" + escape_json_string(s) + "\""),
      )
    @json.JsonValue::Array([]) => @pretty.text("[]")
    @json.JsonValue::Array(elems) => {
      let items = elems.map(json_to_layout)
      let sep = @pretty.text(",") + @pretty.line()
      @pretty.group(
        @pretty.text("[") +
        @pretty.nest(@pretty.softline() + @pretty.separate(sep, items)) +
        @pretty.softline() +
        @pretty.text("]"),
      )
    }
    @json.JsonValue::Object([]) => @pretty.text("{}")
    @json.JsonValue::Object(pairs) => {
      let entries = pairs.map(fn(pair) {
        let (key, val) = pair
        @pretty.annotate(
          json_ann(@pretty.SyntaxCategory::StringLit),
          @pretty.text("\"" + escape_json_string(key) + "\""),
        ) +
        @pretty.text(":") +
        @pretty.text(" ") +
        json_to_layout(val)
      })
      let sep = @pretty.text(",") + @pretty.line()
      @pretty.group(
        @pretty.text("{") +
        @pretty.nest(@pretty.softline() + @pretty.separate(sep, entries)) +
        @pretty.softline() +
        @pretty.text("}"),
      )
    }
    @json.JsonValue::Error(msg) =>
      @pretty.annotate(
        json_ann(@pretty.SyntaxCategory::Error),
        @pretty.text("<error: " + msg + ">"),
      )
  }
}
