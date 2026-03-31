///|
test "json null" {
  inspect(
    @pretty.render_string(json_to_layout(@json.JsonValue::Null)),
    content="null",
  )
}

///|
test "json bool true" {
  inspect(
    @pretty.render_string(json_to_layout(@json.JsonValue::Bool(true))),
    content="true",
  )
}

///|
test "json bool false" {
  inspect(
    @pretty.render_string(json_to_layout(@json.JsonValue::Bool(false))),
    content="false",
  )
}

///|
test "json number integer" {
  inspect(
    @pretty.render_string(json_to_layout(@json.JsonValue::Number(3.0))),
    content="3",
  )
}

///|
test "json number float" {
  inspect(
    @pretty.render_string(json_to_layout(@json.JsonValue::Number(3.14))),
    content="3.14",
  )
}

///|
test "json string" {
  inspect(
    @pretty.render_string(json_to_layout(@json.JsonValue::String("hello"))),
    content="\"hello\"",
  )
}

///|
test "json empty array" {
  inspect(
    @pretty.render_string(json_to_layout(@json.JsonValue::Array([]))),
    content=(
      #|[]
    ),
  )
}

///|
test "json array wide" {
  let arr = @json.JsonValue::Array([
    @json.JsonValue::Number(1.0),
    @json.JsonValue::Number(2.0),
    @json.JsonValue::Number(3.0),
  ])
  inspect(
    @pretty.render_string(json_to_layout(arr)),
    content=(
      #|[ 1, 2, 3 ]
    ),
  )
}

///|
test "json empty object" {
  inspect(
    @pretty.render_string(json_to_layout(@json.JsonValue::Object([]))),
    content=(
      #|{}
    ),
  )
}

///|
test "json object" {
  let obj = @json.JsonValue::Object([
    ("name", @json.JsonValue::String("Alice")),
    ("age", @json.JsonValue::Number(30.0)),
  ])
  inspect(
    @pretty.render_string(json_to_layout(obj)),
    content=(
      #|{ "name": "Alice", "age": 30 }
    ),
  )
}

///|
test "json error" {
  inspect(
    @pretty.render_string(
      json_to_layout(@json.JsonValue::Error("unexpected token")),
    ),
    content="<error: unexpected token>",
  )
}
