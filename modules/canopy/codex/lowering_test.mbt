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
  let se = try! @probe.new_test_editor("codex-agent")
  se.apply_text_edit(0, 0, "🧑🧒", 0)
  assert_eq(se.get_text(), "🧑🧒")
  let diff =
    #|@@ -1 +1 @@
    #|-🧑🧒
    #|+🧒
  let intents = unified_diff_to_intents(se.get_text(), diff)
  // Apply every lowered intent; the document is correct only if all are
  // accepted by EXACT. `apply...` is the left operand so it always runs.
  let all_accepted = intents.fold(init=true, (ok, intent) => {
    apply_intent_exact(se, intent, 1) && ok
  })
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
  let se = try! @probe.new_test_editor("codex-agent")
  se.apply_text_edit(0, 0, "---", 0)
  let diff =
    #|@@ -1 +1 @@
    #|----
    #|+***
  let intents = unified_diff_to_intents(se.get_text(), diff)
  // Apply every lowered intent; the document is correct only if all are
  // accepted by EXACT. `apply...` is the left operand so it always runs.
  let all_accepted = intents.fold(init=true, (ok, intent) => {
    apply_intent_exact(se, intent, 1) && ok
  })
  assert_true(all_accepted)
  assert_eq(se.get_text(), "***")
}

///|
/// Seatbelt: EXACT must reject a hand-fed mid-grapheme offset, leaving the
/// document unchanged — proving the guard is load-bearing independent of the
/// converter. Offset 1 is the low surrogate of the first emoji.
test "codex lowering: EXACT rejects a hand-fed mid-grapheme offset" {
  let se = try! @probe.new_test_editor("codex-agent")
  se.apply_text_edit(0, 0, "🧑🧒", 0)
  let accepted = se.apply_text_edit_exact(1, 2, "", 1)
  assert_false(accepted)
  assert_eq(se.get_text(), "🧑🧒")
}

///|
/// P1: a hunk with a leading context line must edit the actually-changed line,
/// not the hunk's first line. Document `a\nb`; the hunk changes line 2
/// (`b` -> `c`) behind one context line. A parser that used the hunk start
/// (line 1) would corrupt line 1 (`c\nb`); tracking the old-side line yields
/// `a\nc`.
test "codex lowering: leading context selects the correct old line" {
  let se = try! @probe.new_test_editor("codex-agent")
  se.apply_text_edit(0, 0, "a\nb", 0)
  let diff =
    #|@@ -1,2 +1,2 @@
    #| a
    #|-b
    #|+c
  let intents = unified_diff_to_intents(se.get_text(), diff)
  let all_accepted = intents.fold(init=true, (ok, intent) => {
    apply_intent_exact(se, intent, 1) && ok
  })
  assert_true(all_accepted)
  assert_eq(se.get_text(), "a\nc")
}

///|
/// P2a: a stale hunk — the document line no longer equals the patch's old text
/// — must be rejected, not spliced into unrelated content.
test "codex lowering: stale diff is rejected" {
  let diff =
    #|@@ -1 +1 @@
    #|-foo
    #|+fOO
  let raised = try {
    let _ = unified_diff_to_intents("bar", diff)
    false
  } catch {
    _ => true
  }
  assert_true(raised)
}

///|
/// P2b: an `update` hunk with more than one changed pair is out of scope and
/// must fail rather than silently keeping only the last pair.
test "codex lowering: multi-line update is rejected" {
  let diff =
    #|@@ -1,2 +1,2 @@
    #|-a
    #|+x
    #|-b
    #|+y
  let raised = try {
    let _ = unified_diff_to_intents("a\nb", diff)
    false
  } catch {
    _ => true
  }
  assert_true(raised)
}

///|
/// P2c: a `\ No newline at end of file` marker changes trailing-newline
/// semantics the prototype does not model, so it must be rejected rather than
/// silently dropped (which would leave the document's old `\n` in place).
test "codex lowering: EOF-newline marker is rejected" {
  let diff =
    #|@@ -1 +1 @@
    #|-foo
    #|+bar
    #|\ No newline at end of file
  let raised = try {
    let _ = unified_diff_to_intents("foo", diff)
    false
  } catch {
    _ => true
  }
  assert_true(raised)
}

///|
/// P1 (separated delete/insert): a single `-`/`+` separated by context is a
/// delete + insert at different positions (move-shaped), not a replace.
/// `a\nb\nc` with `-a` … `+x` means "drop line 1, append x" — pairing them as
/// a replace would corrupt line 1 (`x\nb\nc`). It must be rejected.
test "codex lowering: separated delete/insert is rejected" {
  let diff =
    #|@@ -1,3 +1,3 @@
    #|-a
    #| b
    #| c
    #|+x
  let raised = try {
    let _ = unified_diff_to_intents("a\nb\nc", diff)
    false
  } catch {
    _ => true
  }
  assert_true(raised)
}

///|
/// P2 (absent target line): a hunk whose target line does not exist in the
/// current document must fail, not collapse to EOF and match an empty
/// `old_text`. Here the patch edits line 2 (empty -> `bar`) but the document
/// `foo` has only line 1, so applying it would insert at EOF (`foobar`).
test "codex lowering: edit targeting an absent line is rejected" {
  let diff =
    #|@@ -1,2 +1,2 @@
    #| foo
    #|-
    #|+bar
  let raised = try {
    let _ = unified_diff_to_intents("foo", diff)
    false
  } catch {
    _ => true
  }
  assert_true(raised)
}
