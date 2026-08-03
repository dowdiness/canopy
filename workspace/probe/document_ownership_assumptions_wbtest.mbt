// Assumptions that docs/design/local-first-document-ownership.md rests on.
//
// These are drift detectors, not tests of the CRDT. Each one pins a substrate
// property the design reasons from, so that a change underneath the design
// fails here instead of surfacing later as a corrupted archive. If one of
// these fails, the design is what needs revisiting -- not this file.
//
// Evidence record: docs/evidence/2026-08-03-local-first-document-ownership-claims.json

///|
/// A checkpoint round-trips into a fresh editor.
///
/// The design stores a full history export as the archive payload and restores
/// by applying it to a new editor. If this stops holding, the archive format
/// cannot be built the way the design describes.
///
/// This also pins that restoring an intact checkpoint leaves no causally
/// pending operations: apply_sync raises when pending remain, so a clean
/// return is the observation.
test "ownership: checkpoint round-trips into a fresh editor" {
  let original = @editor.Editor::new("assumption-writer-1")
  original.insert_at(0, "# Title\n\nbody text\n")
  original.insert_at(8, "!")
  let want_text = original.get_text()
  let want_version = original.get_version()
  let checkpoint_json = original.export_all().to_json_string()
  let restored = @editor.Editor::new("assumption-writer-2")
  let decoded = @text.SyncMessage::from_json_string(checkpoint_json)
  let applied = try {
    restored.apply_sync(decoded)
    true
  } catch {
    _ => false
  }
  inspect(applied, content="true")
  inspect(restored.get_text() == want_text, content="true")
  inspect(
    restored.get_version().to_json_string() == want_version.to_json_string(),
    content="true",
  )
  inspect(
    original.export_all().to_canonical_bytes() ==
    restored.export_all().to_canonical_bytes(),
    content="true",
  )
}

///|
/// Text plus version is not a proof of continuation.
///
/// This is the assumption that decides how restore may be checked. Two
/// writers sharing an identity produce equal text and an equal version while
/// holding different histories, so an oracle built on text and version accepts
/// a document that is not a continuation of the one that was saved.
///
/// Anything asserting "the document was restored correctly" must therefore
/// compare canonical history, as the round-trip test above does.
test "ownership: equal text and version do not imply equal history" {
  let one = @editor.Editor::new("same-identity")
  let two = @editor.Editor::new("same-identity")
  one.insert_at(0, "A")
  two.insert_at(0, "B")
  one.move_cursor(1)
  two.move_cursor(1)
  let _ = one.backspace()
  let _ = two.backspace()
  inspect(one.get_text() == two.get_text(), content="true")
  inspect(
    one.get_version().to_json_string() == two.get_version().to_json_string(),
    content="true",
  )
  // The weak-oracle demonstration: identical by text and version, distinct by
  // history. If this ever becomes true, the design's oracle can be relaxed.
  inspect(
    one.export_all().to_canonical_bytes() ==
    two.export_all().to_canonical_bytes(),
    content="false",
  )
}

///|
/// An edit that restores the previous text still advances the document.
///
/// The design requires persistence to trigger on history rather than on text.
/// This pins the hazard that requirement exists for: deciding whether to save
/// by comparing text skips a save that mattered.
test "ownership: text-preserving edit still advances the version" {
  let ed = @editor.Editor::new("assumption-writer-4")
  ed.insert_at(0, "hello")
  let before_text = ed.get_text()
  let before_version = ed.get_version().to_json_string()
  ed.move_cursor(1)
  let _ = ed.backspace()
  ed.insert_at(0, "h")
  inspect(ed.get_text() == before_text, content="true")
  inspect(ed.get_version().to_json_string() == before_version, content="false")
}
