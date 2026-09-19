///|
/// Presentation state resolved by the app; extraction is owned by this feature.
pub(all) enum Selection {
  Editing
  Selectable
  Blocked
} derive(Eq)

///|
pub(all) enum RowStatus {
  Saved
  Unsaved
} derive(Eq)

///|
/// Whether deletion is currently available for a document row.
pub(all) enum DeletionAvailability {
  Available
  Blocked
  Pending
  Failed
} derive(Eq)

///|
struct Seed[Id] {
  docid : Id
  source : String
  selection : Selection
  deletion : DeletionAvailability
  status : RowStatus
} derive(Eq)

///|
pub fn[Id] Seed::Seed(
  docid~ : Id,
  source~ : String,
  selection~ : Selection,
  deletion~ : DeletionAvailability,
  status~ : RowStatus,
) -> Seed[Id] {
  { docid, source, selection, deletion, status, }
}

///|
pub fn[Id] Seed::docid(self : Seed[Id]) -> Id {
  self.docid
}

///|
pub fn[Id] Seed::source(self : Seed[Id]) -> String {
  self.source
}

///|
pub fn[Id] Seed::deletion(self : Seed[Id]) -> DeletionAvailability {
  self.deletion
}

///|
pub fn[Id] Seed::selection(self : Seed[Id]) -> Selection {
  self.selection
}

///|
pub enum Intent[Id] {
  Create
  Select(Id)
  RequestDelete(Id)
  CancelDelete
  ConfirmDelete(Id)
}

///|
priv struct Row[Id] {
  seed : Seed[Id]
  lead : @document_lead.DocumentLead
} derive(Eq)

///|
priv struct PresentedRow[Id] {
  row : Row[Id]
  ordinal : (Int, Int)?
} derive(Eq)

///|
fn[Id] row_base_label(row : Row[Id]) -> String {
  if row.lead.primary() == "" {
    "Empty document"
  } else {
    row.lead.primary()
  }
}

///|
fn[Id] rows_presented(
  rows : @vector.Vector[Row[Id]],
) -> @vector.Vector[PresentedRow[Id]] {
  let values = rows.to_array()
  @vector.Vector(
    values.mapi((index, row) => {
      let base = row_base_label(row)
      let total = values.count_if(other => row_base_label(other) == base)
      let ordinal = if total == 1 {
        None
      } else {
        Some(
          (
            values
            .view(end=index + 1)
            .count_if(other => row_base_label(other) == base),
            total,
          ),
        )
      }
      { row, ordinal, }
    })[:],
  )
}

///|
fn[Id] row_label(row : PresentedRow[Id]) -> String {
  let base = row_base_label(row.row)
  match row.ordinal {
    Some((number, total)) => "\{base} (\{number} of \{total})"
    None => base
  }
}

///|
fn[Id] delete_confirmation_label(row : PresentedRow[Id]) -> String {
  "Delete \"\{row_label(row)}\"?"
}

///|
fn status_view(
  status : RowStatus,
  deletion : DeletionAvailability,
) -> @html.Html {
  match deletion {
    Pending =>
      @html.span(
        class="block text-xs text-lm-muted",
        attrs=@html.Attrs::build().role("status"),
        "Deleting",
      )
    Failed =>
      @html.span(
        class="block text-xs text-lm-muted",
        attrs=@html.Attrs::build().role("status"),
        "Delete failed",
      )
    Available | Blocked =>
      match status {
        Saved => @html.nothing
        Unsaved =>
          @html.span(
            class="i-lucide-alert-circle ml-1 inline-block size-3.5 align-[-0.15em] text-lm-muted",
            attrs=@html.Attrs::build().role("img").aria_label("Not saved"),
            @html.nothing,
          )
      }
  }
}

///|
fn[Id] render_row(
  key : Id,
  presented : PresentedRow[Id],
  emit : @cmd.Emit[Intent[Id]],
  close : @cmd.Cmd,
) -> @html.Html {
  let row = presented.row
  let seed = row.seed
  let label = row_label(presented)
  let attrs = @html.Attrs::build()
  let children = [
    @html.div(
      class=if row.lead.form() is @document_lead.DocumentLeadForm::Code {
        "overflow-hidden whitespace-pre-wrap break-words bg-lm-foundation px-1 font-lm-mono text-xs leading-5 [display:-webkit-box] [-webkit-box-orient:vertical] [-webkit-line-clamp:2]"
      } else {
        "overflow-hidden whitespace-pre-wrap break-words text-sm leading-5 font-semibold text-lm-ink [display:-webkit-box] [-webkit-box-orient:vertical] [-webkit-line-clamp:2]"
      },
      row.lead.primary(),
    ),
  ]
  if row.lead.description() != "" {
    children.push(
      @html.div(
        class="mt-1 overflow-hidden whitespace-pre-wrap break-words text-xs leading-5 text-lm-muted [display:-webkit-box] [-webkit-box-orient:vertical] [-webkit-line-clamp:2]",
        row.lead.description(),
      ),
    )
    ignore(attrs.aria_description(row.lead.description()))
  }
  children.push(status_view(seed.status, seed.deletion))
  @sidebar.sidebar_menu_item([
    @sidebar.sidebar_menu_button(
      is_active=seed.selection is Selection::Editing,
      disabled=seed.selection is Selection::Blocked,
      aria_label=label,
      title=label,
      attrs~,
      class="loomark-document-row active:opacity-50",
      on_click=if seed.selection is Selection::Editing {
        @cmd.none
      } else {
        @cmd.batch([emit(Intent::Select(key)), close])
      },
      style=[
        "height:auto;min-height:2.5rem;align-items:flex-start;padding-block:0.5rem;padding-inline-end:2.5rem",
      ],
      @html.div(class="min-w-0", children),
    ),
    @sidebar.sidebar_menu_action(
      disabled=match seed.deletion {
        Available | Failed => false
        Blocked | Pending => true
      },
      aria_label="Delete \"\{label}\"",
      title="Delete \"\{label}\"",
      class="loomark-sidebar-action loomark-delete-action",
      style=["width:2rem;height:2rem"],
      on_click=emit(Intent::RequestDelete(key)),
      @view.trash_icon(),
    ),
  ])
}

///|
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
fn[Id : Eq] row_component(
  seed : @rabbita.Val[Seed[Id]],
) -> @rabbita.Val[Row[Id]] {
  let source = seed.map(seed => seed.source)
  let lead = source.map(@document_lead.extract)
  seed.map2(lead, (seed, lead) => { seed, lead, })
}

///|
fn[Id : Eq] presented_row_component(
  key : Id,
  row : @rabbita.Val[PresentedRow[Id]],
  compact : @rabbita.Val[Bool],
  on_intent : @cmd.Emit[Intent[Id]],
  close_after_action : @cmd.Cmd,
) -> @rabbita.Val[@html.Html] {
  row.map2(compact, (row, compact) => {
    render_row(
      key,
      row,
      on_intent,
      if compact {
        close_after_action
      } else {
        @cmd.none
      },
    )
  })
}

///|
fn[Id : Eq + Hash] visible_documents(
  rows : @rabbita.Val[@vector.Vector[Row[Id]]],
  compact : @rabbita.Val[Bool],
  on_intent : @cmd.Emit[Intent[Id]],
  close_after_action : @cmd.Cmd,
) -> @rabbita.Val[@html.Html] {
  let presented = rows.map(rows_presented)
  presented
  .assoc_by(
    (key, row) => {
      presented_row_component(key, row, compact, on_intent, close_after_action)
    },
    by=row => row.row.seed.docid,
  )
  .view(rows => {
    if rows.is_empty() {
      @html.div(
        class="px-3 py-6 text-sm text-lm-muted",
        attrs=@html.Attrs::build().role("status"),
        "No documents yet",
      )
    } else {
      @sidebar.sidebar_menu(rows.to_array())
    }
  })
}

///|
fn empty_component() -> @rabbita.Val[@html.Html] {
  @rabbita.Val::constant(@html.nothing)
}

///|
fn[Id] available_delete_dialog(
  id : Id,
  row : PresentedRow[Id],
  on_intent : @cmd.Emit[Intent[Id]],
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
            @rui.alert_dialog_title(scope, delete_confirmation_label(row)),
          ]),
          @rui.alert_dialog_footer([
            @rui.alert_dialog_cancel(scope, "Cancel"),
            @rui.alert_dialog_action(
              scope,
              on_click=on_intent(Intent::ConfirmDelete(id)),
              "Delete document",
            ),
          ]),
        ]),
      ])
    },
  )
}

///|
fn[Id : Eq] delete_dialog(
  id : Id,
  rows : @rabbita.Val[@vector.Vector[Row[Id]]],
  on_intent : @cmd.Emit[Intent[Id]],
) -> @rabbita.Val[@html.Html] {
  let candidate = rows
    .map(rows_presented)
    .map(rows => rows.iter().find_first(row => row.row.seed.docid == id))
  candidate.switch_by(
    candidate => {
      match candidate {
        Some(row) => available_delete_dialog(id, row, on_intent)
        None => empty_component()
      }
    },
    by=candidate => {
      match candidate {
        Some(row) => "available-\{delete_confirmation_label(row)}"
        None => "unavailable"
      }
    },
  )
}

///|
pub fn[Id : Eq + Hash] build(
  input~ : @rabbita.Val[@vector.Vector[Seed[Id]]],
  visible~ : @rabbita.Val[Bool],
  can_create~ : @rabbita.Val[Bool],
  compact~ : @rabbita.Val[Bool],
  delete_target~ : @rabbita.Val[Id?],
  on_intent~ : @cmd.Emit[Intent[Id]],
  lifecycle_key~ : (Id) -> String,
  close_after_action~ : @cmd.Cmd,
) -> RecentDocumentsFeature {
  let rows = input.assoc_by((_, seed) => row_component(seed), by=seed => {
    seed.docid
  })
  let content = visible.switch_by(
    visible => {
      if visible {
        visible_documents(rows, compact, on_intent, close_after_action)
      } else {
        empty_component()
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
          class="loomark-new-document",
          style=[
            "width:auto;height:2rem;justify-content:center;padding:0 .5rem",
          ],
          on_click=@cmd.batch([
            on_intent(Intent::Create),
            if compact {
              close_after_action
            } else {
              @cmd.none
            },
          ]),
          "New",
        ),
      ),
      @sidebar.sidebar_content(
        @sidebar.sidebar_group(@sidebar.sidebar_group_content(content)),
      ),
    ])
  })
  let dialog = delete_target.switch_by(
    target => {
      match target {
        None => empty_component()
        Some(id) => delete_dialog(id, rows, on_intent)
      }
    },
    by=target => {
      match target {
        Some(id) => "confirm-\{lifecycle_key(id)}"
        None => "closed"
      }
    },
  )
  { navigation, dialog, }
}
