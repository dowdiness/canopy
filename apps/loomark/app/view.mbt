///|
fn mode_name(mode : EditorMode) -> String {
  match mode {
    Text => "Text"
    Preview => "Preview"
    Split => "Split"
  }
}

///|
fn mode_tab(
  mode : EditorMode,
  selected_mode : EditorMode,
  focused_mode : EditorMode,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Html {
  let name = mode_name(mode)
  let selected = mode == selected_mode
  @html.button(
    id=mode_dom_id(mode),
    class=if selected {
      "relative m-0 inline-grid size-8 cursor-pointer appearance-none place-items-center rounded-md border border-[oklch(0.79_0.035_276)] bg-lm-accent-soft p-0 text-lm-accent focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-lm-accent"
    } else {
      "relative m-0 inline-grid size-8 cursor-pointer appearance-none place-items-center rounded-md border border-transparent bg-transparent p-0 text-lm-muted hover:bg-[oklch(0.955_0.003_255)] hover:text-lm-ink focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-lm-accent"
    },
    title=name,
    type_="button",
    attrs=@html.Attrs::build()
      .role("tab")
      .aria_label(name)
      .aria_selected(if selected { "true" } else { "false" })
      .aria_controls("loomark-editor-panel")
      .tabindex(if mode == focused_mode { 0 } else { -1 }),
    on_click=emit(ModeSelected(mode)),
    @html.span(
      class="pointer-events-none relative block size-4.5",
      attrs=@html.Attrs::build()
        .data_set("mode", name.to_lower())
        .aria_hidden("true"),
      @html.nothing,
    ),
  )
}

///|
fn mode_keydown(
  event : @dom.KeyboardEvent,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Cmd {
  let key = event.key()
  match key {
    "ArrowLeft" | "ArrowRight" | "Enter" | " " => {
      event.prevent_default()
      emit(ModeKeyPressed(key))
    }
    _ => @cmd.none
  }
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
fn sidebar_panel_icon() -> @rabbita.Html {
  @html.span(
    class="relative block size-4 shrink-0",
    attrs=@html.Attrs::build()
      .data_set("loomark-icon", "sidebar")
      .aria_hidden("true"),
    @html.nothing,
  )
}

///|
fn sidebar_document_icon() -> @rabbita.Html {
  @html.span(
    class="relative mt-0.5 block size-4 shrink-0",
    attrs=@html.Attrs::build()
      .data_set("loomark-icon", "document")
      .aria_hidden("true"),
    @html.nothing,
  )
}

///|
fn document_sidebar(
  scope : @rui.SidebarScope,
  editing : EditingState,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Html {
  let available = can_activate(editing)
  let entries = editing.repository.catalog().entries()
  let compact = editing.compact
  let close_after_action = if compact {
    @rui.sidebar_collapse(scope)
  } else {
    @cmd.none
  }
  @rui.sidebar(
    scope,
    id="loomark-document-sidebar",
    mobile=false,
    side=@rui.SidebarLeft,
    variant=@rui.SidebarDefault,
    collapsible=@rui.SidebarOffcanvas,
    aria_label="Documents",
    class="[--rui-sidebar:var(--color-lm-foundation)] [--rui-sidebar-foreground:var(--color-lm-ink)] [--rui-sidebar-border:var(--color-lm-rule)] [--rui-sidebar-accent:var(--color-lm-accent-soft)] [--rui-sidebar-accent-foreground:var(--color-lm-accent)]",
    [
      @rui.sidebar_header(
        @html.div(class="flex min-h-9 items-center justify-between gap-2", [
          @html.strong(class="truncate text-sm font-semibold", "Loomark"),
          @html.div(class="flex items-center gap-1", [
            @rui.button(
              variant=@rui.Ghost,
              size=@rui.Sm,
              disabled=!available,
              on_click=@cmd.batch([emit(CreateRequested), close_after_action]),
              "New",
            ),
            @rui.sidebar_trigger(
              scope,
              mobile=false,
              controls="loomark-document-sidebar",
              aria_label="Close documents",
              sidebar_panel_icon(),
            ),
          ]),
        ]),
      ),
      @rui.sidebar_separator(),
      @rui.sidebar_content(
        @rui.sidebar_group([
          @rui.sidebar_group_label("Documents"),
          @rui.sidebar_group_content(
            @rui.sidebar_menu(
              entries.mapi((index, entry) => {
                let document_id = entry.document_id()
                let selected = document_id == editing.activation.document_id
                @rui.sidebar_menu_item(
                  @rui.sidebar_menu_button(
                    is_active=selected,
                    disabled=!available && !selected,
                    aria_label=document_option_label(entries, index, entry),
                    on_click=@cmd.batch([
                      emit(DocumentSelected(document_id)),
                      close_after_action,
                    ]),
                    style=[
                      "height:auto;min-height:2.75rem;align-items:flex-start;padding-block:0.5rem",
                      if selected {
                        "box-shadow:inset 2px 0 0 var(--color-lm-accent)"
                      } else {
                        ""
                      },
                    ],
                    [
                      sidebar_document_icon(),
                      @html.span(
                        class="min-w-0 overflow-hidden text-ellipsis whitespace-normal [display:-webkit-box] [-webkit-box-orient:vertical] [-webkit-line-clamp:2]",
                        document_option_label(entries, index, entry),
                      ),
                    ],
                  ),
                )
              }),
            ),
          ),
        ]),
      ),
      @rui.sidebar_footer(
        @html.p(
          class="m-0 px-2 text-xs text-lm-muted tabular-nums",
          if entries.length() == 1 {
            "1 document"
          } else {
            "\{entries.length()} documents"
          },
        ),
      ),
    ],
  )
}

///|
fn mode_bar(
  scope : @rui.SidebarScope,
  editing : EditingState,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Html {
  let sidebar_open = !@rui.sidebar_is_collapsed(scope)
  @html.header(
    class="relative z-2 flex min-h-11 shrink-0 flex-wrap items-center justify-between gap-2 border-b border-lm-rule bg-lm-surface px-3 py-1.5 max-[641px]:px-2",
    [
      @html.div(class="flex min-w-0 items-center gap-2", [
        if sidebar_open {
          @html.nothing
        } else {
          @rui.sidebar_trigger(
            scope,
            mobile=false,
            controls="loomark-document-sidebar",
            aria_label="Open documents",
            sidebar_panel_icon(),
          )
        },
        @html.div(
          class="inline-flex items-center gap-0.5",
          attrs=@html.Attrs::build()
            .role("tablist")
            .aria_label("Editor mode")
            .aria_orientation("horizontal")
            .on_keydown(event => mode_keydown(event, emit)),
          [
            mode_tab(Text, editing.mode, editing.focused_mode, emit),
            mode_tab(Preview, editing.mode, editing.focused_mode, emit),
            mode_tab(Split, editing.mode, editing.focused_mode, emit),
          ],
        ),
      ]),
      examples_bar(
        emit,
        editing.activation,
        disabled=editing.creation == Creating,
      ),
    ],
  )
}

///|
fn text_area_view(
  emit : @rabbita.Emit[Msg],
  text_area : @text_area.TextArea,
  activation : Activation,
  disabled? : Bool,
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
fn preview_result_view(result : PreviewResult) -> @rabbita.Html {
  if result.empty {
    @html.p(
      class="m-0 text-lm-muted",
      attrs=@html.Attrs::build().role("status"),
      "Nothing to preview",
    )
  } else {
    result.html
  }
}

///|
fn preview_view(state : PreviewState) -> @rabbita.Html {
  let (alert, content) = match state {
    Unrequested => (@html.nothing, @html.nothing)
    Preparing =>
      (
        @html.nothing,
        @html.p(
          class="m-0 text-lm-muted",
          attrs=@html.Attrs::build().role("status"),
          "Preparing preview…",
        ),
      )
    Ready(result) => (@html.nothing, preview_result_view(result))
    Failed(None) =>
      (
        @html.nothing,
        @html.p(
          class="m-0 text-lm-danger",
          attrs=@html.Attrs::build().role("alert"),
          "Preview could not be prepared.",
        ),
      )
    Failed(Some(result)) =>
      (
        @html.div(
          class="sticky top-0 z-2 border-b border-[oklch(0.78_0.07_25)] bg-lm-danger-soft px-4 py-2.5 text-sm leading-[1.4] text-lm-danger max-[641px]:px-3",
          attrs=@html.Attrs::build().role("alert"),
          "Preview could not be updated. Showing the last completed preview.",
        ),
        preview_result_view(result),
      )
  }
  @html.div(
    id="loomark-preview-scroll",
    class="h-full min-h-0 w-full min-w-0 overflow-auto outline-0 focus-visible:shadow-[inset_0_0_0_2px_var(--color-lm-accent)]",
    attrs=@html.Attrs::build()
      .role("region")
      .aria_label("Markdown preview")
      .tabindex(0),
    [
      alert,
      @html.div(
        class="prose loomark-prose lg:prose-lg mx-auto w-[min(calc(100%-4rem),46rem)] max-w-none min-w-0 px-4 pt-8 pb-16 font-lm-ui max-[641px]:w-full max-[641px]:px-3 max-[641px]:pt-6 max-[641px]:pb-12 [&>*]:min-w-0 [&>*]:break-words",
        content,
      ),
    ],
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
  @html.div(
    class="flex min-h-12 shrink-0 items-center justify-between gap-4 border-t border-[oklch(0.78_0.07_25)] bg-lm-danger-soft px-4 py-2.5 text-sm text-lm-danger max-[641px]:items-start [&_p]:m-0",
    attrs=@html.Attrs::build().role("alert"),
    [
      @html.p("A new document could not be created. " + reason),
      @html.button(
        class="min-h-8 shrink-0 cursor-pointer rounded-md border border-current bg-transparent px-2.5 py-1 text-inherit focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-lm-danger",
        on_click=emit(CreateRequested),
        "Retry creating",
      ),
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
    @source_repository.SaveFailure::StorageUnavailable =>
      " Browser storage is unavailable."
    @source_repository.SaveFailure::QuotaExceeded => " Browser storage is full."
    @source_repository.SaveFailure::WriteFailed =>
      " Browser storage failed while writing the document."
  }
  @html.div(
    class="flex min-h-12 shrink-0 items-center justify-between gap-4 border-t border-[oklch(0.78_0.07_25)] bg-lm-danger-soft px-4 py-2.5 text-sm text-lm-danger max-[641px]:items-start [&_p]:m-0",
    attrs=@html.Attrs::build().role("alert"),
    [
      @html.p("Changes are not saved in this browser." + reason),
      @html.button(
        class="min-h-8 shrink-0 cursor-pointer rounded-md border border-current bg-transparent px-2.5 py-1 text-inherit focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-lm-danger",
        on_click=emit(RetrySave),
        "Retry saving",
      ),
    ],
  )
}

///|
fn view(
  sidebar : @rui.SidebarScope,
  model : Model,
  emit : @rabbita.Emit[Msg],
  editor_panels : @rabbita.Html,
) -> @rabbita.Html {
  @html.div(
    id="loomark-root",
    class="flex h-dvh min-h-0 w-full min-w-0 overflow-hidden bg-lm-foundation font-lm-ui text-lm-ink scheme-light selection:bg-[oklch(0.78_0.08_276/0.45)]",
    attrs=@html.Attrs::build()
      .role("region")
      .aria_label("Loomark Markdown Editor"),
    match model {
      Loading(_) =>
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
        @html.fragment([
          document_sidebar(sidebar, editing, emit),
          @html.div(
            class="flex h-full min-h-0 min-w-0 flex-1 flex-col overflow-hidden bg-lm-paper",
            [
              mode_bar(sidebar, editing, emit),
              @html.main_(
                id="loomark-editor-panel",
                class="flex min-h-0 min-w-0 flex-1 flex-col overflow-hidden",
                attrs=@html.Attrs::build()
                  .role("tabpanel")
                  .aria_label("\{mode_name(editing.mode)} mode"),
                editor_panels,
              ),
              match (editing.save, editing.creation) {
                (Failed(failure), _) => save_failure_view(failure, emit)
                (_, CreationFailed(failure)) =>
                  creation_failure_view(failure, emit)
                (Saved | Waiting | Saving(_), Idle | Creating) => @html.nothing
              },
            ],
          ),
        ])
    },
  )
}
