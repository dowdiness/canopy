///|
fn examples_bar(
  emit : @rabbita.Emit[Msg],
  activation : Activation,
  disabled~ : Bool,
) -> @rabbita.Html {
  let button_class = "min-h-8 shrink-0 cursor-pointer appearance-none rounded-md border-0 bg-transparent px-2 py-1 text-xs text-lm-muted transition-colors duration-150 hover:bg-[oklch(0.955_0.003_255)] hover:text-lm-ink focus-visible:outline-2 focus-visible:outline-offset-1 focus-visible:outline-lm-accent max-[641px]:min-h-11 max-[641px]:px-1"
  @html.div(
    class="flex min-w-0 items-center justify-end gap-0.5 max-[641px]:order-3 max-[641px]:w-full max-[641px]:basis-full max-[641px]:justify-start max-[641px]:overflow-x-auto",
    attrs=@html.Attrs::build().role("toolbar").aria_label("Example documents"),
    [
      @html.button(
        type_="button",
        class=button_class,
        disabled~,
        attrs=@html.Attrs::build().aria_label(
          "Demo: Apply Markdown feature tour example",
        ),
        on_click=emit(
          ExampleSelected(activation, embedded_markdown_demo_source),
        ),
        "Demo",
      ),
      @html.button(
        type_="button",
        class=button_class,
        disabled~,
        attrs=@html.Attrs::build().aria_label("Apply Hello example"),
        on_click=emit(
          ExampleSelected(activation, embedded_hello_example_source),
        ),
        "Hello",
      ),
      @html.button(
        type_="button",
        class=button_class,
        disabled~,
        attrs=@html.Attrs::build().aria_label("Guide: Apply Blog example"),
        on_click=emit(ExampleSelected(activation, embedded_blog_example_source)),
        "Guide",
      ),
      @html.button(
        type_="button",
        class=button_class,
        disabled~,
        attrs=@html.Attrs::build().aria_label("Apply List example"),
        on_click=emit(ExampleSelected(activation, embedded_list_example_source)),
        "List",
      ),
      @html.button(
        type_="button",
        class=button_class,
        disabled~,
        attrs=@html.Attrs::build().aria_label("Apply Code example"),
        on_click=emit(ExampleSelected(activation, embedded_code_example_source)),
        "Code",
      ),
    ],
  )
}
