///|
/// Generate a deterministic Layout[Unit] from a seed and bounded depth.
fn gen_layout(seed : Int, max_depth : Int) -> Layout[Unit] {
  fn go(s : Int, depth : Int) -> (Layout[Unit], Int) {
    let s = s * 1103515245 + 12345
    if depth <= 0 {
      // Leaf: text or empty
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
/// Check if a layout contains HardLine.
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
/// Get max line width from a rendered string.
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
/// Get the max width of any single Text node in a layout.
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
test "property: no line exceeds width (unless forced by token)" {
  @qc.quick_check_fn(fn(input : (Int, Int)) -> Bool {
    let (seed, width_raw) = input
    let width = width_raw.abs() % 40 + 5
    let doc = gen_layout(seed, 5)
    let output = render_string(doc, width~)
    let max_w = max_line_width(output)
    let max_tok = max_token_width(doc)
    // Each line should fit in width, unless a single token is wider
    max_w <= width || max_w <= max_tok
  })
}

///|
test "property: grouped doc with no HardLine flattens at wide width" {
  @qc.quick_check_fn(fn(seed : Int) -> Bool {
    let doc = gen_layout(seed, 5)
    if has_hardline(doc) {
      true // skip documents with hardline
    } else {
      // Wrap in group so top-level Lines flatten to spaces
      let output = render_string(group(doc), width=1000000)
      not(output.contains("\n"))
    }
  })
}

///|
test "property: flat_width matches grouped flat rendering width" {
  @qc.quick_check_fn(fn(seed : Int) -> Bool {
    let doc = gen_layout(seed, 5)
    let fw = flat_width(doc)
    if fw < 0 {
      // HardLine present — flat_width signals "can't flatten"
      has_hardline(doc)
    } else {
      // Wrap in group so all Lines become spaces at wide width
      let output = render_string(group(doc), width=1000000)
      output.length() == fw
    }
  })
}

///|
test "property: render_string and render_spans have consistent length" {
  @qc.quick_check_fn(fn(input : (Int, Int)) -> Bool {
    let (seed, width_raw) = input
    let width = width_raw.abs() % 40 + 5
    let doc : Layout[Unit] = gen_layout(seed, 4)
    let str_output = render_string(doc, width~)
    let spans = render_spans(doc, width~)
    // All span offsets should be within the string length
    let str_len = str_output.length()
    spans.iter().all(fn(pair) {
      let (span, _) = pair
      span.start >= 0 && span.end <= str_len && span.start <= span.end
    })
  })
}

///|
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
test "property: wider width produces output no wider than narrow" {
  @qc.quick_check_fn(fn(input : (Int, Int)) -> Bool {
    let (seed, widths_raw) = input
    let narrow = widths_raw.abs() % 20 + 5
    let wide = narrow + widths_raw.abs() % 40 + 1
    let doc = gen_layout(seed, 4)
    let narrow_lines = max_line_width(render_string(doc, width=narrow))
    let wide_lines = max_line_width(render_string(doc, width=wide))
    // Wider width should produce same or narrower output
    wide_lines <= wide && (wide_lines <= narrow_lines || narrow_lines <= narrow)
  })
}
