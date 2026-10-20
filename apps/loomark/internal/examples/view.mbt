///|
/// An example document offered in the sidebar: visible label, the accessible
/// name that begins with it, and its Markdown source.
priv struct Example {
  label : String
  name : String
  source : String
}

///|
/// The document a first visit opens with, before anything has been written.
pub fn welcome_source() -> String {
  embedded_welcome_source
}

///|
let examples : Array[Example] = [
  {
    label: "Welcome",
    name: "Welcome: Create welcome example document",
    source: embedded_welcome_source,
  },
  {
    label: "Markdown",
    name: "Markdown: Create Markdown guide example document",
    source: embedded_markdown_source,
  },
  {
    label: "Journal",
    name: "Journal: Create journal example document",
    source: embedded_journal_source,
  },
]

///|
pub fn examples_bar(
  on_select : @rabbita.Emit[String],
  close_after_action : @rabbita.Cmd,
  disabled~ : Bool,
) -> @rabbita.Html {
  let button_class = "min-h-7 cursor-pointer appearance-none rounded-full border border-lm-rule bg-transparent px-2.5 py-0.5 text-xs text-lm-muted transition-colors duration-150 hover:border-lm-muted/40 hover:bg-lm-surface hover:text-lm-ink focus-visible:outline-2 focus-visible:outline-offset-1 focus-visible:outline-lm-accent disabled:cursor-default disabled:opacity-50 max-[641px]:min-h-11 max-[641px]:px-3.5"
  @html.div(
    class="flex min-w-0 flex-col gap-1.5",
    attrs=@html.Attrs::build().role("toolbar").aria_label("Example documents"),
    [
      @html.span(
        class="px-0.5 text-[0.6875rem] font-medium tracking-[0.06em] text-lm-muted uppercase",
        "Examples",
      ),
      @html.div(
        class="flex min-w-0 flex-wrap gap-1.5",
        examples.map(example => {
          @html.button(
            type_="button",
            class=button_class,
            disabled~,
            attrs=@html.Attrs::build().aria_label(example.name),
            on_click=@cmd.batch([on_select(example.source), close_after_action]),
            example.label,
          )
        }),
      ),
    ],
  )
}
