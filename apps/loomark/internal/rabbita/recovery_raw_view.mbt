///|
/// Read-only recovery surface for an accepted document whose editor session
/// could not be reopened. It has no editing callback; controls are effects
/// over the exact captured source only.
fn raw_recovery_view(
  model : DriverModel,
  emit : @cmd.Emit[DriverEvent],
) -> @rabbita_runtime.Html {
  let source = match model.runtime_state {
    EditorRuntimeState::RawRecovery(source) => source
    _ => model.document.source()
  }
  @html.div(
    id="loomark-recovery-root",
    attrs=@html.Attrs::build()
      .role("alert")
      .aria_label("Markdown document recovery")
      .data_set("loomark-recovery", "raw"),
    style=[
      "min-height:100vh;box-sizing:border-box;display:grid;place-items:center;padding:2rem;background:oklch(0.968 0.008 85);color:oklch(0.24 0.018 265)",
    ],
    @html.div(
      id="loomark-recovery-panel",
      style=[
        "width:min(100%,48rem);display:grid;gap:0.75rem;padding:2rem;border:1px solid oklch(0.86 0.012 85);border-radius:0.5rem;background:oklch(0.991 0.004 85)",
      ],
      [
        @html.h1(id="loomark-recovery-title", "Your document is safe to copy"),
        @html.p(
          id="loomark-recovery-message",
          "Editing is paused. Copy or download the exact accepted Markdown, then reload to try again.",
        ),
        match model.error {
          Some(error) =>
            @html.p(
              id="loomark-recovery-status",
              attrs=@html.Attrs::build().role("status"),
              error,
            )
          None => @html.nothing
        },
        @html.textarea(
          id="loomark-recovery-source",
          attrs=@html.Attrs::build().aria_label("Recovered Markdown source"),
          rows=18,
          value=source,
          read_only=true,
          "",
        ),
        @html.pre(
          id="loomark-recovery-source-pre",
          attrs=@html.Attrs::build().aria_label(
            "Recovered Markdown source preview",
          ),
          source,
        ),
        @html.div(
          attrs=@html.Attrs::build()
            .role("group")
            .aria_label("Recovery actions"),
          [
            @rui.button(
              id="loomark-recovery-copy",
              attrs=@html.Attrs::build().aria_label("Copy recovered Markdown"),
              on_click=emit(Lifecycle(RecoveryCopy)),
              "Copy",
            ),
            @rui.button(
              id="loomark-recovery-download",
              attrs=@html.Attrs::build().aria_label(
                "Download recovered Markdown",
              ),
              on_click=emit(Lifecycle(RecoveryDownload)),
              "Download .md",
            ),
            @rui.button(
              id="loomark-recovery-reload",
              attrs=@html.Attrs::build().aria_label("Reload editor"),
              on_click=emit(Lifecycle(RecoveryReload)),
              "Reload",
            ),
          ],
        ),
      ],
    ),
  )
}
