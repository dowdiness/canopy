// Prototype tests for Codex unified-diff -> UserIntent::TextEdit lowering.
//
// Vector rationale (non-vacuity): the two emoji U+1F9D1 (🧑) and U+1F9D2 (🧒)
// share the same UTF-16 high surrogate (D83E) and differ only in the low
// surrogate (DFD1 vs DFD2). A code-unit-granular minimal diff therefore stops
// its common prefix AFTER the shared high surrogate, yielding a mid-surrogate
// offset that `apply_text_edit_exact` rejects (or that lands wrong) — so the
// full-text-match assertion FAILS for a broken converter and passes only for a
// grapheme-granular one. See
// docs/research/2026-06-13-canopy-codex-app-server-lowering.md §4-§6.

///|
/// Accept path + full-text-match. Deletes the first of two adjacent emoji via
/// a single-line `update` diff. Only a grapheme-correct converter both is
/// accepted by EXACT and reproduces the intended document.
test "codex lowering: update diff deletes first of two adjacent emoji" {
  let se = @probe.new_test_editor("codex-agent")
  se.apply_text_edit(0, 0, "🧑🧒", 0)
  assert_eq(se.get_text(), "🧑🧒")
  let diff =
    #|@@ -1 +1 @@
    #|-🧑🧒
    #|+🧒
  let intents = unified_diff_to_intents(se.get_text(), diff)
  let mut all_accepted = true
  for intent in intents {
    if !apply_intent_exact(se, intent, 1) {
      all_accepted = false
    }
  }
  assert_true(all_accepted)
  assert_eq(se.get_text(), "🧒")
}

///|
/// Regression (Codex pre-PR review): a content line that itself begins with
/// `-` must not be mistaken for a `---` file header. Document line `---`
/// (Markdown frontmatter delimiter) appears in the diff as the raw line
/// `----`; the old "skip any `---` prefix" parser dropped it. With hunk-state
/// gating the marker is stripped to content `---`, replaced by `***`.
test "codex lowering: content line starting with dashes is not a file header" {
  let se = @probe.new_test_editor("codex-agent")
  se.apply_text_edit(0, 0, "---", 0)
  let diff =
    #|@@ -1 +1 @@
    #|----
    #|+***
  let intents = unified_diff_to_intents(se.get_text(), diff)
  let mut all_accepted = true
  for intent in intents {
    if !apply_intent_exact(se, intent, 1) {
      all_accepted = false
    }
  }
  assert_true(all_accepted)
  assert_eq(se.get_text(), "***")
}

///|
/// Seatbelt: EXACT must reject a hand-fed mid-grapheme offset, leaving the
/// document unchanged — proving the guard is load-bearing independent of the
/// converter. Offset 1 is the low surrogate of the first emoji.
test "codex lowering: EXACT rejects a hand-fed mid-grapheme offset" {
  let se = @probe.new_test_editor("codex-agent")
  se.apply_text_edit(0, 0, "🧑🧒", 0)
  let accepted = se.apply_text_edit_exact(1, 2, "", 1)
  assert_false(accepted)
  assert_eq(se.get_text(), "🧑🧒")
}
