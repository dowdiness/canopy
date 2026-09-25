///|
fn preview_result_view(preview : RenderedPreview) -> @rabbita.Html {
  if preview.empty {
    @html.p(
      class="m-0 text-lm-muted",
      attrs=@html.Attrs::build().role("status"),
      "Nothing to preview",
    )
  } else {
    preview.html
  }
}

///|
pub fn State::view(self : State) -> @rabbita.Html {
  let (alert, content) = match self.phase {
    Unrequested | Preparing =>
      (
        @html.nothing,
        if self.phase is Preparing {
          @html.p(
            class="m-0 text-lm-muted",
            attrs=@html.Attrs::build().role("status"),
            "Preparing preview…",
          )
        } else {
          @html.nothing
        },
      )
    Ready(output) => (@html.nothing, preview_result_view(output))
    Failed(None) =>
      (
        @html.nothing,
        @html.p(
          class="m-0 opacity-100 text-lm-danger transition-opacity duration-[160ms] ease-[cubic-bezier(0.23,1,0.32,1)] starting:opacity-0 motion-reduce:duration-[80ms] motion-reduce:ease-[ease]",
          attrs=@html.Attrs::build().role("alert"),
          "Preview could not be prepared.",
        ),
      )
    Failed(Some(output)) =>
      (
        @html.div(
          class="sticky top-0 z-2 border-b border-[oklch(0.78_0.07_25)] bg-lm-danger-soft px-4 py-2.5 text-sm leading-[1.4] text-lm-danger opacity-100 transition-opacity duration-[160ms] ease-[cubic-bezier(0.23,1,0.32,1)] starting:opacity-0 motion-reduce:duration-[80ms] motion-reduce:ease-[ease] max-[641px]:px-3",
          attrs=@html.Attrs::build().role("alert"),
          "Preview could not be updated. Showing the last completed preview.",
        ),
        preview_result_view(output),
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
        class="prose prose-sm loomark-prose md:prose-base xl:prose-lg mx-auto w-[min(calc(100%-4rem),46rem)] max-w-none min-w-0 px-4 pt-8 pb-16 font-lm-ui max-[641px]:w-full max-[641px]:px-3 max-[641px]:pt-6 max-[641px]:pb-12 [&>*]:min-w-0 [&>*]:break-words",
        content,
      ),
    ],
  )
}
