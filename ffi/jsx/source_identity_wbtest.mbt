///|
test "JSX source identity allocator returns distinct construction IDs" {
  let source_a = allocate_jsx_source_id()
  let source_b = allocate_jsx_source_id()
  inspect(source_a == source_b, content="false")
}
