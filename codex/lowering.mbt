// Codex app-server edit lowering (prototype).
//
// Lowers a Codex `FileChange.update` unified diff into `@protocol.UserIntent`
// TextEdit operations and drives them into a `SyncEditor` under the EXACT
// (grapheme-boundary-checked) policy. Background and verification record:
// docs/research/2026-06-13-canopy-codex-app-server-lowering.md.
//
// Prototype scope (§8 of the research note is OUT of scope): exactly one
// changed line (one `-` line + one `+` line) inside a single `update` hunk.
// Multi-hunk diffs, `add`/`delete` whole-document variants, `move_path`, and
// concurrent-edit fuzzy hunk apply are deliberately unsupported here.
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
  let (line_1based, old_line, new_line) = parse_single_line_update(diff)
  let line_start = line_start_offset(doc, line_1based)
  let (from_in_line, del, insert) = minimal_splice(old_line, new_line)
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
/// Parse a single-changed-line `update` hunk: returns the 1-based old start
/// line plus the old and new line contents (marker stripped).
fn parse_single_line_update(diff : String) -> (Int, String, String) raise {
  // `for .. in` + `mut` is allowed here as a genuine parser STATE MACHINE: the
  // `in_hunk` flag gates how each line is interpreted, and the three result
  // slots accumulate across that state — not a simple accumulator.
  let mut line_no : Int? = None
  let mut old_line : String? = None
  let mut new_line : String? = None
  // Gate on hunk state: `---`/`+++` file headers (and any `diff`/`index`
  // preamble) appear ONLY before the first `@@`. After it, branch on the
  // single marker char so content lines that themselves begin with `-`/`+`
  // (e.g. a Markdown frontmatter `---`, raw diff line `----`) are not mistaken
  // for file headers.
  let mut in_hunk = false
  for line in diff.split("\n") {
    if line.has_prefix("@@") {
      line_no = Some(parse_hunk_old_start(line.to_owned()))
      in_hunk = true
    } else if in_hunk {
      if line.has_prefix("-") {
        old_line = Some(line[1:].to_owned())
      } else if line.has_prefix("+") {
        new_line = Some(line[1:].to_owned())
      }
      // context (' ' prefix) and other lines are ignored in this single-line
      // prototype
    }
    // lines before the first `@@` are file headers / preamble — ignored
  }
  guard line_no is Some(ln) else { fail("codex lowering: no hunk header") }
  guard old_line is Some(o) else { fail("codex lowering: no '-' line") }
  guard new_line is Some(n) else { fail("codex lowering: no '+' line") }
  (ln, o, n)
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
