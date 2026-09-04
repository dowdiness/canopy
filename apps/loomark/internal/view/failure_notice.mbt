///|
/// Create a consistent failure notice with one action.
pub fn failure_notice(
  message : String,
  action_label : String,
  on_action : Cmd,
) -> Html {
  div(
    class="flex min-h-12 shrink-0 items-center justify-between gap-4 border-t border-[oklch(0.78_0.07_25)] bg-lm-danger-soft px-4 py-2.5 text-sm text-lm-danger opacity-100 transition-opacity duration-[160ms] ease-[cubic-bezier(0.23,1,0.32,1)] starting:opacity-0 motion-reduce:duration-[80ms] motion-reduce:ease-[ease] max-[641px]:items-start [&_p]:m-0",
    attrs=Attrs::build().role("alert"),
    [
      p(message),
      button(
        class="min-h-8 shrink-0 cursor-pointer rounded-md border border-current bg-transparent px-2.5 py-1 text-inherit focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-lm-danger",
        on_click=on_action,
        action_label,
      ),
    ],
  )
}
