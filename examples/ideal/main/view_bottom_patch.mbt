///|
/// Shows the kind tag and the actual source text at the affected position.
fn format_structured_change(
  c : @canopy_core.StructuredChange,
  source_map : @canopy_core.SourceMap,
  source_text : String,
) -> String {
  fn snippet(node_id : @canopy_core.NodeId) -> String {
    match source_map.get_range(node_id) {
      Some(r) => source_text[r.start:r.end].to_owned()
      None => ""
    }
  }
  fn truncate(s : String) -> String {
    if s.length() > 60 {
      s[0:60].to_owned() + "..."
    } else {
      s
    }
  }
  fn format_kind_change(
    prefix : String,
    kind_tag : String,
    node_id : @canopy_core.NodeId,
  ) -> String {
    let s = snippet(node_id)
    if s.is_empty() {
      prefix + " " + kind_tag
    } else {
      prefix + " " + kind_tag + " '" + truncate(s) + "'"
    }
  }
  match c {
    @canopy_core.Inserted(_, _, node_id, kind_tag) =>
      format_kind_change("+", kind_tag, node_id)
    @canopy_core.Deleted(_, _, node_id, kind_tag) =>
      format_kind_change("-", kind_tag, node_id)
    @canopy_core.Wrapped(inner_id, wrapper_node_id, wrapper_kind) => {
      let s = snippet(wrapper_node_id)
      let s = if s.is_empty() { snippet(inner_id) } else { s }
      if s.is_empty() {
        "⊞ " + wrapper_kind
      } else {
        "⊞ " + wrapper_kind + " '" + truncate(s) + "'"
      }
    }
    @canopy_core.Unwrapped(wrapper_id, _, wrapper_kind) => {
      let s = snippet(wrapper_id)
      if s.is_empty() {
        "⊟ " + wrapper_kind
      } else {
        "⊟ " + wrapper_kind + " '" + truncate(s) + "'"
      }
    }
    @canopy_core.Renamed(node_id, kind_tag) =>
      format_kind_change("→", kind_tag, node_id)
    @canopy_core.Freshened(_, _, node_id, kind_tag) =>
      format_kind_change("~", kind_tag, node_id)
  }
}

///|
/// Render the Patch panel — paired (op label, SpanEdits) rows.
/// Mirrors `view_op_log` shape: most-recent first, capped to MAX_PATCH_LOG.
/// Each entry surfaces the producing `GenericTreeOp` label as a header row
/// so the user can cross-reference the matching Op Log entry, then each
/// `SpanEdit` renders via its `Show` impl (`@<start> -<delete_len> +«…»`).
/// Per-entry `changes` are rendered in a `<details>` block within each row.
fn view_patch_log(model : Model) -> Html {
  // See `view_op_log` for the rationale; Patch panel rows are heavier
  // (header + N `SpanEdit` rows per entry), so guarding here matters more.
  if !model.workspace.bottom_visible {
    return @html.div(
      class="bottom-content",
      attrs=bottom_panel_attrs(Patch),
      ([] : Array[Html]),
    )
  }
  let log = model.patch_log
  let source_map = model.editor.get_source_map()
  let source_text = model.editor.get_text()
  if log.is_empty() {
    @html.div(class="bottom-content", attrs=bottom_panel_attrs(Patch), [
      @html.span(class="no-problems", [
        @html.text(
          "No patches yet. Structure-mode edits aren't traced here — see the Op Log tab.",
        ),
      ]),
    ])
  } else {
    let n = log.length()
    let items : Array[Html] = Array::makei(n, i => {
      let entry = log[n - 1 - i]
      let edit_rows : Array[Html] = entry.edits.map(edit => {
        @html.div(class="patch-log-edit", [
          @html.span(class="patch-log-edit-text", [@html.text(edit.to_string())]),
        ])
      })
      let change_rows : Array[Html] = entry.changes.map(c => {
        @html.div(class="patch-structural-change", [
          @html.span(class="patch-change-text", [
            @html.text(format_structured_change(c, source_map, source_text)),
          ]),
        ])
      })
      let structural_details : Array[Html] = if change_rows.is_empty() {
        []
      } else {
        [
          @html.node(
            "details",
            @html.Attrs::build().class("patch-structural-details"),
            [
              @html.node("summary", @html.Attrs::build(), [
                @html.text("Structural changes"),
              ]),
              @html.div(class="patch-structural-body", change_rows),
            ],
          ),
        ]
      }
      @html.div(
        class="patch-log-row",
        [
          @html.div(class="patch-log-header", [
            @html.span(class="patch-log-index", [@html.text("\{n - i}.")]),
            @html.span(class="patch-log-op", [@html.text(entry.op_label)]),
          ]),
          @html.div(class="patch-log-edits", edit_rows),
        ] +
        structural_details,
      )
    })
    @html.div(
      class="bottom-content patch-log",
      attrs=bottom_panel_attrs(Patch),
      items,
    )
  }
}

///|
