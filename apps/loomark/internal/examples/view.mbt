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
      @html.div(class="flex min-w-0 flex-wrap gap-1.5", [
        @html.button(
          type_="button",
          class=button_class,
          disabled~,
          attrs=@html.Attrs::build().aria_label(
            "Demo: Create Markdown feature tour example document",
          ),
          on_click=@cmd.batch([
            on_select(embedded_markdown_demo_source),
            close_after_action,
          ]),
          "Demo",
        ),
        @html.button(
          type_="button",
          class=button_class,
          disabled~,
          attrs=@html.Attrs::build().aria_label("Create Hello example document"),
          on_click=@cmd.batch([
            on_select(embedded_hello_example_source),
            close_after_action,
          ]),
          "Hello",
        ),
        @html.button(
          type_="button",
          class=button_class,
          disabled~,
          attrs=@html.Attrs::build().aria_label(
            "Guide: Create Blog example document",
          ),
          on_click=@cmd.batch([
            on_select(embedded_blog_example_source),
            close_after_action,
          ]),
          "Guide",
        ),
        @html.button(
          type_="button",
          class=button_class,
          disabled~,
          attrs=@html.Attrs::build().aria_label("Create List example document"),
          on_click=@cmd.batch([
            on_select(embedded_list_example_source),
            close_after_action,
          ]),
          "List",
        ),
        @html.button(
          type_="button",
          class=button_class,
          disabled~,
          attrs=@html.Attrs::build().aria_label("Create Code example document"),
          on_click=@cmd.batch([
            on_select(embedded_code_example_source),
            close_after_action,
          ]),
          "Code",
        ),
      ]),
    ],
  )
}
