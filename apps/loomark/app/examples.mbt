///|
fn examples_bar(
  emit : @rabbita.Emit[Msg],
  activation : Activation,
  close_after_action : @rabbita.Cmd,
  disabled~ : Bool,
) -> @rabbita.Html {
  let button_class = "min-h-8 cursor-pointer appearance-none rounded-md border border-transparent bg-transparent px-2 py-1 text-xs text-lm-muted transition-colors duration-150 hover:border-lm-rule hover:bg-lm-surface hover:text-lm-ink focus-visible:outline-2 focus-visible:outline-offset-1 focus-visible:outline-lm-accent max-[641px]:min-h-11"
  @html.div(
    class="flex min-w-0 flex-col gap-1.5",
    attrs=@html.Attrs::build().role("toolbar").aria_label("Example documents"),
    [
      @html.span(class="px-1 text-xs font-medium text-lm-muted", "Examples"),
      @html.div(class="grid min-w-0 grid-cols-3 gap-1", [
        @html.button(
          type_="button",
          class=button_class,
          disabled~,
          attrs=@html.Attrs::build().aria_label(
            "Demo: Create Markdown feature tour example document",
          ),
          on_click=@cmd.batch([
            emit(ExampleSelected(activation, embedded_markdown_demo_source)),
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
            emit(ExampleSelected(activation, embedded_hello_example_source)),
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
            emit(ExampleSelected(activation, embedded_blog_example_source)),
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
            emit(ExampleSelected(activation, embedded_list_example_source)),
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
            emit(ExampleSelected(activation, embedded_code_example_source)),
            close_after_action,
          ]),
          "Code",
        ),
      ]),
    ],
  )
}
