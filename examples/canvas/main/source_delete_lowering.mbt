///|
priv enum SourceOperationEdit {
  ExactLoweredEdit(@graph_dsl.LoweredGraphEdit)
  WholeSourceReplacement(String)
}

///|
priv struct SourceDeletionSpan {
  start : Int
  end : Int
}

///|
fn string_in_array(items : Array[String], target : String) -> Bool {
  for item in items {
    if item == target {
      return true
    }
  }
  false
}

///|
fn append_unique_string(items : Array[String], item : String) -> Unit {
  if !string_in_array(items, item) {
    items.push(item)
  }
}

///|
fn deleted_bindings_for_canvas_ids(
  doc : @graph_dsl.GraphDoc,
  node_ids : Array[NodeId],
) -> Result[Array[String], String] {
  let bindings : Array[String] = []
  for id in node_ids {
    match graph_node_for_canvas_id(doc, id) {
      Some(node) => append_unique_string(bindings, node.binding())
      None =>
        return Err("cannot lower DeleteNodes: missing node " + id.to_string())
    }
  }
  if bindings.length() == 0 {
    Err("cannot lower DeleteNodes: no nodes selected")
  } else {
    Ok(bindings)
  }
}

///|
fn survivor_reference_to_deleted_binding(
  doc : @graph_dsl.GraphDoc,
  deleted_bindings : Array[String],
) -> (String, String)? {
  for node in doc.nodes() {
    if !string_in_array(deleted_bindings, node.binding()) {
      for param in node.params() {
        match graph_input_reference(param) {
          Some(binding) if string_in_array(deleted_bindings, binding) =>
            return Some((node.binding(), binding))
          _ => ()
        }
      }
    }
  }
  None
}

///|
fn source_line_delete_end(source : String, end : Int) -> Int {
  if end >= source.length() {
    end
  } else if source[end] == '\r' {
    if end + 1 < source.length() && source[end + 1] == '\n' {
      end + 2
    } else {
      end + 1
    }
  } else if source[end] == '\n' {
    end + 1
  } else {
    end
  }
}

///|
fn previous_line_break_start(source : String, start : Int) -> Int {
  if start >= 2 && source[start - 2] == '\r' && source[start - 1] == '\n' {
    start - 2
  } else if start >= 1 &&
    (source[start - 1] == '\n' || source[start - 1] == '\r') {
    start - 1
  } else {
    start
  }
}

///|
fn deletion_span_for_graph_node(
  source : String,
  node : @graph_dsl.GraphNode,
) -> SourceDeletionSpan {
  { start: node.start(), end: source_line_delete_end(source, node.end()) }
}

///|
fn compare_deletion_span_start(
  a : SourceDeletionSpan,
  b : SourceDeletionSpan,
) -> Int {
  if a.start < b.start {
    -1
  } else if a.start > b.start {
    1
  } else if a.end < b.end {
    -1
  } else if a.end > b.end {
    1
  } else {
    0
  }
}

///|
fn compare_deletion_span_start_desc(
  a : SourceDeletionSpan,
  b : SourceDeletionSpan,
) -> Int {
  0 - compare_deletion_span_start(a, b)
}

///|
fn merged_deletion_spans(
  source : String,
  spans : Array[SourceDeletionSpan],
) -> Array[SourceDeletionSpan] {
  let ordered = spans.copy()
  ordered.sort_by(compare_deletion_span_start)
  let merged : Array[SourceDeletionSpan] = []
  for span in ordered {
    if merged.length() == 0 {
      merged.push(span)
    } else {
      let last_index = merged.length() - 1
      let last = merged[last_index]
      if span.start <= last.end {
        if span.end > last.end {
          merged[last_index] = { ..last, end: span.end }
        }
      } else {
        merged.push(span)
      }
    }
  }
  let adjusted : Array[SourceDeletionSpan] = []
  for span in merged {
    let start = if span.end == source.length() {
      previous_line_break_start(source, span.start)
    } else {
      span.start
    }
    adjusted.push({ ..span, start, })
  }
  adjusted
}

///|
fn apply_deletion_spans(
  source : String,
  spans : Array[SourceDeletionSpan],
) -> String? {
  let ordered = spans.copy()
  ordered.sort_by(compare_deletion_span_start_desc)
  let source_len = source.length()
  let mut next_start = source_len
  let mut result = source
  for span in ordered {
    if span.start < 0 ||
      span.end < span.start ||
      span.end > source_len ||
      span.end > next_start {
      return None
    }
    result = result[:span.start].to_owned() + result[span.end:].to_owned()
    next_start = span.start
  }
  Some(result)
}

///|
fn lower_delete_node_bindings(
  doc : @graph_dsl.GraphDoc,
  bindings : Array[String],
) -> Result[String, String] {
  match survivor_reference_to_deleted_binding(doc, bindings) {
    Some((survivor, deleted)) =>
      return Err(
        "cannot lower DeleteNodes: survivor '" +
        survivor +
        "' still references deleted binding '" +
        deleted +
        "'",
      )
    None => ()
  }
  let source = doc.source()
  let spans : Array[SourceDeletionSpan] = []
  for binding in bindings {
    match doc.find_node(binding) {
      Some(node) => spans.push(deletion_span_for_graph_node(source, node))
      None =>
        return Err(
          "cannot lower DeleteNodes: missing binding '" + binding + "'",
        )
    }
  }
  match apply_deletion_spans(source, merged_deletion_spans(source, spans)) {
    Some(new_source) => Ok(new_source)
    None => Err("cannot lower DeleteNodes into source")
  }
}

///|
fn lower_delete_nodes(
  doc : @graph_dsl.GraphDoc,
  node_ids : Array[NodeId],
) -> Result[SourceOperationEdit, String] {
  let bindings = match deleted_bindings_for_canvas_ids(doc, node_ids) {
    Ok(bindings) => bindings
    Err(message) => return Err(message)
  }
  match lower_delete_node_bindings(doc, bindings) {
    Ok(new_source) => Ok(WholeSourceReplacement(new_source))
    Err(message) => Err(message)
  }
}
