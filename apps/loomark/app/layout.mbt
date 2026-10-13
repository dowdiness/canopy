///|
priv enum ScreenPhase {
  LoadingScreen
  RecoveryScreen(@source_repository.OpenFailure)
  CreationScreen
  EditingScreen
} derive(Eq)

///|
priv struct LayoutInput {
  phase : ScreenPhase
  compact : Bool
  navigation : @rabbita.Html
  tools : @rabbita.Html
  toolbar : @rabbita.Html
  account_notice : @rabbita.Html
  editor : @rabbita.Html
  footer : @rabbita.Html
  notices : @rabbita.Html
  dialog : @rabbita.Html
} derive(Eq)

///|
fn screen_layout(
  sidebar : @sidebar.SidebarScope,
  input : LayoutInput,
) -> @rabbita.Html {
  @html.div(
    id="loomark-root",
    class="flex h-full min-h-0 w-full min-w-0 overflow-hidden bg-lm-foundation font-lm-ui text-lm-ink scheme-light selection:bg-lm-accent-soft",
    attrs=@html.Attrs::build()
      .role("region")
      .aria_label("Loomark Markdown Editor"),
    [
      match input.phase {
        LoadingScreen =>
          @html.div(
            class="grid min-h-full place-items-center text-lm-muted [&_p]:m-0",
            [@html.p("Loading document")],
          )
        RecoveryScreen(failure) => {
          let message = match failure {
            @source_repository.OpenFailure::StorageUnavailable =>
              "Browser storage is unavailable."
            @source_repository.OpenFailure::ReadFailed =>
              "Browser storage failed while reading the document."
          }
          @html.div(
            class="mx-auto w-[min(calc(100%-2rem),36rem)] pt-[max(4rem,20vh)] pb-8 [&_h1]:mt-0 [&_h1]:mb-3 [&_h1]:text-xl [&_h1]:leading-[1.3] [&_p]:m-0 [&_p]:leading-[1.6] [&_p]:text-lm-muted",
            [@html.h1("Document recovery"), @html.p(message)],
          )
        }
        CreationScreen =>
          @html.div(
            class="mx-auto w-[min(calc(100%-2rem),36rem)] pt-[max(4rem,20vh)] pb-8 [&_h1]:mt-0 [&_h1]:mb-3 [&_h1]:text-xl [&_h1]:leading-[1.3] [&_p]:m-0 [&_p]:leading-[1.6]",
            [@html.h1("New document"), input.notices],
          )
        EditingScreen => {
          let editor_inert = input.compact &&
            !@sidebar.sidebar_is_collapsed(sidebar)
          @html.div(
            class="flex h-full min-h-0 min-w-0 flex-1 opacity-100 transition-opacity duration-[140ms] ease-[cubic-bezier(0.23,1,0.32,1)] starting:opacity-[0.92] motion-reduce:duration-[80ms] motion-reduce:ease-[ease]",
            [
              @sidebar.sidebar(
                sidebar,
                id="loomark-document-sidebar",
                mobile=false,
                side=@sidebar.SidebarLeft,
                variant=@sidebar.SidebarDefault,
                collapsible=@sidebar.SidebarOffcanvas,
                aria_label="Documents",
                class="loomark-sidebar [--rui-sidebar:var(--color-lm-foundation)] [--rui-sidebar-foreground:var(--color-lm-ink)] [--rui-sidebar-border:var(--color-lm-rule)] [--rui-sidebar-accent:var(--color-lm-accent-soft)] [--rui-sidebar-accent-foreground:var(--color-lm-accent)]",
                [input.navigation, input.tools],
              ),
              document_sidebar_trigger(sidebar, input.compact),
              @html.div(
                id="loomark-editor",
                class="relative flex h-full min-h-0 min-w-0 flex-1 flex-col overflow-hidden bg-lm-paper",
                attrs=@html.Attrs::build().inert(editor_inert),
                [
                  input.toolbar,
                  input.account_notice,
                  input.editor,
                  input.footer,
                  input.notices,
                ],
              ),
            ],
          )
        }
      },
      input.dialog,
    ],
  )
}

///|
fn document_sidebar_trigger(
  scope : @sidebar.SidebarScope,
  compact : Bool,
) -> @rabbita.Html {
  let focus = compact && @sidebar.sidebar_is_collapsed(scope)
  @sidebar.sidebar_trigger(
    scope,
    mobile=false,
    controls="loomark-document-sidebar",
    aria_label="Toggle documents",
    class="loomark-sidebar-trigger fixed left-3 z-50 active:opacity-50 max-[520px]:left-2",
    on_click=if focus {
      @sidebar.sidebar_focus("loomark-document-sidebar")
    } else {
      @cmd.none
    },
    @view.panel_icon("block size-4 shrink-0"),
  )
}
