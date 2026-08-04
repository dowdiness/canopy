// formatted_view: Converts pretty-printer Layout into ViewNode tree.
// Each rendered line becomes a child ViewNode with text + token_spans.
// This is the text-format renderer for the multi-representation system
// (see docs/architecture/multi-representation-system.md).

///|
fn category_to_role(cat : @pretty.SyntaxCategory) -> String {
  match cat {
    Keyword => "keyword"
    Identifier => "identifier"
    Number => "number"
    StringLit => "string"
    Operator => "operator"
    Punctuation => "punctuation"
    Comment => "comment"
    Error => "error"
    EvalAnnotation => "eval-annotation"
    EvalError => "eval-error"
  }
}

///|
/// Convert a pretty-print layout into a ViewNode tree for formatted text display.
/// Each rendered line becomes a child ViewNode with text and token_spans.
/// Annotations that span line breaks are split into per-line TokenSpans.
pub fn layout_to_view_tree(
  layout : @pretty.Layout[@pretty.SyntaxCategory],
  width? : Int = 80,
) -> ViewNode {
  let cmds = @pretty.resolve(width, layout)
  let children : Array[ViewNode] = []
  let line_buf = StringBuilder::new()
  let line_spans : Array[TokenSpan] = []
  let ann_stack : Array[(@pretty.SyntaxCategory, Int)] = []
  let mut offset = 0
  let mut line_id = 1
  // flush_line: emit current line as a ViewNode child, handle cross-line spans
  fn flush_line() {
    let text = line_buf.to_string()
    if text.length() > 0 || children.length() > 0 {
      children.push(
        ViewNode(
          id=@core.NodeId::from_int(line_id),
          kind_tag="line",
          label="",
          text~,
          text_range=(0, 0),
          token_spans=line_spans.copy(),
          css_class="line",
        ),
      )
      line_id = line_id + 1
    }
    line_buf.reset()
    line_spans.clear()
    offset = 0
    // Re-open any annotations that were split across the line break
    for i = 0; i < ann_stack.length(); i = i + 1 {
      ann_stack[i] = (ann_stack[i].0, 0)
    }
  }

  for cmd in cmds {
    match cmd {
      @pretty.CText(s) => {
        line_buf.write_string(s)
        offset = offset + s.length()
      }
      @pretty.CNewline(indent) => {
        // Close any open annotations on the current line
        for i = ann_stack.length() - 1; i >= 0; i = i - 1 {
          let (cat, start) = ann_stack[i]
          if offset > start {
            line_spans.push(
              TokenSpan(role=category_to_role(cat), start~, end=offset),
            )
          }
        }
        flush_line()
        // Add indentation
        for j = 0; j < indent; j = j + 1 {
          line_buf.write_char(' ')
        }
        offset = indent
        // Re-open spans at the indent position
        for i = 0; i < ann_stack.length(); i = i + 1 {
          ann_stack[i] = (ann_stack[i].0, offset)
        }
      }
      @pretty.CAnnStart(cat) => ann_stack.push((cat, offset))
      @pretty.CAnnEnd(_) =>
        if ann_stack.pop() is Some((cat, start)) && offset > start {
          line_spans.push(
            TokenSpan(role=category_to_role(cat), start~, end=offset),
          )
        }
    }
  }
  // Flush final line (close any remaining open annotations)
  for i = ann_stack.length() - 1; i >= 0; i = i - 1 {
    let (cat, start) = ann_stack[i]
    if offset > start {
      line_spans.push(TokenSpan(role=category_to_role(cat), start~, end=offset))
    }
  }
  flush_line()
  ViewNode(
    id=@core.NodeId::from_int(0),
    kind_tag="formatted-text",
    label="formatted-text",
    text_range=(0, 0),
    children~,
    css_class="formatted-text",
  )
}
