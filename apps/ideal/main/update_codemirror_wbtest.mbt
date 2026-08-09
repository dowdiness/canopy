///|
test "CodeMirror source version guard rejects unknown and mismatched events" {
  inspect(code_mirror_source_version_matches("v1", "v1"), content="true")
  inspect(code_mirror_source_version_matches("v1", "v2"), content="false")
  inspect(code_mirror_source_version_matches("", "v2"), content="false")
}
