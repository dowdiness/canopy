///|
extern "js" fn read_textarea_value(id : String) -> String =
  #| id => document.getElementById(id)?.value ?? ""

///|
const HELLO_EXAMPLE_SOURCE : String = "# Hello World\n\nWelcome to the Canopy Markdown editor.\n\nThis editor has three modes: raw, block, and preview.\n"

///|
const BLOG_EXAMPLE_SOURCE : String = "# Getting Started\n\nCanopy is an incremental projectional editor.\n\n## Features\n\nThe editor supports real-time collaboration via CRDT.\n\nEvery keystroke is incrementally parsed and projected into a structured view."

///|
const LIST_EXAMPLE_SOURCE : String = "# Shopping List\n\nThings to pick up:\n\n- Apples\n- Bread\n- Coffee\n- Dark chocolate"

///|
const CODE_EXAMPLE_SOURCE : String = "# README\n\nA minimal example project.\n\n## Install\n\n```bash\nnpm install\n```\n\n## Usage\n\n- Run the dev server\n- Open the browser\n- Start editing"

///|
/// Long-form Markdown feature tour used by the "Demo" example button.
const MARKDOWN_DEMO_SOURCE : String =
  $|# Markdown Feature Tour
  $|
  $|A long-form tour of Markdown syntax for editing in the Raw source view.
  $|The standalone document is stored directly as portable Markdown.
  $|
  $|---
  $|
  $|## Headings
  $|
  $|Headings come in six levels, from the document title down to small captions.
  $|
  $|### Level Three Heading
  $|
  $|#### Level Four Heading
  $|
  $|##### Level Five Heading
  $|
  $|###### Level Six Heading
  $|
  $|## Emphasis and inline styles
  $|
  $|Text can be **bold**, *italic*, or ***both at once***. Use `inline code` for
  $|identifiers and command names, and nest styles like *italic with **bold
  $|inside***. Unsupported extensions stay as plain text, so the editor stays
  $|honest about what it renders.
  $|
  $|## Links and autolinks
  $|
  $|- A regular link: [Canopy repository](https://github.com/dowdiness/canopy)
  $|- An automatic URI link: <https://docs.moonbitlang.com>
  $|- An automatic email link: <hello@canopy.example>
  $|- A relative link: [README](./README.md)
  $|
  $|### Images
  $|
  $|Images render from safe destinations:
  $|
  $|![Canopy placeholder](https://placehold.co/640x160?text=Canopy+Markdown "A placeholder image")
  $|
  $|## Lists
  $|
  $|### Unordered lists
  $|
  $|- Apples
  $|- Bread
  $|- Dairy
  $|  - Milk
  $|  - Yogurt
  $|    - Greek yogurt
  $|- Dark chocolate
  $|
  $|### Ordered lists
  $|
  $|1. Clone the repository
  $|2. Initialize submodules
  $|3. Build the editor
  $|   1. Install the MoonBit toolchain
  $|   2. Run `moon build --target js`
  $|4. Open the preview
  $|
  $|## Blockquotes
  $|
  $|> Markdown is a lightweight markup language for writing plain-text
  $|> documents that read well before and after rendering.
  $|>
  $|> > Nested quotes keep their own left border.
  $|>
  $|> — the Canopy team
  $|
  $|## Code blocks
  $|
  $|Fenced code blocks keep their language hint and scroll horizontally when a
  $|line is too long:
  $|
  $|```moon
  $|fn greet(name : String) -> String {
  $|  "Hello, \{'\\'}{name}!"
  $|}
  $|
  $|pub fn main {
  $|  println(greet("Canopy"))
  $|}
  $|```
  $|
  $|```python
  $|def fibonacci(n):
  $|    if n < 2:
  $|        return n
  $|    return fibonacci(n - 1) + fibonacci(n - 2)
  $|```
  $|
  $|```bash
  $|moon check
  $|moon test
  $|moon build --target js
  $|```
  $|
  $|## Thematic breaks
  $|
  $|Content before the rule.
  $|
  $|---
  $|
  $|Content after the rule.
  $|
  $|## Hard breaks
  $|
  $|A hard break ends the line here \{'\\'}
  $|and continues on the next line without a blank paragraph in between.
  $|
  $|## Inline HTML
  $|
  $|Inline HTML stays literal and never executes: <span class="note">not rendered</span>
  $|
  $|## A long section of prose
  $|
  $|Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod
  $|tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam,
  $|quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo
  $|consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse
  $|cillum dolore eu fugiat nulla pariatur.
  $|
  $|Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia
  $|deserunt mollit anim id est laborum. Sed ut perspiciatis unde omnis iste
  $|natus error sit voluptatem accusantium doloremque laudantium, totam rem
  $|aperiam, eaque ipsa quae ab illo inventore veritatis et quasi architecto
  $|beatae vitae dicta sunt explicabo.
  $|
  $|Nemo enim ipsam voluptatem quia voluptas sit aspernatur aut odit aut fugit,
  $|sed quia consequuntur magni dolores eos qui ratione voluptatem sequi
  $|nesciunt. Neque porro quisquam est, qui dolorem ipsum quia dolor sit amet,
  $|consectetur, adipisci velit, sed quia non numquam eius modi tempora
  $|incidunt ut labore et dolore magnam aliquam quaerat voluptatem.
  $|
  $|Ut enim ad minima veniam, quis nostrum exercitationem ullam corporis
  $|suscipit laboriosam, nisi ut aliquid ex ea commodi consequatur? Quis autem
  $|vel eum iure reprehenderit qui in ea voluptate velit esse quam nihil
  $|molestiae consequatur, vel illum qui dolorem eum fugiat quo voluptas nulla
  $|pariatur.
  $|
  $|At vero eos et accusamus et iusto odio dignissimos ducimus qui blanditiis
  $|praesentium voluptatum deleniti atque corrupti quos dolores et quas
  $|molestias excepturi sint occaecati cupiditate non provident, similique sunt
  $|in culpa qui officia deserunt mollitia animi, id est laborum et dolorum
  $|fuga. Et harum quidem rerum facilis est et expedita distinctio.
  $|
  $|Nam libero tempore, cum soluta nobis est eligendi optio cumque nihil
  $|impedit quo minus id quod maxime placeat facere possimus, omnis voluptas
  $|assumenda est, omnis dolor repellendus. Temporibus autem quibusdam et aut
  $|officiis debitis aut rerum necessitatibus saepe eveniet ut et voluptates
  $|repudiandae sint et molestiae non recusandae.
  $|
  $|Itaque earum rerum hic tenetur a sapiente delectus, ut aut reiciendis
  $|voluptatibus maiores alias consequatur aut perferendis doloribus asperiores
  $|repellat. This final paragraph keeps the document long enough that the
  $|preview pane scrolls, proving the editor handles long documents well.

///|
/// Render one decorative mode glyph; the owning tab supplies its accessible
/// name and interaction semantics.
fn mode_icon(path : String) -> @html.Html {
  @html.span(
    attrs=@html.Attrs::build().aria_hidden("true"),
    style=[
      "display:inline-flex;width:1.125rem;height:1.125rem;align-items:center;justify-content:center;pointer-events:none",
    ],
    @svg.svg(
      width=18,
      height=18,
      view_box="0 0 24 24",
      style=["display:block;width:100%;height:100%"],
      [
        @svg.path(
          d=path,
          fill="none",
          stroke="currentColor",
          stroke_width=2,
          attrs=@svg.Attrs::build()
            .stroke_linecap("round")
            .stroke_linejoin("round"),
        ),
      ],
    ),
  )
}

///|
fn current_preview_source(
  model : DriverModel,
  raw_input_coordinator : RawInputCoordinator,
) -> String {
  if model.split_preview_open {
    raw_input_coordinator.fast_source_value().unwrap_or(model.document.source())
  } else {
    model.document.source()
  }
}

///|
fn preview_document_view(
  model : DriverModel,
  raw_input_coordinator : RawInputCoordinator,
) -> @rabbita_runtime.Html {
  let source = current_preview_source(model, raw_input_coordinator)
  let unavailable = () => {
    @html.div(
      style=[
        "box-sizing:border-box;width:100%;min-width:0;overflow-y:auto;overflow-x:hidden",
      ],
      @html.div(
        id="loomark-preview",
        attrs=@html.Attrs::build()
          .data_set("loomark-preview-fallback", "unavailable")
          .role("region")
          .tabindex(0)
          .aria_label("Markdown preview"),
        style=[
          "box-sizing:border-box;width:var(--lm-page-width);margin-inline:auto;min-width:0;display:grid;gap:1rem;grid-auto-rows:max-content;background:transparent;padding:1rem var(--lm-page-x-padding)",
        ],
        @rui.typography_muted(
          "Preview is unavailable for the current accepted document.",
        ),
      ),
    )
  }
  match model.raw_preview.artifact() {
    Some(stamped) if stamped.preview.source == source =>
      semantic_preview_artifact_view(source, stamped.preview.artifact)
    _ =>
      match model.preview_artifact {
        Some(stamped) if stamped.preview.source == source =>
          semantic_preview_artifact_view(source, stamped.preview.artifact)
        _ =>
          if selected_projection_placement is ProjectionSynchronous {
            match model.semantic_document {
              Some(document) if source == model.document.source() =>
                semantic_preview_view(source, document)
              _ => unavailable()
            }
          } else {
            unavailable()
          }
      }
  }
}

///|

///|
/// Render the Raw Markdown source textarea; the split Preview pairs this
/// editable source with the rendered Preview pane even when Preview is the
/// selected mode tab.
fn raw_editor_view(
  model : DriverModel,
  emit : @cmd.Emit[DriverEvent],
  raw_input_coordinator : RawInputCoordinator,
) -> @rabbita_runtime.Html {
  let local_text = model.runtime_state is EditorRuntimeState::LocalText(_)
  let committed_source = if local_text {
    runtime_source(model)
  } else {
    model.document.source()
  }
  let source = raw_input_coordinator.display_source(committed_source)
  @html.div(
    style=[
      "box-sizing:border-box;width:100%;min-width:0;overflow-y:auto;overflow-x:hidden",
    ],
    @rui.textarea(
      id="loomark-input",
      value=source,
      rows=4,
      attrs=@html.Attrs::build()
        .aria_label("Raw Markdown source")
        .on_compositionstart(_ => {
          raw_input_coordinator.begin_fast_composition()
          @rabbita_runtime.none
        })
        .on_compositionend(_ => {
          let source = read_textarea_value("loomark-input")
          raw_input_coordinator.finish_fast_composition()
          let generation = raw_input_coordinator.install_fast_source(source)
          @cmd.batch([
            @cmd.delay(
              emit(Editing(RawFastPreview(generation))),
              RAW_FAST_PREVIEW_MS,
            ),
            @cmd.delay(
              emit(Editing(RawFastFlush(generation, source))),
              RAW_FAST_FLUSH_MS,
            ),
          ])
        })
        .on_beforeinput(_ => @rabbita_runtime.none)
        .on_input(_ => @rabbita_runtime.none),
      style=[
        "display:block;min-width:0;min-height:clamp(24rem,70vh,36rem);width:var(--lm-page-width);margin-inline:auto;field-sizing:content;resize:none;overflow:hidden;--rui-control-base-border:transparent;--rui-control-base-shadow:none;background:transparent;padding:1rem var(--lm-page-x-padding);font-family:ui-monospace,SFMono-Regular,Menlo,Monaco,Consolas,\"Liberation Mono\",\"Courier New\",monospace;font-size:1.125rem;line-height:1.65",
      ],
      on_input=@cmd.Emit(source => {
        let generation = raw_input_coordinator.install_fast_source(source)
        let preview = @cmd.delay(
          emit(Editing(RawFastPreview(generation))),
          RAW_FAST_PREVIEW_MS,
        )
        if raw_input_coordinator.fast_composing() {
          preview
        } else {
          @cmd.batch([
            preview,
            @cmd.delay(
              emit(Editing(RawFastFlush(generation, source))),
              RAW_FAST_FLUSH_MS,
            ),
          ])
        }
      }),
    ),
  )
}

///|
fn editor_view(
  model : DriverModel,
  emit : @cmd.Emit[DriverEvent],
  raw_input_coordinator : RawInputCoordinator,
  block_input_coordinator : BlockInputCoordinator,
) -> @rabbita_runtime.Html {
  match model.state.mode() {
    @core.Raw => raw_editor_view(model, emit, raw_input_coordinator)
    @core.Preview => preview_document_view(model, raw_input_coordinator)
    @core.Block => block_editor_view(model, block_input_coordinator, emit)
  }
}

///|
fn preview_view(
  model : DriverModel,
  emit : @cmd.Emit[DriverEvent],
  active_view : @rabbita_runtime.Html,
  driver_controls : @rabbita_runtime.Html,
) -> @rabbita_runtime.Html {
  let local_text = model.runtime_state is EditorRuntimeState::LocalText(_)
  let raw_selected = model.state.mode() == @core.Raw
  let block_selected = model.state.mode() == @core.Block
  let preview_selected = model.state.mode() == @core.Preview
  let raw_button = @rui.tabs_trigger(
    value="raw",
    id="loomark-mode-raw",
    selected=raw_selected,
    attrs=@html.Attrs::build()
      .aria_label("Raw Markdown")
      .on_click(_ => emit(Navigation(SelectRaw))),
    style=["min-height:2.75rem;flex:0 0 3.25rem;padding:0"],
    mode_icon("m8 9-3 3 3 3m8-6 3 3-3 3m-2-8-4 16"),
  )
  let preview_button = @rui.tabs_trigger(
    value="preview",
    id="loomark-mode-preview",
    selected=preview_selected,
    attrs=@html.Attrs::build()
      .aria_label("Preview")
      .on_click(_ => emit(Navigation(SelectPreview))),
    style=["min-height:2.75rem;flex:0 0 3.25rem;padding:0"],
    mode_icon(
      "M2 12s3.5-6 10-6 10 6 10 6-3.5 6-10 6S2 12 2 12Zm10 3a3 3 0 1 0 0-6 3 3 0 0 0 0 6Z",
    ),
  )
  let block_button = @rui.tabs_trigger(
    value="block",
    id="loomark-mode-block",
    selected=block_selected,
    attrs=@html.Attrs::build()
      .aria_label("Block view")
      .on_click(_ => emit(Navigation(SelectBlock))),
    style=["min-height:2.75rem;flex:0 0 3.25rem;padding:0"],
    mode_icon("M4 4h6v6H4V4Zm10 0h6v6h-6V4ZM4 14h6v6H4v-6Zm10 0h6v6h-6v-6Z"),
  )
  let (panel_id, panel_labelledby) = match model.state.mode() {
    @core.Raw => ("loomark-panel-raw", "loomark-mode-raw")
    @core.Block => ("loomark-panel-block", "loomark-mode-block")
    @core.Preview => ("loomark-panel-preview", "loomark-mode-preview")
  }
  // The split cannot be started from the full Preview surface; keep the
  // affordance visible but disabled so the limitation is explicit. The toggle
  // stays enabled while a split is already open (e.g. after switching modes).
  let split_disabled = preview_selected && !model.split_preview_open
  let split_toggle = if local_text {
    @html.nothing
  } else {
    @rui.button(
      id="loomark-split-toggle",
      variant=@rui.Ghost,
      size=@rui.IconSm,
      disabled=split_disabled,
      attrs=@html.Attrs::build()
        .aria_label(
          if model.split_preview_open {
            "Close split Preview"
          } else {
            "Open split Preview"
          },
        )
        .aria_pressed(model.split_preview_open.to_string()),
      on_click=emit(Navigation(ToggleSplitPreview)),
      mode_icon("M4 4h6v16H4V4Zm10 0h6v16h-6V4Z"),
    )
  }
  let examples = @html.div(
    attrs=@html.Attrs::build().role("toolbar").aria_label("Example documents"),
    style=[
      "display:flex;min-height:2.5rem;align-items:center;justify-content:flex-end;gap:0.125rem;flex-wrap:wrap;padding-inline:0.25rem",
    ],
    [
      @rui.button(
        variant=@rui.Ghost,
        size=@rui.Xs,
        attrs=@html.Attrs::build().aria_label(
          "Apply Markdown feature tour example",
        ),
        on_click=emit(Editing(ReplaceSource(MARKDOWN_DEMO_SOURCE))),
        "Demo",
      ),
      @rui.button(
        variant=@rui.Ghost,
        size=@rui.Xs,
        attrs=@html.Attrs::build().aria_label("Apply Hello example"),
        on_click=emit(Editing(ReplaceSource(HELLO_EXAMPLE_SOURCE))),
        "Hello",
      ),
      @rui.button(
        variant=@rui.Ghost,
        size=@rui.Xs,
        attrs=@html.Attrs::build().aria_label("Guide: Apply Blog example"),
        on_click=emit(Editing(ReplaceSource(BLOG_EXAMPLE_SOURCE))),
        "Guide",
      ),
      @rui.button(
        variant=@rui.Ghost,
        size=@rui.Xs,
        attrs=@html.Attrs::build().aria_label("Apply List example"),
        on_click=emit(Editing(ReplaceSource(LIST_EXAMPLE_SOURCE))),
        "List",
      ),
      @rui.button(
        variant=@rui.Ghost,
        size=@rui.Xs,
        attrs=@html.Attrs::build().aria_label("Apply Code example"),
        on_click=emit(Editing(ReplaceSource(CODE_EXAMPLE_SOURCE))),
        "Code",
      ),
    ],
  )
  let persistence_failed = match model.archive_queue.status() {
    @repository.LocalArchivePersistenceStatus::StorageFailed(..) => true
    _ => false
  }
  let error_view = if persistence_failed {
    @html.div(
      id="loomark-error-container",
      style=["display:flex;align-items:center;gap:0.5rem"],
      [
        @rui.alert(
          id="loomark-error",
          variant=@rui.Destructive,
          style=["border-radius:0;flex:1"],
          @rui.alert_description("Changes are applied but not saved locally."),
        ),
        @rui.button(
          variant=@rui.Ghost,
          size=@rui.Xs,
          attrs=@html.Attrs::build().aria_label("Retry saving locally"),
          on_click=emit(Lifecycle(RetryLocalPersistence(model.document_id))),
          "Retry save",
        ),
      ],
    )
  } else {
    match model.error {
      Some(error) =>
        @rui.alert(
          id="loomark-error",
          variant=@rui.Destructive,
          style=["border-radius:0"],
          @rui.alert_description("error: " + error),
        )
      None => @html.nothing
    }
  }
  @rui.theme(
    id="loomark-root",
    attrs=@html.Attrs::build()
      .data_set(
        "loomark-projection-placement",
        selected_projection_placement.name(),
      )
      .role("region")
      .aria_label("Loomark Markdown Editor"),
    style=[
      "min-height:100vh;min-height:100dvh;box-sizing:border-box;background:oklch(0.968 0.008 85);color:oklch(0.24 0.018 265);padding:0;--rui-background:oklch(0.991 0.004 85);--rui-foreground:oklch(0.24 0.018 265);--rui-muted:oklch(0.94 0.01 85);--rui-muted-foreground:oklch(0.5 0.02 265);--rui-border:oklch(0.86 0.012 85);--rui-primary:oklch(0.48 0.12 276);--rui-radius:0.5rem",
    ],
    [
      @html.div(
        id="loomark-editor-shell",
        style=["width:100%;height:100dvh;display:flex;flex-direction:column"],
        [
          @rui.tabs_root(
            value=mode_name(model.state.mode()),
            id="loomark-editor-frame",
            style=[
              "flex:1;gap:0;overflow:hidden;background:var(--rui-background)",
            ],
            [
              @html.div(
                style=[
                  "display:flex;min-width:0;align-items:center;justify-content:space-between;gap:0.25rem;flex-wrap:wrap;padding-inline:0.5rem;border-bottom:1px solid var(--rui-border)",
                ],
                [
                  @html.div(
                    style=[
                      "display:flex;align-items:center;gap:0.125rem;min-width:0",
                    ],
                    [
                      @rui.tabs_list(
                        variant=@rui.TabsLine,
                        aria_label="Editor view",
                        id="loomark-toolbar",
                        style=["min-height:3.25rem;padding:0;overflow:visible"],
                        if local_text {
                          [raw_button]
                        } else {
                          [block_button, raw_button, preview_button]
                        },
                      ),
                      split_toggle,
                    ],
                  ),
                  @html.div(
                    style=[
                      "display:flex;align-items:center;justify-content:flex-end;gap:0.125rem;flex-wrap:wrap",
                    ],
                    [examples],
                  ),
                ],
              ),
              @html.div(
                id=panel_id,
                attrs=@html.Attrs::build()
                  .role("tabpanel")
                  .aria_labelledby(panel_labelledby),
                style=[
                  "min-width:0;min-height:0;flex:1;display:flex;overflow:auto",
                ],
                active_view,
              ),
            ],
          ),
          error_view,
        ],
      ),
      driver_controls,
    ],
  )
}

///|
fn standalone_bootstrap_view(model : DriverModel) -> @rabbita_runtime.Html {
  match model.error_code {
    Some("storage-unavailable") => archive_recovery_view(StorageUnavailable)
    Some("storage-read-failed") => archive_recovery_view(StorageReadFailed)
    Some("editor-initialization-failed") =>
      archive_recovery_view(EditorInitializationFailed)
    Some("unsupported-archive") => archive_recovery_view(UnsupportedArchive)
    Some("corrupt-archive") => archive_recovery_view(CorruptArchive)
    Some("archive-over-limit") => archive_recovery_view(ArchiveOverLimit)
    Some("incomplete-archive") => archive_recovery_view(IncompleteArchive)
    _ =>
      @html.div(
        id="loomark-bootstrap",
        attrs=@html.Attrs::build().role("status"),
        style=[
          "min-height:100vh;display:grid;place-items:center;background:oklch(0.968 0.008 85);color:oklch(0.5 0.02 265)",
        ],
        @html.p("Loading local document…"),
      )
  }
}

///|
fn standalone_preview_view(
  model : DriverModel,
  emit : @cmd.Emit[DriverEvent],
  active_view : @rabbita_runtime.Html,
) -> @rabbita_runtime.Html {
  if !model.archive_persistence_enabled {
    return standalone_bootstrap_view(model)
  }
  match model.runtime_state {
    EditorRuntimeState::RawRecovery(_) => raw_recovery_view(model, emit)
    _ => {
      let benchmark_controls = if projection_benchmark_enabled {
        @html.button(
          id="loomark-projection-trace-dump",
          type_="button",
          hidden=true,
          attrs=@html.Attrs::build().on_click(_ => {
            projection_benchmark_trace_publish()
            @cmd.none
          }),
          "Projection trace",
        )
      } else {
        @html.nothing
      }
      preview_view(model, emit, active_view, benchmark_controls)
    }
  }
}

///|
fn private_dev_host_preview_view(
  model : DriverModel,
  emit : @cmd.Emit[DriverEvent],
  active_view : @rabbita_runtime.Html,
) -> @rabbita_runtime.Html {
  match model.runtime_state {
    EditorRuntimeState::RawRecovery(_) => return raw_recovery_view(model, emit)
    _ => ()
  }
  let driver_controls = @html.fragment([
    @html.button(
      id="loomark-event-target",
      type_="button",
      hidden=true,
      "Driver event",
    ),
    @html.button(
      id="loomark-driver-target",
      type_="button",
      hidden=true,
      "Driver",
    ),
  ])
  preview_view(model, emit, active_view, driver_controls)
}
