///|
priv enum DocumentIntent {
  CreateRequested
  MenuToggled
  ImportFilesSelected(FixedArray[@browser.File])
  ExportRequested
  ExampleSelected(Activation, String)
}

///|
priv struct DocumentToolsInput {
  activation : Activation
  examples_disabled : Bool
  import_disabled : Bool
} derive(Eq)

///|
priv struct ToolbarInput {
  can_create : Bool
  menu_open : Bool
  import_disabled : Bool
} derive(Eq)

///|
fn file_actions(
  input_id : String,
  import_disabled : Bool,
  emit : @rabbita.Emit[DocumentIntent],
) -> @rabbita.Html {
  let action_class = "flex min-h-9 min-w-0 cursor-pointer items-center justify-center gap-2 rounded-md border border-lm-rule bg-lm-surface px-2 py-1.5 text-xs text-lm-muted transition-colors duration-150 hover:bg-lm-accent-soft hover:text-lm-accent focus-visible:outline-2 focus-visible:outline-offset-1 focus-visible:outline-lm-accent max-[641px]:min-h-11"
  @html.div(class="grid min-w-0 grid-cols-2 gap-2", [
    @html.label(
      class="relative \{action_class} has-[:focus-visible]:outline-2 has-[:focus-visible]:outline-offset-1 has-[:focus-visible]:outline-lm-accent",
      title="Import Markdown",
      for_=input_id,
      [
        @view.upload_icon("pointer-events-none block size-4 shrink-0"),
        @html.span("Import"),
        @html.input(
          input_type=File,
          id=input_id,
          class="sr-only",
          on_files=emit.map(files => ImportFilesSelected(files)),
          attrs=@html.Attrs::build()
            .aria_label("Import Markdown")
            .disabled(import_disabled),
        ),
      ],
    ),
    @html.button(
      type_="button",
      class=action_class,
      title="Export Markdown",
      attrs=@html.Attrs::build().aria_label("Export Markdown"),
      on_click=emit(ExportRequested),
      [
        @view.download_icon("pointer-events-none block size-4 shrink-0"),
        @html.span("Export"),
      ],
    ),
  ])
}

///|
fn sidebar_tools(
  input : DocumentToolsInput,
  close_after_action : @rabbita.Cmd,
  emit : @rabbita.Emit[DocumentIntent],
) -> @rabbita.Html {
  @sidebar.sidebar_footer(class="border-t border-lm-rule", [
    @examples.examples_bar(
      emit.map(text => ExampleSelected(input.activation, text)),
      close_after_action,
      disabled=input.examples_disabled,
    ),
    file_actions("loomark-import", input.import_disabled, emit),
  ])
}

///|
fn document_toolbar(
  input : ToolbarInput,
  account : @rabbita.Html,
  sync_status : @rabbita.Html,
  emit : @rabbita.Emit[DocumentIntent],
) -> @rabbita.Html {
  @html.header(
    class="loomark-topbar flex h-12 shrink-0 items-center justify-end gap-1 px-6 max-[520px]:h-[52px] max-[520px]:px-3",
    [
      @html.button(
        type_="button",
        class="loomark-icon",
        title="New document",
        attrs=@html.Attrs::build()
          .aria_label("New document")
          .disabled(!input.can_create),
        on_click=emit(CreateRequested),
        @view.square_pen_icon("block size-4"),
      ),
      @html.button(
        type_="button",
        class="loomark-icon",
        title="More actions",
        attrs=@html.Attrs::build()
          .id("loomark-more-actions")
          .aria_label("More actions")
          .aria_controls("loomark-more-actions-content")
          .aria_expanded(if input.menu_open { "true" } else { "false" }),
        on_click=emit(MenuToggled),
        @view.more_icon("block size-4"),
      ),
      if input.menu_open {
        @html.div(id="loomark-more-actions-content", class="loomark-menu", [
          sync_status,
          @html.div(
            class="flex flex-col gap-1 border-b border-lm-rule px-1 pb-2",
            account,
          ),
          file_actions("loomark-menu-import", input.import_disabled, emit),
        ])
      } else {
        @html.nothing
      },
    ],
  )
}

///|
fn document_footer(
  mode : EditorMode,
  durability : LocalDurability?,
  persistence : @replica_persistence.Status?,
  attention : @rabbita.Html,
  on_mode : @rabbita.Emit[EditorMode],
) -> @rabbita.Html {
  @html.footer(
    class="loomark-footer flex h-16 shrink-0 items-center justify-between gap-2 px-3 max-[520px]:px-2",
    [
      @html.div(
        class="loomark-footer-status flex min-w-0 flex-1 items-center gap-2",
        [
          save_indicator(durability, persistence),
          @html.div(class="loomark-sync-attention min-w-0", attention),
        ],
      ),
      @html.div(
        class="loomark-bottom-actions flex shrink-0 items-center gap-2",
        [
          @rui.tabs_root(
            value=mode_name(mode).to_lower(),
            style=["width:auto"],
            @rui.tabs_list(
              orientation=@rui.TabsHorizontal,
              variant=@rui.TabsDefault,
              aria_label="Editor mode",
              [
                mode_tab(Text, mode, on_mode),
                mode_tab(Split, mode, on_mode),
                mode_tab(Preview, mode, on_mode),
              ],
            ),
          ),
        ],
      ),
    ],
  )
}
