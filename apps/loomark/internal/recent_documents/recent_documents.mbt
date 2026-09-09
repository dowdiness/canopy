///|
struct Seed {
  docid : String
  lead_source : String?
  selected : Bool
  can_select : Bool
  can_delete : Bool
  untouched_new : Bool
  compact : Bool
  status : String?
} derive(Eq)

///|
pub fn Seed::Seed(
  docid~ : String,
  lead_source~ : String?,
  selected~ : Bool,
  can_select~ : Bool,
  can_delete~ : Bool,
  untouched_new~ : Bool,
  compact~ : Bool,
  status~ : String?,
) -> Seed {
  {
    docid,
    lead_source,
    selected,
    can_select,
    can_delete,
    untouched_new,
    compact,
    status,
  }
}

///|
pub enum Intent {
  Create
  Select(String)
  RequestDelete(String)
  CancelDelete
  ConfirmDelete(String)
}

///|
priv struct Row {
  seed : Seed
  lead : @document_lead.DocumentLead?
} derive(Eq)

///|
priv struct PresentedRow {
  row : Row
  ordinal : (Int, Int)?
} derive(Eq)

///|
fn lead_for(source : String?) -> @document_lead.DocumentLead? {
  source.map(source => {
    @document_lead.extract(
      source,
      limits=@document_lead.DocumentLeadLimits::try_new(
        primary=80,
        description=160,
      ).unwrap(),
    )
  })
}

///|
fn task_mark(checked : Bool) -> @html.Html {
  @html.span(
    class=if checked {
      "i-lucide-square-check mr-1 inline-block size-3.5 align-[-0.15em]"
    } else {
      "i-lucide-square mr-1 inline-block size-3.5 align-[-0.15em]"
    },
    attrs=@html.Attrs::build()
      .role("img")
      .aria_label(if checked { "Completed task" } else { "Incomplete task" }),
    @html.nothing,
  )
}

///|
fn description_view(
  lead : @document_lead.DocumentLead,
  id : String,
) -> @html.Html {
  let description = lead.description()
  // Local HTML builder walks ordered provenance ranges, not Markdown text.
  let parts : Array[@html.Html] = []
  let mut cursor = 0
  for marker in lead.task_marker_ranges() {
    if marker.start() > cursor {
      parts.push(@html.text(description[cursor:marker.start()].to_owned()))
    }
    parts.push(task_mark(marker.checked()))
    cursor = marker.end()
  }
  if cursor < description.length() {
    parts.push(@html.text(description[cursor:].to_owned()))
  }
  @html.span(
    id~,
    class="mt-1 overflow-hidden whitespace-pre-wrap break-words text-xs leading-5 text-lm-muted [display:-webkit-box] [-webkit-box-orient:vertical] [-webkit-line-clamp:2]",
    parts,
  )
}

///|
fn row_base_label(seed : Seed, lead : @document_lead.DocumentLead?) -> String {
  match lead {
    Some(lead) =>
      if lead.primary() == "" {
        "Empty document"
      } else if lead.form() is @document_lead.Task(checked) {
        let state = if checked { "Completed task" } else { "Incomplete task" }
        "\{state} — \{lead.primary()}"
      } else {
        lead.primary()
      }
    None => if seed.untouched_new { "New document" } else { "Document" }
  }
}

///|
fn present_rows(rows : @vector.Vector[Row]) -> @vector.Vector[PresentedRow] {
  let values = rows.to_array()
  @vector.Vector(
    values.mapi((index, row) => {
      let base = row_base_label(row.seed, row.lead)
      let total = values.count_if(other => {
        row_base_label(other.seed, other.lead) == base
      })
      let ordinal = if total == 1 {
        None
      } else {
        Some(
          (
            values
            .view(end=index + 1)
            .count_if(other => row_base_label(other.seed, other.lead) == base),
            total,
          ),
        )
      }
      PresentedRow::{ row, ordinal }
    })[:],
  )
}

///|
fn row_label(row : PresentedRow) -> String {
  let base = row_base_label(row.row.seed, row.row.lead)
  match row.ordinal {
    Some((ordinal, total)) => "\{base} (\{ordinal} of \{total})"
    None => base
  }
}

///|
fn render_row(
  key : String,
  presented : PresentedRow,
  on_intent : @cmd.Emit[Intent],
  close : @cmd.Cmd,
) -> @html.Html {
  let row = presented.row
  let seed = row.seed
  let label = row_label(presented)
  let description_id = "loomark-document-description-\{key}"
  let primary = match row.lead {
    Some(lead) => {
      let contents = match lead.form() {
        @document_lead.Task(checked) =>
          [task_mark(checked), @html.text(lead.primary())]
        @document_lead.List(marker) =>
          [@html.text("\{marker} "), @html.text(lead.primary())]
        _ => [@html.text(lead.primary())]
      }
      @html.span(
        class=if lead.form() is @document_lead.Code {
          "overflow-hidden whitespace-pre-wrap break-words bg-lm-foundation px-1 font-lm-mono text-xs [display:-webkit-box] [-webkit-box-orient:vertical] [-webkit-line-clamp:2]"
        } else {
          "overflow-hidden whitespace-pre-wrap break-words [display:-webkit-box] [-webkit-box-orient:vertical] [-webkit-line-clamp:2]"
        },
        contents,
      )
    }
    None =>
      @html.span(
        class="overflow-hidden whitespace-normal [display:-webkit-box] [-webkit-box-orient:vertical] [-webkit-line-clamp:2]",
        label,
      )
  }
  let children = [primary]
  let attrs = @html.Attrs::build()
  match row.lead {
    Some(lead) if lead.description() != "" => {
      children.push(description_view(lead, description_id))
      ignore(attrs.aria_describedby(description_id))
    }
    _ => ()
  }
  match seed.status {
    Some(status) =>
      children.push(
        @html.span(
          class="block text-xs text-lm-muted",
          attrs=@html.Attrs::build().role("status"),
          status,
        ),
      )
    None => ()
  }
  @sidebar.sidebar_menu_item([
    @sidebar.sidebar_menu_button(
      is_active=seed.selected,
      disabled=!seed.can_select,
      aria_label=if seed.untouched_new {
        "\{label} — not yet written"
      } else {
        label
      },
      title=label,
      attrs~,
      class="loomark-document-row active:opacity-50",
      on_click=@cmd.batch([
        on_intent(Intent::Select(key)),
        if seed.compact {
          close
        } else {
          @cmd.none
        },
      ]),
      style=[
        "height:auto;min-height:2.5rem;align-items:flex-start;padding-block:0.5rem;padding-inline-end:2.5rem",
        if seed.selected {
          "opacity:1"
        } else {
          ""
        },
      ],
      @html.div(class="min-w-0", children),
    ),
    if seed.untouched_new {
      @html.nothing
    } else {
      @sidebar.sidebar_menu_action(
        disabled=!seed.can_delete || row.lead is None,
        aria_label="Delete \"\{label}\"",
        title="Delete \"\{label}\"",
        class="loomark-sidebar-action loomark-delete-action",
        style=["width:2rem;height:2rem"],
        on_click=on_intent(Intent::RequestDelete(key)),
        @html.span(
          class="i-lucide-trash-2",
          attrs=@html.Attrs::build().aria_hidden("true"),
          @html.nothing,
        ),
      )
    },
  ])
}

///|
fn can_open_delete_dialog(row : PresentedRow) -> Bool {
  row.row.lead is Some(_) && row.row.seed.can_delete
}

///|
fn delete_dialog_title(row : PresentedRow) -> String {
  "Delete \"\{row_label(row)}\"?"
}

///|
fn render_delete_dialog(
  document_id : String,
  row : PresentedRow,
  on_intent : @cmd.Emit[Intent],
) -> @rabbita.Val[@html.Html] {
  @rui.alert_dialog(
    id="loomark-delete-document",
    default_open=true,
    on_open_change=@cmd.Emit(open => {
      if open {
        @cmd.none
      } else {
        on_intent(Intent::CancelDelete)
      }
    }),
    scope => {
      @rui.alert_dialog_portal([
        @rui.alert_dialog_content(scope, [
          @rui.alert_dialog_header([
            @rui.alert_dialog_title(scope, delete_dialog_title(row)),
            @rui.alert_dialog_description(
              scope, "This permanently removes the document from this browser.",
            ),
          ]),
          @rui.alert_dialog_footer([
            @rui.alert_dialog_cancel(scope, "Cancel"),
            @rui.alert_dialog_action(
              scope,
              on_click=on_intent(Intent::ConfirmDelete(document_id)),
              class="[--rui-button-bg:var(--color-lm-danger)] [--rui-button-fg:white]",
              "Delete document",
            ),
          ]),
        ]),
      ])
    },
  )
}

///|
/// Pure keyed lead projection outlives disposable visible HTML rows.
pub struct RecentDocumentsFeature {
  priv navigation : @rabbita.Val[@html.Html]
  priv dialog : @rabbita.Val[@html.Html]
}

///|
pub fn RecentDocumentsFeature::navigation(
  self : Self,
) -> @rabbita.Val[@html.Html] {
  self.navigation
}

///|
pub fn RecentDocumentsFeature::dialog(self : Self) -> @rabbita.Val[@html.Html] {
  self.dialog
}

///|
pub fn build(
  input~ : @rabbita.Val[@vector.Vector[Seed]],
  visible~ : @rabbita.Val[Bool],
  can_create~ : @rabbita.Val[Bool],
  compact~ : @rabbita.Val[Bool],
  delete_target~ : @rabbita.Val[String?],
  on_intent~ : @cmd.Emit[Intent],
  close_after_action~ : @cmd.Cmd,
) -> RecentDocumentsFeature {
  let rows = input.assoc_by(
    (_, seed) => {
      let lead = seed.map(seed => seed.lead_source).map(lead_for)
      seed.map2(lead, (seed, lead) => Row::{ seed, lead })
    },
    by=seed => seed.docid,
  )
  let presented_rows = rows.map(present_rows)
  let content = visible.switch_by(
    visible => {
      if visible {
        presented_rows
        .assoc_by(
          (key, row) => {
            row.map(row => render_row(key, row, on_intent, close_after_action))
          },
          by=row => row.row.seed.docid,
        )
        .view(rows => @sidebar.sidebar_menu(rows.to_array()))
      } else {
        @rabbita.Val::constant(@html.nothing)
      }
    },
    by=visible => if visible { "visible" } else { "hidden" },
  )
  let navigation = can_create.map3(compact, content, (
    can_create,
    compact,
    content,
  ) => {
    @html.div(class="contents", [
      @sidebar.sidebar_header(
        style=["align-items:flex-end"],
        @sidebar.sidebar_menu_button(
          disabled=!can_create,
          aria_label="New document",
          title="New document",
          class="active:opacity-50",
          style=["width:2rem;height:2rem;justify-content:center;padding:0"],
          on_click=@cmd.batch([
            on_intent(Intent::Create),
            if compact {
              close_after_action
            } else {
              @cmd.none
            },
          ]),
          @view.plus_icon(),
        ),
      ),
      @sidebar.sidebar_content(
        style=[],
        @sidebar.sidebar_group(@sidebar.sidebar_group_content(content)),
      ),
    ])
  })
  let dialog = delete_target.switch_by(
    target => {
      match target {
        None => @rabbita.Val::constant(@html.nothing)
        Some(document_id) => {
          let candidate = presented_rows.map(rows => {
            rows
            .iter()
            .find_first(row => row.row.seed.docid == document_id)
            .filter(can_open_delete_dialog)
          })
          candidate.switch_by(
            candidate => {
              match candidate {
                Some(row) => render_delete_dialog(document_id, row, on_intent)
                None => @rabbita.Val::constant(@html.nothing)
              }
            },
            by=candidate => {
              match candidate {
                Some(_) => "available"
                None => "unavailable"
              }
            },
          )
        }
      }
    },
    by=target => {
      match target {
        Some(document_id) => "confirm-\{document_id}"
        None => "closed"
      }
    },
  )
  { navigation, dialog }
}
