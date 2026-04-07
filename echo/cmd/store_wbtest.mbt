///|
impl Show for StoredPost with output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
test "StoredPost JSON round-trip" {
  let posts : Array[StoredPost] = [
    { text: "CRDTのmerge操作でバグ", ts: "2026-04-04T10:00:00Z" },
    { text: "カレーを作った", ts: "2026-04-04T11:30:00Z" },
  ]
  let json = posts_to_json(posts)
  let (parsed, err) = posts_from_json(json)
  inspect(err, content="None")
  inspect(parsed.length(), content="2")
  inspect(parsed[0].text, content="CRDTのmerge操作でバグ")
  inspect(parsed[0].ts, content="2026-04-04T10:00:00Z")
  inspect(parsed[1].text, content="カレーを作った")
}

///|
test "posts_from_json - empty string returns empty, no error" {
  let (posts, err) = posts_from_json("")
  inspect(posts, content="[]")
  inspect(err, content="None")
}

///|
test "posts_from_json - invalid JSON returns error" {
  let (posts, err) = posts_from_json("not json")
  inspect(posts, content="[]")
  // Error should be Some(...) for corrupt data
  inspect(err is None, content="false")
}

///|
test "posts_from_json - empty array" {
  let (posts, err) = posts_from_json("[]")
  inspect(posts, content="[]")
  inspect(err, content="None")
}
