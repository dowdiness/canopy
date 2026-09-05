///|
test "CodeMirror source version guard rejects unknown and mismatched events" {
  inspect(code_mirror_source_version_matches("v1", "v1"), content="true")
  inspect(code_mirror_source_version_matches("v1", "v2"), content="false")
  inspect(code_mirror_source_version_matches("", "v2"), content="false")
}

///|
test "stale CodeMirror change uses its captured document" {
  let model = init_model()
  let source = model.editor.get_text()
  let source_version = Hash::hash(model.editor.get_version()).to_string()
  model.editor.set_text_and_record("R" + source, 1)
  let current_source_version = Hash::hash(model.editor.get_version()).to_string()
  inspect(source_version != current_source_version, content="true")
  let expected = "L" + source
  let event = @cm.ChangeEvent::new(
    [@cm.ChangeDelta::new(0, 0, "L")],
    expected,
    source_version~,
  )
  let changed = match
    handle_codemirror(test_parent_emit(), CmChanges(event), model) {
    Some((_, changed)) => changed
    None => abort("CmChanges was not handled")
  }
  inspect(changed.editor.get_text(), content=expected)
}
