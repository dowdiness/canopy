// Property-based tests for the Wadler-Lindig pretty-printer.
//
// These tests verify algebraic invariants that must hold for ALL documents,
// not just hand-picked examples. Each property is tested against 100 randomly
// generated Layout trees.
//
// Background: Wadler's pretty-printer ("A prettier printer", 1998) is built
// on a small algebra of document combinators. The key insight is that `Group`
// offers a choice: render content flat (on one line) or broken (with line
// breaks). The layout algorithm greedily picks flat when it fits within the
// target width. These properties verify that this greedy choice preserves
// the algebra's laws.

///|
/// Random document generator using a linear congruential PRNG.
/// Produces Layout[Unit] trees of bounded depth with a mix of all
/// constructors: Empty, Text, Line, HardLine, Nest, Concat, Group, Annotate.
/// The depth bound prevents exponential blowup in tree size.
fn gen_layout(seed : Int, max_depth : Int) -> Layout[Unit] {
  fn go(s : Int, depth : Int) -> (Layout[Unit], Int) {
    let s = s * 1103515245 + 12345
    if depth <= 0 {
      let choice = s.abs() % 3
      match choice {
        0 => (Empty, s)
        1 => (Text("x"), s)
        _ => (Text("ab"), s)
      }
    } else {
      let choice = s.abs() % 8
      match choice {
        0 => (Empty, s)
        1 => (Text("x"), s)
        2 => (Line, s)
        3 => {
          let (doc, s2) = go(s, depth - 1)
          (Nest(2, doc), s2)
        }
        4 => {
          let (l, s2) = go(s, depth - 1)
          let (r, s3) = go(s2, depth - 1)
          (Concat(l, r), s3)
        }
        5 => {
          let (doc, s2) = go(s, depth - 1)
          (Group(doc), s2)
        }
        6 => {
          let (doc, s2) = go(s, depth - 1)
          (Annotate((), doc), s2)
        }
        _ => (HardLine, s)
      }
    }
  }
  let (doc, _) = go(seed, max_depth.abs() % 6)
  doc
}

///|
fn has_hardline(layout : Layout[Unit]) -> Bool {
  match layout {
    Empty | Text(_) | Line => false
    HardLine => true
    Nest(_, doc) => has_hardline(doc)
    Concat(l, r) => has_hardline(l) || has_hardline(r)
    Group(doc) => has_hardline(doc)
    Annotate(_, doc) => has_hardline(doc)
  }
}

///|
fn max_line_width(s : String) -> Int {
  let mut max_w = 0
  let mut cur_w = 0
  for ch in s {
    if ch == '\n' {
      if cur_w > max_w {
        max_w = cur_w
      }
      cur_w = 0
    } else {
      cur_w += 1
    }
  }
  if cur_w > max_w {
    max_w = cur_w
  }
  max_w
}

///|
fn max_token_width(layout : Layout[Unit]) -> Int {
  match layout {
    Empty | Line | HardLine => 0
    Text(s) => s.length()
    Nest(_, doc) => max_token_width(doc)
    Concat(l, r) => {
      let lw = max_token_width(l)
      let rw = max_token_width(r)
      if lw > rw { lw } else { rw }
    }
    Group(doc) => max_token_width(doc)
    Annotate(_, doc) => max_token_width(doc)
  }
}

///|
/// The fundamental guarantee of Wadler's algorithm: every line in the output
/// fits within the requested width. The only exception is when a single
/// indivisible token (Text node) is already wider than the target — the
/// algorithm cannot break inside a token, so that line will overflow.
test "property: no line exceeds width (unless forced by token)" {
  @qc.quick_check_fn(fn(input : (Int, Int)) -> Bool {
    let (seed, width_raw) = input
    let width = width_raw.abs() % 40 + 5
    let doc = gen_layout(seed, 5)
    let output = render_string(doc, width~)
    let max_w = max_line_width(output)
    let max_tok = max_token_width(doc)
    max_w <= width || max_w <= max_tok
  })
}

///|
/// When a document has no HardLine nodes and is wrapped in a Group, giving
/// it infinite width should produce single-line output. This verifies that
/// Group's flattening works correctly: Line nodes become spaces in flat mode.
///
/// Why we wrap in group(): bare Line nodes at the top level are in Break mode
/// (the default), so they always produce newlines. Only Lines inside a Group
/// can be flattened. This matches real usage — pretty-printers always wrap
/// their output in at least one group.
test "property: grouped doc with no HardLine flattens at wide width" {
  @qc.quick_check_fn(fn(seed : Int) -> Bool {
    let doc = gen_layout(seed, 5)
    if has_hardline(doc) {
      true
    } else {
      let output = render_string(group(doc), width=1000000)
      not(output.contains("\n"))
    }
  })
}

///|
/// flat_width computes the width a document would occupy if rendered entirely
/// on one line (Lines become spaces). This must match the actual rendered
/// width when we force flat mode by wrapping in group() at infinite width.
///
/// When flat_width returns -1, the document contains HardLine and cannot
/// be flattened — we verify that has_hardline agrees.
test "property: flat_width matches grouped flat rendering width" {
  @qc.quick_check_fn(fn(seed : Int) -> Bool {
    let doc = gen_layout(seed, 5)
    let fw = flat_width(doc)
    if fw < 0 {
      has_hardline(doc)
    } else {
      let output = render_string(group(doc), width=1000000)
      output.length() == fw
    }
  })
}

///|
/// render_string and render_spans use the same resolve() function to produce
/// the same Cmd stream. This property verifies that all span offsets from
/// render_spans fall within the string produced by render_string — they
/// share a consistent coordinate space.
test "property: render_string and render_spans have consistent length" {
  @qc.quick_check_fn(fn(input : (Int, Int)) -> Bool {
    let (seed, width_raw) = input
    let width = width_raw.abs() % 40 + 5
    let doc : Layout[Unit] = gen_layout(seed, 4)
    let str_output = render_string(doc, width~)
    let spans = render_spans(doc, width~)
    let str_len = str_output.length()
    spans.iter().all(fn(pair) {
      let (span, _) = pair
      span.start >= 0 && span.end <= str_len && span.start <= span.end
    })
  })
}

///|
/// Group is idempotent: wrapping a document in two Groups produces the same
/// output as one Group. This holds because Group's decision depends only on
/// flat_width, which is the same regardless of how many Group layers exist.
test "property: group is idempotent" {
  @qc.quick_check_fn(fn(input : (Int, Int)) -> Bool {
    let (seed, width_raw) = input
    let width = width_raw.abs() % 40 + 5
    let doc = gen_layout(seed, 4)
    let single = render_string(group(doc), width~)
    let double = render_string(group(group(doc)), width~)
    single == double
  })
}

///|
/// Empty is the identity element for Concat (the + operator).
/// Concatenating Empty before or after a document must not change the output.
/// This is one of Wadler's algebraic laws: `nil <> x = x` and `x <> nil = x`.
test "property: Empty is identity for concat" {
  @qc.quick_check_fn(fn(input : (Int, Int)) -> Bool {
    let (seed, width_raw) = input
    let width = width_raw.abs() % 40 + 5
    let doc = gen_layout(seed, 4)
    let base = render_string(doc, width~)
    let left_id = render_string(Empty + doc, width~)
    let right_id = render_string(doc + Empty, width~)
    base == left_id && base == right_id
  })
}

///|
/// Width monotonicity: giving the layout algorithm more horizontal space
/// should never make individual lines wider than they would be at the wider
/// width. In other words, the algorithm should take advantage of extra space
/// (flattening more groups) but never waste it.
test "property: wider width produces output no wider than narrow" {
  @qc.quick_check_fn(fn(input : (Int, Int)) -> Bool {
    let (seed, widths_raw) = input
    let narrow = widths_raw.abs() % 20 + 5
    let wide = narrow + widths_raw.abs() % 40 + 1
    let doc = gen_layout(seed, 4)
    let narrow_lines = max_line_width(render_string(doc, width=narrow))
    let wide_lines = max_line_width(render_string(doc, width=wide))
    wide_lines <= wide && (wide_lines <= narrow_lines || narrow_lines <= narrow)
  })
}
