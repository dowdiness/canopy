///|
fn mode_name(mode : EditorMode) -> String {
  match mode {
    Text => "Text"
    Preview => "Preview"
    Split => "Split"
  }
}

///|
fn mode_dom_id(mode : EditorMode) -> String {
  "loomark-mode-\{mode_name(mode).to_lower()}"
}

///|
fn mode_tab(
  mode : EditorMode,
  selected_mode : EditorMode,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Html {
  let name = mode_name(mode)
  let icon_class = match mode {
    Text => "i-lucide-align-left"
    Preview => "i-lucide-eye"
    Split => "i-lucide-columns-2"
  }
  @rui.tabs_trigger(
    value=name.to_lower(),
    selected=mode == selected_mode,
    controls="loomark-editor-panel",
    id=mode_dom_id(mode),
    on_value_change=@cmd.Emit(_ => emit(ModeSelected(mode))),
    title=name,
    class="group",
    attrs=@html.Attrs::build().aria_label(name),
    style=["width:2rem;height:2rem;min-height:2rem;flex:none;padding:0"],
    @html.span(
      class="pointer-events-none block size-4.5 \{icon_class} transition-colors duration-150 group-hover:text-[oklch(0.145_0_0)]",
      attrs=@html.Attrs::build().aria_hidden("true"),
      @html.nothing,
    ),
  )
}

///|
fn mode_content(mode : EditorMode, content : @rabbita.Html) -> @rabbita.Html {
  @rui.tabs_content(
    value=mode_name(mode).to_lower(),
    selected=true,
    labelledby=mode_dom_id(mode),
    id="loomark-editor-panel",
    class="min-h-0 min-w-0 flex-1 flex-col overflow-hidden",
    style=["display:flex"],
    content,
  )
}

///|
fn document_base_label(entry : @source_repository.CatalogEntry) -> String {
  entry.name().unwrap_or("Unnamed document")
}

///|
fn document_option_label(
  entries : ArrayView[@source_repository.CatalogEntry],
  index : Int,
  entry : @source_repository.CatalogEntry,
) -> String {
  let base = document_base_label(entry)
  let total = entries.count_if(other => document_base_label(other) == base)
  if total == 1 {
    base
  } else {
    let ordinal = entries
      .view(end=index + 1)
      .count_if(other => document_base_label(other) == base)
    "\{base} (\{ordinal} of \{total})"
  }
}

///|
fn recent_entries(
  editing : EditingState,
) -> Array[@source_repository.CatalogEntry] {
  let persisted = editing.documents.snapshot().catalog().entries()
  let entries = editing.documents
    .current_sources()
    .filter_map(source => {
      let document_id = source.document_id()
      let persisted_entry = match
        persisted.search_by(entry => entry.document_id() == document_id) {
        Some(index) => persisted.get(index)
        None => None
      }
      let visible = persisted_entry is Some(_) ||
        source.text() != "" ||
        source.change_order().value() > 0L
      if visible {
        @source_repository.CatalogEntry::new(
          document_id,
          match persisted_entry {
            Some(entry) => entry.name()
            None => None
          },
          change_order=source.change_order(),
        )
      } else {
        None
      }
    })
  @source_repository.Catalog::from_entries(entries)
  .unwrap()
  .entries()
  .to_owned()
}

///|
fn document_sidebar(
  scope : @sidebar.SidebarScope,
  editing : EditingState,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Html {
  let available = can_activate(editing)
  let entry_values = recent_entries(editing)
  let entries = entry_values.view()
  let compact = editing.compact
  let close_after_action = if compact {
    @sidebar.sidebar_collapse(scope)
  } else {
    @cmd.none
  }
  @sidebar.sidebar(
    scope,
    id="loomark-document-sidebar",
    mobile=false,
    side=@sidebar.SidebarLeft,
    variant=@sidebar.SidebarDefault,
    collapsible=@sidebar.SidebarIcon,
    aria_label="Documents",
    class="[--rui-sidebar:var(--color-lm-foundation)] [--rui-sidebar-foreground:var(--color-lm-ink)] [--rui-sidebar-border:var(--color-lm-rule)] [--rui-sidebar-accent:var(--color-lm-accent-soft)] [--rui-sidebar-accent-foreground:var(--color-lm-accent)]",
    @sidebar.sidebar_content(
      @sidebar.sidebar_group(
        @sidebar.sidebar_group_content(
          @sidebar.sidebar_menu(
            @sidebar.sidebar_menu_item([
              @sidebar.sidebar_menu_button(
                aria_label="Documents",
                title="Documents",
                class="hover:opacity-70 active:opacity-50",
                on_click=if @sidebar.sidebar_is_collapsed(scope) {
                  @sidebar.sidebar_expand(scope)
                } else {
                  @sidebar.sidebar_collapse(scope)
                },
                [folder_icon(), @html.span("Documents")],
              ),
              @sidebar.sidebar_menu_action(
                disabled=!available,
                aria_label="New document",
                title="New document",
                class="loomark-sidebar-action",
                style=["width:2rem;height:2rem"],
                on_click=@cmd.batch([emit(CreateRequested), close_after_action]),
                plus_icon(),
              ),
              @sidebar.sidebar_menu_sub(
                entries.mapi((index, entry) => {
                  let document_id = entry.document_id()
                  let selected = document_id == editing.activation.document_id
                  let label = document_option_label(entries, index, entry)
                  let (target_available, status) = match
                    editing.documents.delete_status(document_id) {
                    Some(Available) => (true, None)
                    Some(Failed(_, _)) => (true, Some("Delete failed"))
                    Some(Waiting(_)) | Some(Deleting(_)) | Some(Probing(_)) =>
                      (false, Some("Deleting"))
                    Some(Unknown(_)) =>
                      (false, Some("Unknown deletion outcome"))
                    None => (false, None)
                  }
                  @sidebar.sidebar_menu_sub_item([
                    @sidebar.sidebar_menu_sub_button(
                      is_active=selected,
                      disabled=!can_select(editing, document_id),
                      aria_label=label,
                      title=label,
                      class="pr-10 hover:opacity-70 active:opacity-50",
                      on_click=@cmd.batch([
                        emit(DocumentSelected(document_id)),
                        close_after_action,
                      ]),
                      style=[
                        "height:auto;min-height:2.5rem;align-items:flex-start;padding-block:0.5rem",
                      ],
                      @html.div(class="min-w-0", [
                        @html.span(
                          class="overflow-hidden text-ellipsis whitespace-normal [display:-webkit-box] [-webkit-box-orient:vertical] [-webkit-line-clamp:2]",
                          label,
                        ),
                        match status {
                          Some(status) =>
                            @html.span(
                              class="block text-xs text-lm-muted",
                              attrs=@html.Attrs::build().role("status"),
                              status,
                            )
                          None => @html.nothing
                        },
                      ]),
                    ),
                    @sidebar.sidebar_menu_action(
                      disabled=!target_available,
                      aria_label="Delete \"\{label}\"",
                      title="Delete \"\{label}\"",
                      class="loomark-sidebar-action loomark-delete-action",
                      style=["width:2rem;height:2rem"],
                      on_click=emit(DeleteRequested(document_id)),
                      trash_icon(),
                    ),
                  ])
                }),
              ),
            ]),
          ),
        ),
      ),
    ),
  )
}

///|
fn mode_bar(
  scope : @sidebar.SidebarScope,
  editing : EditingState,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Html {
  @html.header(
    class="relative z-2 flex min-h-11 shrink-0 flex-wrap items-center justify-between gap-2 border-b border-lm-rule bg-lm-surface px-3 py-1 max-[641px]:px-2 max-[641px]:py-0",
    [
      @html.div(class="flex min-w-0 items-center gap-2", [
        @sidebar.sidebar_trigger(
          scope,
          mobile=false,
          controls="loomark-document-sidebar",
          aria_label="Toggle documents",
          class="active:opacity-50",
          panel_icon(),
        ),
        @rui.tabs_root(
          value=mode_name(editing.mode).to_lower(),
          style=["width:auto"],
          @rui.tabs_list(
            orientation=@rui.TabsHorizontal,
            variant=@rui.TabsDefault,
            aria_label="Editor mode",
            [
              mode_tab(Text, editing.mode, emit),
              mode_tab(Preview, editing.mode, emit),
              mode_tab(Split, editing.mode, emit),
            ],
          ),
        ),
      ]),
      @html.div(class="flex min-w-0 items-center gap-1", [
        examples_bar(
          emit,
          editing.activation,
          disabled=editing.creation == Creating,
        ),
        @html.label(
          class="relative flex min-h-8 shrink-0 cursor-pointer items-center rounded-md border border-lm-rule bg-transparent px-2 py-1 text-xs text-lm-muted transition-colors duration-150 hover:bg-[oklch(0.955_0.003_255)] hover:text-lm-ink has-[:focus-visible]:outline-2 has-[:focus-visible]:outline-offset-1 has-[:focus-visible]:outline-lm-accent max-[641px]:min-h-11",
          title="Import Markdown",
          for_="loomark-import",
          [
            @html.text("Import"),
            @html.input(
              input_type=File,
              id="loomark-import",
              class="absolute inset-0 cursor-pointer opacity-0",
              on_files=emit.map(files => ImportFilesSelected(files)),
              attrs=@html.Attrs::build().aria_label("Import Markdown"),
            ),
          ],
        ),
        @html.button(
          type_="button",
          class="min-h-8 shrink-0 cursor-pointer rounded-md border border-lm-rule bg-transparent px-2 py-1 text-xs text-lm-muted transition-colors duration-150 hover:bg-[oklch(0.955_0.003_255)] hover:text-lm-ink focus-visible:outline-2 focus-visible:outline-offset-1 focus-visible:outline-lm-accent max-[641px]:min-h-11",
          title="Export Markdown",
          attrs=@html.Attrs::build().aria_label("Export Markdown"),
          on_click=emit(ExportRequested),
          "Export",
        ),
      ]),
    ],
  )
}

///|
fn text_area_view(
  emit : @rabbita.Emit[Msg],
  text_area : @text_area.TextArea,
  activation : Activation,
  disabled? : Bool,
  read_only? : Bool,
) -> @rabbita.Html {
  @html.div(
    class="h-full min-h-0 w-full min-w-0",
    Map([
      (
        "activation-\{activation.generation}",
        @html.textarea(
          rows=24,
          autofocus=true,
          disabled?,
          read_only?,
          class="m-0 block h-full min-h-0 w-full min-w-0 resize-none rounded-none border-0 bg-transparent px-[max(3rem,calc((100%_-_44rem)_/_2))] pt-8 pb-16 font-lm-mono text-base leading-[1.65] text-lm-ink caret-lm-accent outline-0 [tab-size:2] max-[641px]:px-3 max-[641px]:pt-6 max-[641px]:pb-12",
          attrs=text_area.attach(
            @html.Attrs::build().aria_label("Text"),
            change => emit(TextChanged(activation, change)),
            composing => {
              if composing {
                emit(CompositionStarted(activation))
              } else {
                emit(CompositionEnded(activation))
              }
            },
          ),
          @html.nothing,
        ),
      ),
    ]),
  )
}

///|
fn import_failure_view(emit : @rabbita.Emit[Msg]) -> @rabbita.Html {
  failure_notice(
    "The Markdown file could not be imported.",
    "Dismiss",
    emit(DismissImportFailure),
  )
}

///|
fn creation_failure_view(
  failure : @source_repository.CreateFailure,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Html {
  let reason = match failure {
    @source_repository.CreateFailure::DocumentIdentityUnavailable =>
      "This browser cannot create a document identity."
    @source_repository.CreateFailure::StorageUnavailable =>
      "Browser storage is unavailable."
    @source_repository.CreateFailure::QuotaExceeded =>
      "Browser storage is full."
    @source_repository.CreateFailure::WriteFailed =>
      "Browser storage failed while creating the document."
  }
  failure_notice(
    "A new document could not be created. " + reason,
    "Retry creating",
    emit(CreateRequested),
  )
}

///|
fn delete_failure_view(
  document_id : String,
  failure : @source_repository.DeleteFailure,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Html {
  let reason = match failure {
    InvalidSource => "The document is no longer available."
    StorageUnavailable => "Browser storage is unavailable."
    QuotaExceeded => "Browser storage is full."
    WriteFailed => "Browser storage failed while deleting the document."
  }
  @html.div(
    class="flex min-h-12 shrink-0 items-center justify-between gap-4 bg-lm-danger-soft px-4 py-2.5 text-sm text-lm-danger",
    attrs=@html.Attrs::build().role("alert"),
    [
      @html.p("The document was not deleted. " + reason),
      @html.div(class="flex shrink-0 gap-2", [
        @html.button(
          class="min-h-8 rounded-md border border-current px-2.5 py-1",
          on_click=emit(RetryDelete(document_id)),
          "Try again",
        ),
        @html.button(
          class="min-h-8 rounded-md border border-current px-2.5 py-1",
          on_click=emit(DismissDeleteFailure(document_id)),
          "Dismiss",
        ),
      ]),
    ],
  )
}

///|
fn save_failure_view(
  failure : @source_repository.SaveFailure,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Html {
  let reason = match failure {
    @source_repository.SaveFailure::InvalidSource =>
      " The document identity is invalid."
    @source_repository.SaveFailure::ChangeOrderExhausted =>
      " This browser has run out of change ordering space."
    @source_repository.SaveFailure::StorageUnavailable =>
      " Browser storage is unavailable."
    @source_repository.SaveFailure::QuotaExceeded => " Browser storage is full."
    @source_repository.SaveFailure::WriteFailed =>
      " Browser storage failed while writing the document."
  }
  failure_notice(
    "Changes are not saved in this browser." + reason,
    "Retry saving",
    emit(RetrySave),
  )
}

///|
fn view(
  sidebar : @sidebar.SidebarScope,
  model : Model,
  emit : @rabbita.Emit[Msg],
  editor_panels : @rabbita.Html,
  delete_dialog : @rabbita.Html,
) -> @rabbita.Html {
  @html.div(
    id="loomark-root",
    class="flex h-dvh min-h-0 w-full min-w-0 overflow-hidden bg-lm-foundation font-lm-ui text-lm-ink scheme-light selection:bg-[oklch(0.78_0.08_276/0.45)]",
    attrs=@html.Attrs::build()
      .role("region")
      .aria_label("Loomark Markdown Editor"),
    [
      match model {
        Loading(_) | PreparingNew(_) =>
          @html.div(
            class="grid min-h-dvh place-items-center text-lm-muted [&_p]:m-0",
            [@html.p("Loading document")],
          )
        Recovery(failure, _) => {
          let message = match failure {
            @source_repository.OpenFailure::StorageUnavailable =>
              "Browser storage is unavailable."
            @source_repository.OpenFailure::ReadFailed =>
              "Browser storage failed while reading the document."
            @source_repository.OpenFailure::DocumentIdentityUnavailable =>
              "This browser cannot create a document identity."
            @source_repository.OpenFailure::QuotaExceeded =>
              "Browser storage is full."
            @source_repository.OpenFailure::WriteFailed =>
              "Browser storage failed while preparing the document."
          }
          @html.div(
            class="mx-auto w-[min(calc(100%-2rem),36rem)] pt-[max(4rem,20vh)] pb-8 [&_h1]:mt-0 [&_h1]:mb-3 [&_h1]:text-xl [&_h1]:leading-[1.3] [&_p]:m-0 [&_p]:leading-[1.6] [&_p]:text-lm-muted",
            [@html.h1("Document recovery"), @html.p(message)],
          )
        }
        Editing(editing) =>
          @html.div(
            class="flex h-full min-h-0 min-w-0 flex-1 opacity-100 transition-opacity duration-[140ms] ease-[cubic-bezier(0.23,1,0.32,1)] starting:opacity-[0.92] motion-reduce:duration-[80ms] motion-reduce:ease-[ease]",
            [
              document_sidebar(sidebar, editing, emit),
              @html.div(
                class="flex h-full min-h-0 min-w-0 flex-1 flex-col overflow-hidden bg-lm-paper",
                [
                  mode_bar(sidebar, editing, emit),
                  mode_content(editing.mode, editor_panels),
                  match
                    (
                      editing.documents.save_status(
                        editing.activation.document_id,
                      ),
                      editing.creation,
                    ) {
                    (Some(Failed(failure)), _) =>
                      save_failure_view(failure, emit)
                    (_, CreationFailed(failure)) =>
                      creation_failure_view(failure, emit)
                    _ =>
                      match
                        editing.documents.delete_status(
                          editing.activation.document_id,
                        ) {
                        Some(Failed(operation, failure)) =>
                          delete_failure_view(
                            operation.document_id,
                            failure,
                            emit,
                          )
                        _ => @html.nothing
                      }
                  },
                  if editing.import_failed {
                    import_failure_view(emit)
                  } else {
                    @html.nothing
                  },
                ],
              ),
            ],
          )
      },
      delete_dialog,
    ],
  )
}
