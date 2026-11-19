///|
test "origin_of_base_uri drops the page path" {
  inspect(
    @base_uri.origin_of_base_uri("https://loomark.example/app/index.html"),
    content="https://loomark.example",
  )
  inspect(
    @base_uri.origin_of_base_uri("http://localhost:5173/documents/42?tab=1#top"),
    content="http://localhost:5173",
  )
}

///|
test "origin_of_base_uri keeps a bare origin and tolerates a trailing slash" {
  inspect(
    @base_uri.origin_of_base_uri("https://loomark.example"),
    content="https://loomark.example",
  )
  inspect(
    @base_uri.origin_of_base_uri("https://loomark.example/"),
    content="https://loomark.example",
  )
}

///|
test "origin_of_base_uri leaves the empty test base URI empty" {
  inspect(@base_uri.origin_of_base_uri(""), content="")
}
