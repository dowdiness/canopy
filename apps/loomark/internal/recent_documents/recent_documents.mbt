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
struct Seed {
  docid : String
  source : String
  selection : Selection
  deletion : DeletionAvailability
  status : RowStatus
} derive(Eq)

///|
pub fn Seed::Seed(
  docid~ : String,
  source~ : String,
  selection~ : Selection,
  deletion~ : DeletionAvailability,
  status~ : RowStatus,
) -> Seed {
  { docid, source, selection, deletion, status, }
}

///|
pub fn Seed::docid(self : Seed) -> String {
  self.docid
}

///|
pub fn Seed::source(self : Seed) -> String {
  self.source
}

///|
pub fn Seed::deletion(self : Seed) -> DeletionAvailability {
  self.deletion
}

///|
pub fn Seed::selection(self : Seed) -> Selection {
  self.selection
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
  lead : @document_lead.DocumentLead
} derive(Eq)

///|
priv struct PresentedRow {
  row : Row
  ordinal : (Int, Int)?
} derive(Eq)

///|
fn row_base_label(row : Row) -> String {
  if row.lead.primary() == "" {
    "Empty document"
  } else {
    row.lead.primary()
  }
}

///|
fn rows_presented(rows : @vector.Vector[Row]) -> @vector.Vector[PresentedRow] {
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
fn row_label(row : PresentedRow) -> String {
  let base = row_base_label(row.row)
  match row.ordinal {
    Some((number, total)) => "\{base} (\{number} of \{total})"
    None => base
  }
}

///|
fn delete_confirmation_label(row : PresentedRow) -> String {
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
fn action_menu(
  key : String,
  deletion : DeletionAvailability,
  emit : @cmd.Emit[Intent],
) -> @rabbita.Val[@html.Html] {
  let can_delete = match deletion {
    Available | Failed => true
    Blocked | Pending => false
  }
  @rui.dropdown_menu(id="loomark-document-actions-\{key}", scope => {
    @html.fragment([
      @rui.dropdown_menu_trigger(
        scope,
        aria_label="Actions for document",
        title="Actions",
        class="loomark-document-actions",
        style=["height:2rem;min-height:2rem;padding:0 .5rem"],
        "Actions",
      ),
      @rui.dropdown_menu_portal([
        @rui.dropdown_menu_content(scope, align=@rui.End, [
          @rui.dropdown_menu_item(
            scope,
            disabled=!can_delete,
            destructive=true,
            on_select=if can_delete {
              emit(Intent::RequestDelete(key))
            } else {
              @cmd.none
            },
            "Delete",
          ),
        ]),
      ]),
    ])
  })
}

///|
fn render_row(
  key : String,
  presented : PresentedRow,
  emit : @cmd.Emit[Intent],
  close : @cmd.Cmd,
  menu : @html.Html,
) -> @html.Html {
  let row = presented.row
  let seed = row.seed
  let label = row_label(presented)
  let description_id = "loomark-document-description-\{key}"
  let attrs = @html.Attrs::build()
  let children = [
    @html.span(
      class=if row.lead.form() is @document_lead.DocumentLeadForm::Code {
        "overflow-hidden whitespace-pre-wrap break-words bg-lm-foundation px-1 font-lm-mono text-xs [display:-webkit-box] [-webkit-box-orient:vertical] [-webkit-line-clamp:2]"
      } else {
        "overflow-hidden whitespace-pre-wrap break-words [display:-webkit-box] [-webkit-box-orient:vertical] [-webkit-line-clamp:2]"
      },
      row.lead.primary(),
    ),
  ]
  if row.lead.description() != "" {
    children.push(
      @html.span(
        id=description_id,
        class="mt-1 overflow-hidden whitespace-pre-wrap break-words text-xs leading-5 text-lm-muted [display:-webkit-box] [-webkit-box-orient:vertical] [-webkit-line-clamp:2]",
        row.lead.description(),
      ),
    )
    ignore(attrs.aria_describedby(description_id))
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
    menu,
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
      let source = seed.map(seed => seed.source)
      let lead = source.map(@document_lead.extract)
      seed.map2(lead, (seed, lead) => { seed, lead, })
    },
    by=seed => seed.docid,
  )
  let content = visible.switch_by(
    visible => {
      if visible {
        let presented = rows.map(rows_presented)
        presented
        .assoc_by(
          (key, row) => {
            let deletion = row.map(row => row.row.seed.deletion)
            let menu = deletion.switch_by(
              deletion => action_menu(key, deletion, on_intent),
              by=deletion => {
                match deletion {
                  Available | Failed => "allowed"
                  Blocked | Pending => "blocked"
                }
              },
            )
            row
            .map2(compact, (row, compact) => (row, compact))
            .map2(menu, (pair, menu) => {
              render_row(
                key,
                pair.0,
                on_intent,
                if pair.1 {
                  close_after_action
                } else {
                  @cmd.none
                },
                menu,
              )
            })
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
        None => @rabbita.Val::constant(@html.nothing)
        Some(id) => {
          let presented = rows.map(rows_presented)
          let candidate = presented.map(rows => {
            rows.iter().find_first(row => row.row.seed.docid == id)
          })
          candidate.switch_by(
            row => {
              match row {
                None => @rabbita.Val::constant(@html.nothing)
                Some(row) =>
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
                            @rui.alert_dialog_title(
                              scope,
                              delete_confirmation_label(row),
                            ),
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
            },
            by=row => if row is Some(_) { "available" } else { "unavailable" },
          )
        }
      }
    },
    by=target => {
      match target {
        Some(id) => "confirm-\{id}"
        None => "closed"
      }
    },
  )
  { navigation, dialog, }
}
