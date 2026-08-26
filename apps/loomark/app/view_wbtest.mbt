///|
#warnings("-alert_unstable")
fn render_preview_state(state : PreviewState) -> String {
  @rabbita_testing.server_side_render(() => preview_view(state))
}

///|
test "Preview view distinguishes preparing initial failure and stale result" {
  let preparing = render_preview_state(Preparing)
  assert_true(preparing.contains("role=\"status\""))
  assert_true(preparing.contains("Preparing preview…"))

  let initial_failure = render_preview_state(Failed(None))
  assert_true(initial_failure.contains("role=\"alert\""))
  assert_true(initial_failure.contains("Preview could not be prepared."))

  let stale = render_preview_state(
    Failed(
      Some({ text: "# Last good\n", html: @html.h1("Last good"), empty: false }),
    ),
  )
  assert_true(stale.contains("Showing the last completed preview."))
  assert_true(stale.contains(">Last good</h1>"))
}
