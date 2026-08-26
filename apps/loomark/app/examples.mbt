///|
fn examples_bar(emit : @rabbita.Emit[Msg]) -> @rabbita.Html {
  @html.div(
    class="loomark-examples",
    attrs=@html.Attrs::build().role("toolbar").aria_label("Example documents"),
    [
      @html.button(
        type_="button",
        attrs=@html.Attrs::build().aria_label(
          "Apply Markdown feature tour example",
        ),
        on_click=emit(ExampleSelected(embedded_markdown_demo_source)),
        "Demo",
      ),
      @html.button(
        type_="button",
        attrs=@html.Attrs::build().aria_label("Apply Hello example"),
        on_click=emit(ExampleSelected(embedded_hello_example_source)),
        "Hello",
      ),
      @html.button(
        type_="button",
        attrs=@html.Attrs::build().aria_label("Guide: Apply Blog example"),
        on_click=emit(ExampleSelected(embedded_blog_example_source)),
        "Guide",
      ),
      @html.button(
        type_="button",
        attrs=@html.Attrs::build().aria_label("Apply List example"),
        on_click=emit(ExampleSelected(embedded_list_example_source)),
        "List",
      ),
      @html.button(
        type_="button",
        attrs=@html.Attrs::build().aria_label("Apply Code example"),
        on_click=emit(ExampleSelected(embedded_code_example_source)),
        "Code",
      ),
    ],
  )
}
