// Codex app-server edit lowering (prototype).
//
// Lowers a Codex `FileChange.update` unified diff into `@protocol.UserIntent`
// TextEdit operations and drives them into a `SyncEditor` under the EXACT
// (grapheme-boundary-checked) policy. Background and verification record:
// docs/research/2026-06-13-canopy-codex-app-server-lowering.md.
//
// Prototype scope (§8 of the research note is OUT of scope): exactly one
// changed line (one `-` line + one `+` line) inside a single `update` hunk,
// applied only when the document line still matches the patch's old text.
// Multi-hunk diffs, multi-line hunks, `add`/`delete` whole-document variants,
// `move_path`, `\ No newline at end of file` semantics, and concurrent /
// stale apply are REJECTED with a clear error here — never silently
// mishandled, which would corrupt unrelated text.
//
// Design note (refines the research note's framing): because a unified diff is
// line-based and its content lines reach MoonBit already decoded to `String`
// (UTF-16), there is no explicit UTF-8 byte -> UTF-16 conversion step — the
// decode at the transport boundary absorbs it. The risk that survives is
// grapheme-splitting by a too-fine minimal diff, which is why the splice is
// computed at GRAPHEME granularity and driven through `apply_text_edit_exact`.

///|
/// Lower a unified-diff `update` payload into TextEdit intents against `doc`.
///
/// `doc` is the current document text (UTF-16); `diff` is the unified-diff
/// string from `FileChange.update.unified_diff`. Returns one TextEdit per
/// changed line (prototype: exactly one).
pub fn unified_diff_to_intents(
  doc : String,
  diff : String,
) -> Array[@protocol.UserIntent] raise {
  let (edit_line, old_text, new_text) = parse_single_line_update(diff)
  let line_start = line_start_offset(doc, edit_line)
  let line_end = line_end_offset(doc, line_start)
  // Stale-diff guard: this prototype does no fuzzy/concurrent apply, so the
  // targeted document line MUST currently equal the patch's old text. Without
  // it, a stale hunk would splice grapheme-aligned offsets into unrelated
  // content and `apply_text_edit_exact` would accept the corruption.
  guard doc[line_start:line_end] == old_text[:] else {
    fail(
      "codex lowering: stale diff — document line \{edit_line} does not match the patch old text",
    )
  }
  let (from_in_line, del, insert) = minimal_splice(old_text, new_text)
  let from = line_start + from_in_line
  [@protocol.UserIntent::TextEdit(from~, to=from + del, insert~)]
}

///|
/// Drive a single lowered intent into the editor under EXACT-boundary policy.
/// Returns `false` (document unchanged) if the splice endpoints are not
/// grapheme boundaries or are out of range — the load-bearing seatbelt.
pub fn[T : Eq] apply_intent_exact(
  se : @editor.SyncEditor[T],
  intent : @protocol.UserIntent,
  timestamp_ms : Int,
) -> Bool raise {
  guard intent is @protocol.UserIntent::TextEdit(from~, to~, insert~) else {
    fail("codex lowering prototype: only TextEdit is supported")
  }
  se.apply_text_edit_exact(from, to - from, insert, timestamp_ms)
}

///|
/// Minimal sub-line splice between `old` and `new` as a `(from, del, insert)`
/// triple in UTF-16 code units, with endpoints aligned to GRAPHEME-cluster
/// boundaries by construction.
///
/// Common prefix and suffix are matched a whole cluster at a time, so the
/// returned `from`/`from + del` never split a surrogate pair or a combining
/// sequence. This resolves the research note's §5 chain (sub-line minimal ->
/// mid-grapheme possible -> grapheme alignment required) at the diff step,
/// leaving `apply_text_edit_exact` as a pure seatbelt rather than a routine
/// rejecter of legitimate edits.
fn minimal_splice(old : String, new : String) -> (Int, Int, String) {
  let ob = @moji.grapheme_boundaries(old)
  let nb = @moji.grapheme_boundaries(new)
  let onc = ob.length() - 1 // number of grapheme clusters in `old`
  let nnc = nb.length() - 1
  let bound = onc.min(nnc)
  // longest common grapheme prefix, then suffix (suffix cannot overlap prefix:
  // it scans the remaining `bound - p` clusters), so `from <= to` always holds.
  let p = for k in 0..<bound {
    if old[ob[k]:ob[k + 1]] != new[nb[k]:nb[k + 1]] {
      break k
    }
  } nobreak {
    bound
  }
  let s = for k in 0..<(bound - p) {
    if old[ob[onc - 1 - k]:ob[onc - k]] != new[nb[nnc - 1 - k]:nb[nnc - k]] {
      break k
    }
  } nobreak {
    bound - p
  }
  let from = ob[p]
  let to = ob[onc - s]
  let insert = new[nb[p]:nb[nnc - s]].to_owned()
  (from, to - from, insert)
}

///|
/// UTF-16 offset of the start of the given 1-based line in `doc`.
fn line_start_offset(doc : String, line_1based : Int) -> Int {
  if line_1based <= 1 {
    return 0
  }
  for i in 0..<doc.length(); line = 1 {
    if doc[i] is '\n' {
      if line + 1 == line_1based {
        break i + 1
      }
      continue line + 1
    }
    continue line
  } nobreak {
    doc.length()
  }
}

///|
/// UTF-16 offset of the end of the line that starts at `start` — the next
/// `\n`, or the end of the document.
fn line_end_offset(doc : String, start : Int) -> Int {
  for i in start..<doc.length() {
    if doc[i] is '\n' {
      break i
    }
  } nobreak {
    doc.length()
  }
}

///|
/// Parse a single-changed-line `update` hunk. Returns `(old_line_number,
/// old_text, new_text)` where `old_line_number` is the 1-based old-side line
/// of the `-` line (NOT the hunk's first line — a hunk may carry leading
/// context). Rejects anything outside the prototype's scope.
///
/// `for .. in` + `mut` is allowed here as a genuine parser STATE MACHINE:
/// `cur_old` (Some once the `@@` header is seen) tracks the old-side line
/// number, and the slots accumulate across that state. Per the unified-diff
/// model, context (` `) and deleted (`-`) lines advance the old side; added
/// (`+`) lines do not. Out-of-scope inputs — more than one hunk, more than one
/// changed pair, or a `\ No newline at end of file` marker — fail rather than
/// being silently dropped or mis-applied.
fn parse_single_line_update(diff : String) -> (Int, String, String) raise {
  let mut cur_old : Int? = None // None until the first `@@`; else next old line
  let mut hunks = 0
  let mut old_at : (Int, String)? = None // (old line number, content) of `-`
  let mut old_count = 0
  let mut new_text : String? = None
  let mut new_count = 0
  for line in diff.split("\n") {
    if line.has_prefix("@@") {
      hunks += 1
      cur_old = Some(parse_hunk_old_start(line.to_owned()))
    } else if line.has_prefix("\\") {
      // `\ No newline at end of file`: trailing-newline semantics unsupported.
      fail("codex lowering: EOF-newline marker unsupported (out of scope)")
    } else if cur_old is Some(n) {
      if line.has_prefix("-") {
        old_at = Some((n, line[1:].to_owned()))
        old_count += 1
        cur_old = Some(n + 1)
      } else if line.has_prefix("+") {
        new_text = Some(line[1:].to_owned())
        new_count += 1
      } else if line.has_prefix(" ") {
        cur_old = Some(n + 1) // context line advances the old side
      }
    }
    // lines before the first `@@` are file headers / preamble — ignored
  }
  guard hunks <= 1 else {
    fail("codex lowering: multi-hunk update unsupported (out of scope)")
  }
  guard old_count <= 1 && new_count <= 1 else {
    fail("codex lowering: multi-line update unsupported (out of scope)")
  }
  guard old_at is Some((edit_line, old_text)) else {
    fail("codex lowering: no hunk `-` line")
  }
  guard new_text is Some(new_text) else {
    fail("codex lowering: no hunk `+` line")
  }
  (edit_line, old_text, new_text)
}

///|
/// Extract the old start line `A` from a hunk header `@@ -A[,B] +C[,D] @@`.
fn parse_hunk_old_start(header : String) -> Int raise {
  guard header.split(" ").find_first(tok => tok.has_prefix("-")) is Some(tok) else {
    fail("codex lowering: malformed hunk header")
  }
  // `@@ -A[,B]` — take the field before the optional comma. `split` always
  // yields at least one element, so a `None` here means an empty old-start
  // (a malformed header); fail explicitly rather than silently reusing it.
  guard tok[1:].split(",").next() is Some(start_field) else {
    fail("codex lowering: empty hunk old-start field")
  }
  @string.parse_int(start_field.to_owned())
}
