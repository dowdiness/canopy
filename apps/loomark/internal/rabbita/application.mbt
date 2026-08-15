///|
/// The private harness has exactly one mount per page/process. This is a
/// bounded test seam, not a reusable handle registry or lifecycle API.
let mounted : @ref.Ref[Bool] = { val: false }

///|
let detached_snapshot : @ref.Ref[String] = { val: "{}" }

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
  $|A long-form tour of the Markdown features this editor renders. Switch
  $|between the Raw, Block, and Preview tabs to see the same document through
  $|each lens, and open the split view to edit and preview side by side.
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
fn mode_name(mode : @core.ApplicationMode) -> String {
  match mode {
    @core.Raw => "raw"
    @core.Block => "block"
    @core.Preview => "preview"
  }
}

///|
fn runtime_state_name(state : EditorRuntimeState) -> String {
  match state {
    EditorRuntimeState::Healthy => "healthy"
    EditorRuntimeState::Restarting => "restarting"
    EditorRuntimeState::RawRecovery(_) => "raw-recovery"
  }
}

///|
fn runtime_source(model : DriverModel) -> String {
  match model.runtime_state {
    EditorRuntimeState::RawRecovery(source) => source
    _ => model.document.source()
  }
}

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
fn record_error(
  model : DriverModel,
  code : String,
  operation : String,
  message : String,
) -> DriverModel {
  {
    ..model,
    error: Some(message),
    error_code: Some(code),
    error_operation: Some(operation),
    error_count: model.error_count + 1,
  }
}

///|
fn publish(
  model : DriverModel,
  raw_input_coordinator : RawInputCoordinator?,
  raw_input_token : Int?,
) -> Unit {
  match (raw_input_coordinator, raw_input_token) {
    (Some(coordinator), Some(token)) => coordinator.mark_publish_started(token)
    _ => ()
  }
  let fields : Map[String, Json] = {
    "source": runtime_source(model).to_json(),
    "replica_id": model.replica_id.to_json(),
    "version": @core.SNAPSHOT_VERSION.to_json(),
    "mode": mode_name(model.state.mode()).to_json(),
    "runtime_state": runtime_state_name(model.runtime_state).to_json(),
    "split_preview_open": model.split_preview_open.to_json(),
    "source_revision": model.source_revision.to_json(),
    "semantic_read_count": model.semantic_read_count.to_json(),
    "fatal": model.fatal.to_json(),
    "error_code": match model.error_code {
      Some(code) => code.to_json()
      None => Json::null()
    },
    "error_operation": match model.error_operation {
      Some(operation) => operation.to_json()
      None => Json::null()
    },
    "error_count": model.error_count.to_json(),
    "committed_change_count": model.committed_change_count.to_json(),
    "editor_failure_armed": model.fail_next_editor_commit.to_json(),
    "parser_failure_armed": model.force_parser_failure.to_json(),
    "reconstruction_attempt_count": model.reconstruction_attempt_count.to_json(),
    "resize_count": model.resize_count.to_json(),
    "selection": match model.selection {
      Some(selection) => selection.to_json()
      None => Json::null()
    },
    "measurement": match model.measurement {
      Some(measurement) => measurement.to_json()
      None => Json::null()
    },
    "raw_input_phase": match raw_input_coordinator {
      Some(coordinator) => {
        match raw_input_token {
          Some(token) => coordinator.mark_publish_finished(token)
          None => ()
        }
        match coordinator.phase_json() {
          Some(phase) => phase
          None => Json::null()
        }
      }
      None => Json::null()
    },
    "raw_render_barrier_armed": match raw_input_coordinator {
      Some(coordinator) => coordinator.render_barrier_armed().to_json()
      None => false.to_json()
    },
    "raw_render_barrier_waiting": match raw_input_coordinator {
      Some(coordinator) => coordinator.render_barrier_waiting().to_json()
      None => false.to_json()
    },
    "event_detail": match model.event_detail {
      Some(detail) => detail.to_json()
      None => Json::null()
    },
    "event_count": model.event_count.to_json(),
    "control_ready": model.control_ready.to_json(),
    "event_install_count": model.event_install_count.to_json(),
    "event_unload_count": model.event_unload_count.to_json(),
    "listening": model.listening.to_json(),
    "rejection": match model.rejection {
      Some(rejection) => rejection.to_json()
      None => Json::null()
    },
    "error": match model.error {
      Some(error) => error.to_json()
      None => Json::null()
    },
  }
  detached_snapshot.val = Json::object(fields).stringify()
  projection_trace_adopted_not_presented()
}

///|
fn preview_document_view(model : DriverModel) -> @rabbita_runtime.Html {
  let source = model.document.source()
  let unavailable = () =>
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
  if selected_projection_placement is ProjectionSynchronous {
    match model.semantic_document {
      Some(document) => semantic_preview_view(source, document)
      None => unavailable()
    }
  } else {
    match model.preview_artifact {
      Some(artifact) => semantic_preview_artifact_view(source, artifact)
      None => unavailable()
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
  let source = raw_input_coordinator.display_source(model.document.source())
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
          match read_raw_selection() {
            Some(selection) =>
              ignore(
                raw_input_coordinator.begin_native_composition(
                  model, source, selection,
                ),
              )
            None => raw_input_coordinator.cancel_pending()
          }
          @rabbita_runtime.none
        })
        .on_compositionend(_ => {
          @cmd.batch([
            raw_input_coordinator.finish_composition(
              model.document.source(),
              emit,
            ),
            raw_input_coordinator.finalize_deferred_composition(model, emit),
          ])
        })
        .on_beforeinput(event => {
          raw_input_coordinator.capture_native_before_input(model, event)
        })
        .on_input(event => {
          if raw_input_event_is_composing(event) {
            raw_input_coordinator.suppress_composing_input_repair()
          }
          @rabbita_runtime.none
        }),
      style=[
        "display:block;min-width:0;min-height:clamp(24rem,70vh,36rem);width:var(--lm-page-width);margin-inline:auto;field-sizing:content;resize:none;overflow:hidden;--rui-control-base-border:transparent;--rui-control-base-shadow:none;background:transparent;padding:1rem var(--lm-page-x-padding);font-family:ui-monospace,SFMono-Regular,Menlo,Monaco,Consolas,\"Liberation Mono\",\"Courier New\",monospace;font-size:1.125rem;line-height:1.65",
      ],
      on_input=@cmd.Emit(source => {
        match read_raw_selection() {
          Some(selection) =>
            if raw_input_coordinator.update_composition(source, selection) {
              @rabbita_runtime.none
            } else {
              let matched = raw_input_coordinator.has_captured_before_input()
              let repair_unmatched = raw_input_coordinator.take_unmatched_input_repair()
              let deferred = raw_input_coordinator.defer_native_input(
                source, selection,
              )
              let active_delivery = raw_input_coordinator.has_active_delivery()
              let input_command = if deferred {
                @rabbita_runtime.none
              } else {
                raw_input_coordinator.enqueue(source, selection, emit)
              }
              if deferred || matched || !repair_unmatched || active_delivery {
                input_command
              } else {
                let repair_epoch = raw_input_coordinator.epoch()
                let repair_selection = rejected_text_selection(
                  model.document.source(),
                  source,
                  selection,
                )
                @cmd.batch([
                  input_command,
                  after_render(
                    scheduler => {
                      ignore(scheduler)
                      guard raw_input_coordinator.epoch() == repair_epoch else {
                        return
                      }
                      @dom_boundary.write_text_value_id(
                        "loomark-input",
                        raw_textarea_value(model.document.source()),
                      )
                      @dom_boundary.write_text_selection_id(
                        "loomark-input", repair_selection,
                      )
                    },
                    emit,
                  ),
                ])
              }
            }
          None => {
            raw_input_coordinator.cancel_pending()
            @rabbita_runtime.none
          }
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
    @core.Preview => preview_document_view(model)
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
  let split_toggle = @rui.button(
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
  let error_view = if model.local_storage_warning {
    @rui.alert(
      id="loomark-error",
      variant=@rui.Destructive,
      style=["border-radius:0"],
      @rui.alert_description("Changes are applied but not saved locally."),
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
                        [block_button, raw_button, preview_button],
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
fn standalone_preview_view(
  model : DriverModel,
  emit : @cmd.Emit[DriverEvent],
  active_view : @rabbita_runtime.Html,
) -> @rabbita_runtime.Html {
  match model.runtime_state {
    EditorRuntimeState::RawRecovery(_) => raw_recovery_view(model, emit)
    _ => {
      let benchmark_controls = if projection_benchmark_enabled {
        @html.button(
          id="loomark-projection-trace-dump",
          type_="button",
          hidden=true,
          attrs=@html.Attrs::build().on_click(
            _ => {
              projection_benchmark_trace_publish()
              @cmd.none
            },
          ),
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

///|
fn driver_event_name(event : DriverEvent) -> String {
  match event {
    Editing(edit_event) =>
      match edit_event {
        ReplaceSource(_) => "source"
        RawInput(_, _) => "raw-input"
        RawNativeInput(..) => "raw-native-input"
        RawSelectionEdit(_) => "raw-selection-edit"
        CommitCapturedRawSelection(_) => "commit-captured-raw-selection"
        BlockFocused(_) => "block-focused"
        BlockHeading(_, _) => "block-heading"
        BlockToggleList(_) => "block-toggle-list"
        BlockDelete => "block-delete"
        BlockInput(..) => "block-input"
        BlockSplit(..) => "block-split"
        BlockMerge(..) => "block-merge"
        BlockNavigate(..) => "block-navigate"
        ProbeBlockSelection(_) => "probe-block-selection"
      }
    Navigation(nav_event) =>
      match nav_event {
        SelectRaw => "select-raw"
        SelectBlock => "select-block"
        SelectPreview => "select-preview"
        ToggleSplitPreview => "toggle-split"
        FocusPreview => "focus-preview"
        FocusBlock => "focus-block"
        FocusRaw => "focus-raw"
        RestoreFocus(_) => "restore-focus"
        FocusRejected(_) => "focus-rejected"
        EffectFailed(_) => "effect-failed"
        BlockSelectionRejected(_, _) => "block-selection-rejected"
      }
    Probe(probe_event) =>
      match probe_event {
        WriteSelection(..) => "write-selection"
        WriteSelectionFailure => "write-selection-failure"
        CaptureRawSelection => "capture-raw-selection"
        RawSelectionCaptured(_) => "raw-selection-captured"
        InstallRawSelection => "install-raw-selection"
        MeasurePreview => "measure-preview"
        MeasureFailure => "measure-failure"
        SelectionRead(..) => "selection-read"
        Measured(..) => "measured"
      }
    Lifecycle(life_event) =>
      match life_event {
        EditorFailure => "editor-failure"
        ForceParserFailure => "force-parser-failure"
        ForceReconstructionFailure => "force-reconstruction-failure"
        ArmRawRenderBarrier => "arm-raw-render-barrier"
        ReleaseRawRenderBarrier => "release-raw-render-barrier"
        RecoveryCopy => "recovery-copy"
        RecoveryDownload => "recovery-download"
        RecoveryReload => "recovery-reload"
        RecoveryEffectFailed(_) => "recovery-effect-failed"
        RestoreSnapshot(..) => "restore-snapshot"
        CustomEvent(_) => "custom-event"
        ControlInstalled => "control-installed"
        SubscriptionInstalled => "subscription-installed"
        SubscriptionUnloaded => "subscription-unloaded"
        InvalidRequest(_) => "invalid-request"
        StopListening => "stop-listening"
        Fatal(_) => "fatal"
        ProjectionWorkerResolved(_, _, _) => "projection-worker-resolved"
        Resize(_) => "resize"
      }
    Archive(_) => "archive-write-completed"
  }
}

///|
/// Decode the private DOM transport without exposing a mutable application
/// handle to the generated JavaScript boundary.
fn parse_driver_event(detail : String) -> DriverEvent {
  if detail == "select-raw" {
    Navigation(SelectRaw)
  } else if detail == "select-block" {
    Navigation(SelectBlock)
  } else if detail == "select-preview" {
    Navigation(SelectPreview)
  } else if detail == "toggle-split" {
    Navigation(ToggleSplitPreview)
  } else if detail == "focus-preview" {
    Navigation(FocusPreview)
  } else if detail == "focus-block" {
    Navigation(FocusBlock)
  } else if detail == "focus-raw" {
    Navigation(FocusRaw)
  } else if detail == "probe-stale-block-selection" {
    Editing(ProbeBlockSelection("stale"))
  } else if detail == "probe-deleted-block-selection" {
    Editing(ProbeBlockSelection("deleted"))
  } else if detail == "write-selection-failure" {
    Probe(WriteSelectionFailure)
  } else if detail == "capture-raw-selection" {
    Probe(CaptureRawSelection)
  } else if detail == "install-raw-selection" {
    Probe(InstallRawSelection)
  } else if detail == "measure-preview" {
    Probe(MeasurePreview)
  } else if detail == "measure-failure" {
    Probe(MeasureFailure)
  } else if detail == "stop-listening" {
    Lifecycle(StopListening)
  } else if detail.has_prefix("source|") {
    Editing(ReplaceSource(detail["source|".length():].to_owned()))
  } else if detail.has_prefix("raw-input|") {
    Editing(RawInput(detail["raw-input|".length():].to_owned(), None))
  } else if detail.has_prefix("raw-selection-edit|") {
    Editing(
      CommitCapturedRawSelection(
        detail["raw-selection-edit|".length():].to_owned(),
      ),
    )
  } else if detail == "editor-failure" {
    Lifecycle(EditorFailure)
  } else if detail == "force-parser-failure" {
    Lifecycle(ForceParserFailure)
  } else if detail == "force-reconstruction-failure" {
    Lifecycle(ForceReconstructionFailure)
  } else if detail == "arm-raw-render-barrier" {
    Lifecycle(ArmRawRenderBarrier)
  } else if detail == "release-raw-render-barrier" {
    Lifecycle(ReleaseRawRenderBarrier)
  } else if detail == "recovery-copy" {
    Lifecycle(RecoveryCopy)
  } else if detail == "recovery-download" {
    Lifecycle(RecoveryDownload)
  } else if detail == "recovery-reload" {
    Lifecycle(RecoveryReload)
  } else if detail.has_prefix("restore-focus|") {
    Navigation(RestoreFocus(detail["restore-focus|".length():].to_owned()))
  } else if detail.has_prefix("restore-snapshot|") {
    let payload = detail["restore-snapshot|".length():].to_owned()
    let parsed = @json.parse(payload) catch {
      _ => return Lifecycle(InvalidRequest("restore-snapshot"))
    }
    match parsed {
      Json::Object(fields) => {
        let version = match fields.get("version") {
          Some(Json::Number(value, ..)) => value.to_int()
          _ => return Lifecycle(InvalidRequest("restore-snapshot"))
        }
        let source = match fields.get("source") {
          Some(Json::String(value)) => value
          _ => return Lifecycle(InvalidRequest("restore-snapshot"))
        }
        let mode = match fields.get("mode") {
          Some(Json::String(value)) =>
            match value {
              "raw" => @core.Raw
              "block" => @core.Block
              "preview" => @core.Preview
              _ => return Lifecycle(InvalidRequest("restore-snapshot"))
            }
          _ => return Lifecycle(InvalidRequest("restore-snapshot"))
        }
        Lifecycle(RestoreSnapshot(version~, source~, mode~))
      }
      _ => Lifecycle(InvalidRequest("restore-snapshot"))
    }
  } else if detail.has_prefix("write-selection|") {
    let parts = detail["write-selection|".length():].split("|").to_array()
    guard parts.length() == 2 else {
      return Lifecycle(InvalidRequest("write-selection"))
    }
    let start = @string.parse_int(parts[0], base=10) catch {
      _ => return Lifecycle(InvalidRequest("write-selection"))
    }
    let end = @string.parse_int(parts[1], base=10) catch {
      _ => return Lifecycle(InvalidRequest("write-selection"))
    }
    Probe(WriteSelection(start~, end~))
  } else if detail.has_prefix("fatal|") {
    Lifecycle(Fatal(detail["fatal|".length():].to_owned()))
  } else {
    Lifecycle(InvalidRequest("unknown"))
  }
}

///|
/// Dispatch one request through the mount-owned DOM event target.
fn dispatch_driver(detail : String) -> Unit {
  @dom_boundary.dispatch_custom_event_id(
    "loomark-driver-target",
    "loomark-driver",
    detail~,
  ) catch {
    _ => ()
  }
}

///|

///|
/// Archive completion channel: tracker acknowledgment always lands, even in
/// fatal state, so an older acknowledgment cannot clear a newer warning.
fn update_archive_tracker(
  model : DriverModel,
  completion : @archive_storage.LocalArchiveWriteCompletion,
) -> (DriverModel, @cmd.Cmd) {
  let tracker = match completion.result() {
    @archive_storage.LocalArchiveStorageWrite::Stored =>
      model.archive_tracker.complete_success(completion.request_id())
    @archive_storage.LocalArchiveStorageWrite::Failed(_) =>
      model.archive_tracker.complete_failure(completion.request_id())
  }
  let next = {
    ..model,
    archive_tracker: tracker,
    local_storage_warning: tracker.has_warning(),
  }
  (next, @rabbita_runtime.none)
}

///|
/// Mode gate for editing-surface events. ReplaceSource is deliberately
/// exempt: driver source replacement works in any mode. The split Preview
/// pairs the Raw textarea with the rendered Preview even while the Preview
/// tab is selected, so Raw input stays live there.
fn editing_mode_applicable(
  event : EditingEvent,
  mode : @core.ApplicationMode,
  split_preview_open : Bool,
) -> String? {
  match event {
    ReplaceSource(_) | ProbeBlockSelection(_) | RawNativeInput(..) => None
    RawInput(_, _) | RawSelectionEdit(_) | CommitCapturedRawSelection(_) =>
      if mode == @core.Raw || (mode == @core.Preview && split_preview_open) {
        None
      } else {
        Some("Raw input is unavailable outside Raw mode")
      }
    BlockFocused(_)
    | BlockHeading(_, _)
    | BlockToggleList(_)
    | BlockDelete
    | BlockInput(..)
    | BlockSplit(..)
    | BlockMerge(..)
    | BlockNavigate(..) =>
      if mode == @core.Block {
        None
      } else {
        Some("Block editing is unavailable outside Block mode")
      }
  }
}

///|
/// Editing-surface dispatcher: mode-gated input and structural requests
/// through the atomic editor façade.
fn update_editing(
  editor : @markdown.MarkdownEditor,
  attachment : @md_markdown.MarkdownSemanticAttachment,
  raw_input_coordinator : RawInputCoordinator,
  block_input_coordinator : BlockInputCoordinator,
  model : DriverModel,
  latest_model : @ref.Ref[DriverModel?],
  event : EditingEvent,
  emit : @cmd.Emit[DriverEvent],
  projection_session? : @ref.Ref[ProjectionSession?],
) -> (DriverModel, @cmd.Cmd) raise {
  let native_token_active = match event {
    RawNativeInput(token~, ..) => raw_input_coordinator.is_active(token)
    _ => true
  }
  if event is RawNativeInput(..) && !native_token_active {
    return (model, @rabbita_runtime.none)
  }
  match event {
    BlockInput(token~, input~) => {
      if !block_input_coordinator.is_active(token) {
        return (model, block_input_coordinator.finish(token, emit))
      }
      if model.state.mode() != @core.Block {
        return (model, block_input_coordinator.finish(token, emit))
      }
      match check_block_edit(model.document_id, editor.version(), input) {
        Current => ()
        WrongDocument | StaleVersion =>
          return (model, block_input_coordinator.finish(token, emit))
      }
    }
    _ => ()
  }
  match
    editing_mode_applicable(event, model.state.mode(), model.split_preview_open) {
    Some(message) => {
      let next = record_error(
        model, "mode-inapplicable", "editor-dispatch", message,
      )
      (next, @rabbita_runtime.none)
    }
    None =>
      match event {
        RawNativeInput(token~, candidate~) => {
          raw_input_coordinator.mark_reducer_started(token)
          let request = normalize_raw_input_candidate(model, candidate)
          raw_input_coordinator.mark_reducer_finished(token)
          match request {
            None => {
              let repair_epoch = raw_input_coordinator.epoch()
              let expected = candidate.before_input.selection
              raw_input_coordinator.discard(token)
              (
                model,
                rejected_raw_input_after_render(
                  latest_model, raw_input_coordinator, repair_epoch, expected, emit,
                ),
              )
            }
            Some(request) => {
              let (next, outcome, persistence_command) = commit_raw_selection_edit(
                editor,
                attachment,
                model,
                request,
                emit,
                editor_started=() => {
                  raw_input_coordinator.mark_editor_started(token)
                },
                editor_finished=() => {
                  raw_input_coordinator.mark_editor_finished(token)
                },
                preview_started=() => {
                  raw_input_coordinator.mark_preview_started(token)
                },
                preview_finished=() => {
                  raw_input_coordinator.mark_preview_finished(token)
                },
                raw_mode_authorized=candidate.raw_mode_authorized,
                projection_session?,
              )
              let (next, selection_command, repair_command) = match outcome {
                RawSelectionEditOutcome::Applied(selection)
                | RawSelectionEditOutcome::Unchanged(selection) =>
                  (
                    next,
                    raw_native_selection_after_render(
                      latest_model, raw_input_coordinator, selection, emit,
                    ),
                    @rabbita_runtime.none,
                  )
                RawSelectionEditOutcome::Rejected(
                  RawSelectionEditRejection::EditorCommitFailed
                ) => {
                  raw_input_coordinator.discard_deferred()
                  let repair_epoch = raw_input_coordinator.epoch()
                  let expected = candidate.before_input.selection
                  (
                    next,
                    @rabbita_runtime.none,
                    rejected_raw_input_after_render(
                      latest_model, raw_input_coordinator, repair_epoch, expected,
                      emit,
                    ),
                  )
                }
                RawSelectionEditOutcome::Rejected(_) => {
                  raw_input_coordinator.discard_deferred()
                  (next, @rabbita_runtime.none, @rabbita_runtime.none)
                }
              }
              let finish_command = raw_input_coordinator.finish(
                token, latest_model, emit,
              )
              (
                next,
                @cmd.batch([
                  persistence_command, selection_command, repair_command, finish_command,
                ]),
              )
            }
          }
        }
        CommitCapturedRawSelection(inserted) =>
          match model.raw_selection {
            None => {
              let next = record_error(
                model, "raw-selection-unavailable", "raw-selection-edit", "Raw selection is unavailable",
              )
              (next, @rabbita_runtime.none)
            }
            Some(selection) =>
              update_editing(
                editor,
                attachment,
                raw_input_coordinator,
                block_input_coordinator,
                model,
                latest_model,
                RawSelectionEdit(
                  ({ selection, inserted } : RawSelectionEditRequest),
                ),
                emit,
                projection_session?,
              )
          }
        RawSelectionEdit(request) => {
          let (next, outcome, persistence_command) = commit_raw_selection_edit(
            editor,
            attachment,
            model,
            request,
            emit,
            projection_session?,
          )
          let (next, selection_command) = match outcome {
            RawSelectionEditOutcome::Applied(selection)
            | RawSelectionEditOutcome::Unchanged(selection) => {
              raw_input_coordinator.cancel_pending()
              (next, raw_selection_after_render(latest_model, selection, emit))
            }
            RawSelectionEditOutcome::Rejected(rejection) =>
              (
                {
                  ..next,
                  rejection: Some(
                    "operation=raw-selection-edit;reason=" +
                    raw_selection_edit_rejection_reason(rejection),
                  ),
                },
                @rabbita_runtime.none,
              )
          }
          (next, @cmd.batch([persistence_command, selection_command]))
        }
        ReplaceSource(source) | RawInput(source, _) => {
          let raw_input_epoch = raw_input_coordinator.epoch()
          let raw_selection = match event {
            RawInput(_, selection) => selection
            _ => None
          }
          let raw_event = event is RawInput(_, _)
          let transition = @core.reduce(
            model.state,
            @core.ApplicationEvent::RequestCanonicalSource(source~),
          )
          let mut next = if raw_event {
            { ..model, text_input_generation: model.text_input_generation + 1 }
          } else {
            model
          }
          let mut restore_raw_value = false
          let mut persistence_command = @rabbita_runtime.none
          for decision in transition.decisions() {
            match decision {
              @core.ReplaceCanonicalSource(source) => {
                let old_requested = preview_requested(next)
                let (committed, accepted, changed, commit_command) = commit_source(
                  editor,
                  next,
                  transition.state(),
                  source,
                  "editor-dispatch",
                  emit,
                  projection_session?,
                )
                next = match projection_session {
                  Some(session) =>
                    update_preview_document_with_projection(
                      attachment,
                      session,
                      committed,
                      old_requested,
                      accepted~,
                      changed~,
                    )
                  None =>
                    update_preview_after_authority(
                      attachment,
                      committed,
                      old_requested,
                      accepted~,
                      changed~,
                    )
                }
                if accepted {
                  raw_input_coordinator.cancel_pending()
                }
                persistence_command = @cmd.batch([
                  persistence_command, commit_command,
                ])
                restore_raw_value = restore_raw_value ||
                  (raw_event && !accepted)
              }
              @core.SnapshotRejected(_) =>
                next = record_error(
                  next, "invalid-snapshot", "editor-dispatch", "snapshot rejected",
                )
            }
          }
          let command = if restore_raw_value {
            let repair_generation = next.text_input_generation
            let repair_source_revision = next.source_revision
            after_render(
              scheduler => {
                ignore(scheduler)
                let accepted_source = next.document.source()
                if raw_input_coordinator.epoch() == raw_input_epoch &&
                  raw_input_repair_eligible(
                    latest_model.val,
                    repair_generation,
                    repair_source_revision,
                  ) {
                  @dom_boundary.write_text_value_id(
                    "loomark-input", accepted_source,
                  )
                  match raw_selection {
                    Some(selection) =>
                      @dom_boundary.write_text_selection_id(
                        "loomark-input",
                        rejected_text_selection(
                          accepted_source, source, selection,
                        ),
                      )
                    None => ()
                  }
                }
              },
              emit,
            )
          } else {
            @rabbita_runtime.none
          }
          (next, @cmd.batch([persistence_command, command]))
        }
        BlockFocused(key) =>
          if model.active_block_key == Some(key) {
            (model, @rabbita_runtime.none)
          } else {
            let (_, selected_index) = model.document
              .blocks()
              .fold(init=(0, None), (state, block) => {
                let (index, found) = state
                (
                  index + 1,
                  match found {
                    Some(_) => found
                    None => if block.key() == key { Some(index) } else { None }
                  },
                )
              })
            match selected_index {
              None => {
                let next = record_error(
                  model, "block-selection-rejected", "editor-dispatch", "focused block is unavailable",
                )
                (next, @rabbita_runtime.none)
              }
              Some(index) => {
                let next = { ..model, active_block_key: Some(key) }
                (
                  next,
                  after_render(
                    scheduler => {
                      ignore(scheduler)
                      @dom_boundary.focus_id(block_input_id(index))
                    },
                    emit,
                  ),
                )
              }
            }
          }
        BlockHeading(requested_level, originating_selection) =>
          match block_format_target(model, originating_selection) {
            None => {
              let next = record_error(
                model, "block-selection-rejected", "editor-dispatch", "formatting requires an active block",
              )
              (next, @rabbita_runtime.none)
            }
            Some(block) => {
              guard block_allows_heading(block.kind()) else {
                let command = originating_selection
                  .map(selection => {
                    block_selection_after_render(
                      latest_model,
                      selection,
                      model.source_revision,
                      report_superseded=true,
                      emit,
                    )
                  })
                  .unwrap_or(@rabbita_runtime.none)
                return (model, command)
              }
              if requested_level == 0 && block.kind() is @markdown.Paragraph {
                let command = originating_selection
                  .map(selection => {
                    block_selection_after_render(
                      latest_model,
                      selection,
                      model.source_revision,
                      report_superseded=true,
                      emit,
                    )
                  })
                  .unwrap_or(@rabbita_runtime.none)
                return (model, command)
              }
              let target_level = match block.kind() {
                @markdown.Heading(level~) if level == requested_level => 0
                _ => requested_level
              }
              let (next, applied, command) = commit_block_toolbar_request(
                editor,
                attachment,
                model,
                latest_model,
                @markdown.MarkdownEditRequest::ChangeHeadingLevel(
                  node_id=block.node_id(),
                  level=target_level,
                ),
                originating_selection,
                "loomark-heading-" + requested_level.to_string(),
                emit,
                projection_session?,
              )
              if applied {
                raw_input_coordinator.cancel_pending()
              }
              (next, command)
            }
          }
        BlockToggleList(originating_selection) =>
          match block_format_target(model, originating_selection) {
            None => {
              let next = record_error(
                model, "block-selection-rejected", "editor-dispatch", "formatting requires an active block",
              )
              (next, @rabbita_runtime.none)
            }
            Some(block) => {
              guard block_allows_list(block.kind()) else {
                let command = originating_selection
                  .map(selection => {
                    block_selection_after_render(
                      latest_model,
                      selection,
                      model.source_revision,
                      report_superseded=true,
                      emit,
                    )
                  })
                  .unwrap_or(@rabbita_runtime.none)
                return (model, command)
              }
              let (next, applied, command) = commit_block_toolbar_request(
                editor,
                attachment,
                model,
                latest_model,
                @markdown.MarkdownEditRequest::ToggleListItem(
                  node_id=block.node_id(),
                ),
                originating_selection,
                "loomark-toggle-list",
                emit,
                projection_session?,
              )
              if applied {
                raw_input_coordinator.cancel_pending()
              }
              (next, command)
            }
          }
        BlockDelete =>
          match active_block(model) {
            None => {
              let next = record_error(
                model, "block-selection-rejected", "editor-dispatch", "deletion requires an active block",
              )
              (next, @rabbita_runtime.none)
            }
            Some(block) => {
              let (next, applied, command) = commit_block_toolbar_request(
                editor,
                attachment,
                model,
                latest_model,
                @markdown.MarkdownEditRequest::Delete(node_id=block.node_id()),
                None,
                "loomark-delete-block",
                emit,
                projection_session?,
              )
              if applied {
                raw_input_coordinator.cancel_pending()
              }
              (next, command)
            }
          }
        BlockInput(token~, input~) => {
          match check_block_selection(model.document, input) {
            ValidBlockSelection => ()
            NonCollapsedBlockSelection
            | InvalidBlockSelection
            | MissingBlockSelectionTarget =>
              return (model, block_input_coordinator.finish(token, emit))
          }
          if !block_input_coordinator.is_active(token) {
            return (model, block_input_coordinator.finish(token, emit))
          }
          match check_block_edit(model.document_id, editor.version(), input) {
            Current => ()
            WrongDocument | StaleVersion =>
              return (model, block_input_coordinator.finish(token, emit))
          }
          let (next, committed_selection, accepted, persistence_command) = commit_block_request(
            editor,
            attachment,
            model,
            @markdown.MarkdownEditRequest::CommitTextControlEdit(
              node_id=input.node_id,
              new_text=input.text,
            ),
            "editor-dispatch",
            emit,
            projection_session?,
          )
          let finish_command = block_input_coordinator.finish(token, emit)
          if accepted && next.source_revision != model.source_revision {
            raw_input_coordinator.cancel_pending()
          }
          let selection = match committed_selection {
            Some(selection) =>
              block_selection_from_commit(
                next.document,
                selection,
                offset=input.selection.end(),
              )
            None => None
          }
          let next = if accepted {
            {
              ..next,
              text_input_generation: model.text_input_generation + 1,
              active_block_key: match selection {
                Some(selection) => Some(selection.key)
                None => model.active_block_key
              },
              selection: match selection {
                Some(selection) => Some(block_selection_label(selection))
                None => None
              },
            }
          } else {
            next
          }
          match selection {
            Some(selection) =>
              // Clearing the final payload can install the façade's empty
              // paragraph sentinel and replace the rendered control. Ordinary
              // input keeps the browser's native caret and must not queue an
              // older caret write over newer keystrokes.
              if input.text == "" {
                (
                  next,
                  @cmd.batch([
                    persistence_command,
                    finish_command,
                    block_selection_after_render(
                      latest_model,
                      selection,
                      next.source_revision,
                      report_superseded=false,
                      emit,
                    ),
                  ]),
                )
              } else {
                (next, @cmd.batch([persistence_command, finish_command]))
              }
            None =>
              if accepted {
                (next, @cmd.batch([persistence_command, finish_command]))
              } else {
                let accepted_text = next.document
                  .blocks()
                  .fold(init=None, (found, block) => {
                    match found {
                      Some(_) => found
                      None =>
                        if block.node_id() == input.node_id {
                          Some(block.text())
                        } else {
                          None
                        }
                    }
                  })
                match accepted_text {
                  Some(text) => {
                    let offset = rejected_text_offset(
                      text,
                      input.text,
                      input.selection.end(),
                    )
                    let repair_generation = next.text_input_generation
                    let repair_source_revision = next.source_revision
                    (
                      next,
                      @cmd.batch([
                        persistence_command,
                        finish_command,
                        after_render(
                          scheduler => {
                            ignore(scheduler)
                            if repair_eligible(
                                latest_model.val,
                                @core.Block,
                                repair_generation,
                                repair_source_revision,
                              ) {
                              @dom_boundary.write_text_value_id(
                                input.input_id,
                                text,
                              )
                              @dom_boundary.focus_id(input.input_id)
                              @dom_boundary.write_text_selection_id(
                                input.input_id,
                                @dom_boundary.TextSelection(
                                  offset,
                                  offset,
                                  @dom_boundary.NoDirection,
                                ),
                              )
                            }
                          },
                          emit,
                        ),
                      ]),
                    )
                  }
                  None =>
                    (next, @cmd.batch([persistence_command, finish_command]))
                }
              }
          }
        }
        BlockSplit(node_id~, offset~) => {
          let (next, committed_selection, accepted, persistence_command) = commit_block_request(
            editor,
            attachment,
            model,
            @markdown.MarkdownEditRequest::SplitBlock(node_id~, offset~),
            "editor-dispatch",
            emit,
            projection_session?,
          )
          if accepted && next.source_revision != model.source_revision {
            raw_input_coordinator.cancel_pending()
          }
          let selection = match committed_selection {
            Some(selection) =>
              block_selection_from_commit(next.document, selection)
            None => None
          }
          let next = {
            ..next,
            active_block_key: match selection {
              Some(selection) => Some(selection.key)
              None => model.active_block_key
            },
            selection: match selection {
              Some(selection) => Some(block_selection_label(selection))
              None => None
            },
          }
          match selection {
            Some(selection) =>
              (
                next,
                @cmd.batch([
                  persistence_command,
                  block_selection_after_render(
                    latest_model,
                    selection,
                    next.source_revision,
                    report_superseded=false,
                    emit,
                  ),
                ]),
              )
            None => (next, persistence_command)
          }
        }
        BlockMerge(node_id~, selection=originating_selection) => {
          let (next, committed_selection, accepted, persistence_command) = commit_block_request(
            editor,
            attachment,
            model,
            @markdown.MarkdownEditRequest::MergeWithPrevious(node_id~),
            "editor-dispatch",
            emit,
            projection_session?,
          )
          if accepted && next.source_revision != model.source_revision {
            raw_input_coordinator.cancel_pending()
          }
          let resolved_selection = match committed_selection {
            Some(selection) =>
              block_selection_from_commit(next.document, selection)
            None => None
          }
          let next = {
            ..next,
            active_block_key: match resolved_selection {
              Some(selection) => Some(selection.key)
              None => model.active_block_key
            },
            selection: match resolved_selection {
              Some(selection) => Some(block_selection_label(selection))
              None => None
            },
          }
          match resolved_selection {
            Some(selection) =>
              (
                next,
                @cmd.batch([
                  persistence_command,
                  block_selection_after_render(
                    latest_model,
                    selection,
                    next.source_revision,
                    report_superseded=false,
                    emit,
                  ),
                ]),
              )
            None =>
              (
                next,
                @cmd.batch([
                  persistence_command,
                  block_selection_after_render(
                    latest_model,
                    originating_selection,
                    next.source_revision,
                    report_superseded=true,
                    emit,
                  ),
                ]),
              )
          }
        }
        BlockNavigate(key~, direction~) =>
          match block_navigation_selection(model.document, key, direction) {
            None => (model, @rabbita_runtime.none)
            Some(selection) => {
              let next = {
                ..model,
                active_block_key: Some(selection.key),
                selection: Some(block_selection_label(selection)),
              }
              (
                next,
                block_selection_after_render(
                  latest_model,
                  selection,
                  next.source_revision,
                  report_superseded=true,
                  emit,
                ),
              )
            }
          }
        ProbeBlockSelection(kind) => {
          let blocks = model.document.blocks().to_array()
          if blocks.is_empty() {
            let next = record_error(
              model, "block-selection-rejected", "browser-effect", "block selection probe has no target",
            )
            (next, @rabbita_runtime.none)
          } else {
            let block = blocks[0]
            let selection = BlockSelection::{
              key: block.key(),
              index: 0,
              start: 0,
              end: 0,
            }
            let previous_revision = model.source_revision
            let source = if kind == "deleted" { "" } else { "replacement\n" }
            let (committed, accepted, changed, persistence_command) = commit_source(
              editor,
              model,
              model.state,
              source,
              "editor-dispatch",
              emit,
              projection_session?,
            )
            let next = match projection_session {
              Some(session) =>
                update_preview_document_with_projection(
                  attachment,
                  session,
                  committed,
                  preview_requested(model),
                  accepted~,
                  changed~,
                )
              None =>
                update_preview_after_authority(
                  attachment,
                  committed,
                  preview_requested(model),
                  accepted~,
                  changed~,
                )
            }
            if accepted && changed {
              raw_input_coordinator.cancel_pending()
            }
            let expected_revision = if kind == "stale" {
              previous_revision
            } else {
              next.source_revision
            }
            (
              next,
              @cmd.batch([
                persistence_command,
                block_selection_after_render(
                  latest_model,
                  selection,
                  expected_revision,
                  report_superseded=true,
                  emit,
                ),
              ]),
            )
          }
        }
      }
  }
}

///|
/// View-surface dispatcher: mode selection, split, focus commands, and the
/// effect reports that accompany them. Not mode-gated.
fn update_navigation(
  attachment : @md_markdown.MarkdownSemanticAttachment,
  raw_input_coordinator : RawInputCoordinator,
  block_input_coordinator : BlockInputCoordinator,
  model : DriverModel,
  latest_model : @ref.Ref[DriverModel?],
  event : NavigationEvent,
  emit : @cmd.Emit[DriverEvent],
  projection_session? : @ref.Ref[ProjectionSession?],
) -> (DriverModel, @cmd.Cmd) {
  match event {
    SelectRaw | SelectBlock | SelectPreview => {
      // The outer or-pattern already narrowed `event` to the Select*
      // variants; `_` is required because this inner match re-matches the
      // full NavigationEvent type.
      let mode = match event {
        SelectRaw => @core.Raw
        SelectBlock => @core.Block
        SelectPreview => @core.Preview
        _ => @core.Raw
      }
      if mode != model.state.mode() {
        raw_input_coordinator.cancel_pending_for_navigation()
        block_input_coordinator.cancel_pending()
      }
      let transition = @core.reduce(
        model.state,
        @core.ApplicationEvent::SelectMode(mode~),
      )
      let old_requested = preview_requested(model)
      let next_model = { ..model, state: transition.state() }
      let next = match projection_session {
        Some(session) =>
          update_preview_document_with_projection(
            attachment,
            session,
            next_model,
            old_requested,
            accepted=true,
            changed=false,
          )
        None =>
          update_preview_after_authority(
            attachment,
            next_model,
            old_requested,
            accepted=true,
            changed=false,
          )
      }
      (next, @rabbita_runtime.none)
    }
    ToggleSplitPreview => {
      if model.state.mode() == @core.Preview && model.split_preview_open {
        raw_input_coordinator.cancel_pending_for_navigation()
      }
      let old_requested = preview_requested(model)
      let next_model = {
        ..model,
        split_preview_open: !model.split_preview_open,
      }
      let next = match projection_session {
        Some(session) =>
          update_preview_document_with_projection(
            attachment,
            session,
            next_model,
            old_requested,
            accepted=true,
            changed=false,
          )
        None =>
          update_preview_after_authority(
            attachment,
            next_model,
            old_requested,
            accepted=true,
            changed=false,
          )
      }
      (next, @rabbita_runtime.none)
    }
    FocusRaw | FocusBlock | FocusPreview => {
      // The outer or-pattern already narrowed `event` to the Focus*
      // variants; `_` is required because this inner match re-matches the
      // full NavigationEvent type.
      let target = match event {
        FocusRaw => @core.RawEditor
        FocusBlock => @core.BlockEditor
        FocusPreview => @core.PreviewControl
        _ => @core.PreviewControl
      }
      let locator = @core.FocusLocator(
        target~,
        source_revision=model.source_revision,
      )
      let token = encode_focus_token(target, model.source_revision)
      match @core.decide_focus(model.state, model.source_revision, locator) {
        @core.Compatible(_) => {
          let next = match target {
            @core.BlockEditor => {
              let active_block_key = model.document
                .blocks()
                .get(0)
                .map(block => block.key())
              { ..model, active_block_key, }
            }
            _ => model
          }
          (next, focus_latest_after_render(latest_model, locator, token, emit))
        }
        @core.Rejected(error) => reject_focus(model, error)
      }
    }
    FocusRejected(error) => reject_focus(model, error)
    RestoreFocus(token) =>
      match decode_focus_token(token) {
        Ok(locator) =>
          match
            @core.decide_focus(model.state, model.source_revision, locator) {
            @core.Compatible(target) => {
              let next = match target {
                @core.BlockEditor => {
                  let active_block_key = model.document
                    .blocks()
                    .get(0)
                    .map(block => block.key())
                  { ..model, active_block_key, }
                }
                _ => model
              }
              (
                next,
                focus_latest_after_render(latest_model, locator, token, emit),
              )
            }
            @core.Rejected(error) => reject_focus(model, error)
          }
        Err(error) => reject_focus_token(model, error)
      }
    EffectFailed(message) => {
      let next = record_error(
        model, "browser-effect-failed", "browser-effect", message,
      )
      (next, @rabbita_runtime.none)
    }
    BlockSelectionRejected(message, selection) => {
      let next = record_error(
        model, "block-selection-rejected", "browser-effect", message,
      )
      let command = match selection {
        Some(selection) =>
          block_selection_after_render(
            latest_model,
            selection,
            next.source_revision,
            report_superseded=true,
            emit,
          )
        None => @rabbita_runtime.none
      }
      (next, command)
    }
  }
}

///|
/// Apply a driver selection-read result to the probe model. Pure.
fn apply_selection_read(
  model : DriverModel,
  start : Int,
  end : Int,
) -> DriverModel {
  { ..model, selection: Some(start.to_string() + ":" + end.to_string()) }
}

///|
/// Apply a driver measurement result to the probe model. Pure.
fn apply_measurement(
  model : DriverModel,
  width : Double,
  height : Double,
) -> DriverModel {
  { ..model, measurement: Some(width.to_string() + ":" + height.to_string()) }
}

///|
/// Driver/test instrumentation dispatcher: probes, measurements, and their
/// outbound results.
fn update_probe(
  model : DriverModel,
  latest_model : @ref.Ref[DriverModel?],
  event : ProbeEvent,
  emit : @cmd.Emit[DriverEvent],
) -> (DriverModel, @cmd.Cmd) {
  match event {
    WriteSelection(start~, end~) =>
      (
        model,
        after_render(
          scheduler => {
            let selection = @dom_boundary.TextSelection(
              start,
              end,
              @dom_boundary.NoDirection,
            )
            @dom_boundary.write_text_selection_id("loomark-input", selection)
            let read = @dom_boundary.read_text_selection_id("loomark-input")
            scheduler.add(
              emit(Probe(SelectionRead(start=read.start(), end=read.end()))),
            )
          },
          emit,
        ),
      )
    WriteSelectionFailure =>
      (
        model,
        after_render(
          scheduler => {
            ignore(scheduler)
            let selection = @dom_boundary.TextSelection(
              0,
              1,
              @dom_boundary.NoDirection,
            )
            @dom_boundary.write_text_selection_id(
              "loomark-missing-input", selection,
            )
          },
          emit,
        ),
      )
    CaptureRawSelection =>
      (
        model,
        after_render(
          scheduler => {
            let selection = @dom_boundary.read_text_selection_id(
              "loomark-input",
            )
            scheduler.add(emit(Probe(RawSelectionCaptured(selection))))
          },
          emit,
        ),
      )
    RawSelectionCaptured(selection) => {
      let bound = versioned_raw_selection_from_dom(model, selection) catch {
        error => {
          let next = record_error(
            model,
            "invalid-raw-selection",
            "browser-effect",
            raw_dom_selection_conversion_error_detail(error),
          )
          return (next, @rabbita_runtime.none)
        }
      }
      let markdown = bound.selection
      (
        {
          ..model,
          raw_selection: Some(bound),
          selection: Some(
            markdown.anchor().to_string() + ":" + markdown.head().to_string(),
          ),
        },
        @rabbita_runtime.none,
      )
    }
    InstallRawSelection =>
      (
        model,
        match model.raw_selection {
          Some(selection) =>
            raw_selection_after_render(latest_model, selection, emit)
          None => @rabbita_runtime.none
        },
      )
    MeasurePreview =>
      (
        model,
        after_render(
          scheduler => {
            let measurement = @dom_boundary.measure_element_id(
              "loomark-preview",
            )
            scheduler.add(
              emit(
                Probe(
                  Measured(
                    width=measurement.offset_width(),
                    height=measurement.offset_height(),
                  ),
                ),
              ),
            )
          },
          emit,
        ),
      )
    MeasureFailure =>
      (
        model,
        after_render(
          scheduler => {
            ignore(scheduler)
            ignore(@dom_boundary.measure_element_id("loomark-missing-preview"))
          },
          emit,
        ),
      )
    SelectionRead(start~, end~) =>
      (apply_selection_read(model, start, end), @rabbita_runtime.none)
    Measured(width~, height~) =>
      (apply_measurement(model, width, height), @rabbita_runtime.none)
  }
}

///|
/// Run a recovery action immediately in the originating activation turn and
/// route boundary failures back through an allowed recovery event.
fn recovery_effect_command(
  effect : () -> Unit raise @dom_boundary.DomBoundaryError,
  emit : @cmd.Emit[DriverEvent],
) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    effect() catch {
      error =>
        scheduler.add(emit(Lifecycle(RecoveryEffectFailed(error.message()))))
    }
  })
}

///|
/// Application-control dispatcher: failures, restore, subscriptions, fatal,
/// resize, and driver protocol errors.
fn update_lifecycle(
  editor : @markdown.MarkdownEditor,
  attachment : @md_markdown.MarkdownSemanticAttachment,
  raw_input_coordinator : RawInputCoordinator,
  block_input_coordinator : BlockInputCoordinator,
  model : DriverModel,
  event : LifecycleEvent,
  emit : @cmd.Emit[DriverEvent],
  projection_session? : @ref.Ref[ProjectionSession?],
  projection_worker? : ProjectionWorkerRuntime,
) -> (DriverModel, @cmd.Cmd) raise {
  match event {
    EditorFailure => {
      let next = { ..model, fail_next_editor_commit: true }
      (next, @rabbita_runtime.none)
    }
    ForceParserFailure => {
      let next = { ..model, force_parser_failure: true }
      (next, @rabbita_runtime.none)
    }
    ForceReconstructionFailure => {
      let next = { ..model, force_reconstruction_failure: true }
      (next, @rabbita_runtime.none)
    }
    ArmRawRenderBarrier => {
      raw_input_coordinator.arm_render_barrier()
      (model, @rabbita_runtime.none)
    }
    ReleaseRawRenderBarrier =>
      (model, raw_input_coordinator.release_render_barrier())
    RecoveryCopy =>
      (
        model,
        recovery_effect_command(
          () => @dom_boundary.copy_text(runtime_source(model)),
          emit,
        ),
      )
    RecoveryDownload =>
      (
        model,
        recovery_effect_command(
          () => {
            @dom_boundary.download_text(
              "loomark-recovered.md",
              runtime_source(model),
            )
          },
          emit,
        ),
      )
    RecoveryReload =>
      (model, recovery_effect_command(() => @dom_boundary.reload(), emit))
    RecoveryEffectFailed(detail) =>
      (
        {
          ..model,
          error: Some("Recovery action failed: " + detail),
          error_code: Some("recovery-effect-failed"),
          error_operation: Some("recovery-action"),
        },
        @rabbita_runtime.none,
      )
    RestoreSnapshot(version~, source~, mode~) => {
      let snapshot = @core.ApplicationStateSnapshot::ApplicationStateSnapshot(
        version~,
        source~,
        mode~,
      )
      let transition = @core.reduce(
        model.state,
        @core.ApplicationEvent::RestoreSnapshot(
          snapshot~,
          canonical_source=model.document.source(),
        ),
      )
      let mut next = model
      let mut accepted = true
      let mut source_changed = false
      let mut persistence_command = @rabbita_runtime.none
      for decision in transition.decisions() {
        match decision {
          @core.ReplaceCanonicalSource(source) => {
            let (committed, commit_accepted, changed, commit_command) = commit_source(
              editor,
              next,
              transition.state(),
              source,
              "restore-snapshot",
              emit,
              projection_session?,
            )
            next = committed
            accepted = accepted && commit_accepted
            source_changed = source_changed || changed
            persistence_command = @cmd.batch([
              persistence_command, commit_command,
            ])
          }
          @core.SnapshotRejected(error) => {
            accepted = false
            let message = match error {
              @core.UnsupportedSnapshotVersion(version) =>
                "unsupported snapshot version: " + version.to_string()
            }
            next = record_error(
              next, "unsupported-snapshot-version", "restore-snapshot", message,
            )
          }
        }
      }
      if accepted {
        raw_input_coordinator.cancel_pending()
        block_input_coordinator.cancel_pending()
        next = { ..next, state: transition.state() }
      }
      next = match projection_session {
        Some(session) =>
          update_preview_document_with_projection(
            attachment,
            session,
            next,
            preview_requested(model),
            accepted~,
            changed=source_changed,
          )
        None =>
          update_preview_after_authority(
            attachment,
            next,
            preview_requested(model),
            accepted~,
            changed=source_changed,
          )
      }
      (next, persistence_command)
    }
    CustomEvent(detail) => {
      let next = {
        ..model,
        event_detail: Some(detail),
        event_count: model.event_count + 1,
      }
      (next, @rabbita_runtime.none)
    }
    ControlInstalled => {
      let next = { ..model, control_ready: true }
      (next, @rabbita_runtime.none)
    }
    SubscriptionInstalled => {
      let next = { ..model, event_install_count: model.event_install_count + 1 }
      (next, @rabbita_runtime.none)
    }
    SubscriptionUnloaded => {
      let next = { ..model, event_unload_count: model.event_unload_count + 1 }
      (next, @rabbita_runtime.none)
    }
    InvalidRequest(message) => {
      let code = if message == "restore-snapshot" {
        "invalid-snapshot"
      } else {
        "invalid-request"
      }
      let next = record_error(
        model,
        code,
        "editor-dispatch",
        "invalid driver request: " + message,
      )
      (next, @rabbita_runtime.none)
    }
    StopListening => {
      let next = { ..model, listening: false }
      (next, @rabbita_runtime.none)
    }
    Fatal(message) => {
      raw_input_coordinator.cancel_pending()
      block_input_coordinator.cancel_pending()
      let next = { ..model, fatal: true, error: Some(message), rejection: None }
      (next, @rabbita_runtime.none)
    }
    ProjectionWorkerResolved(request_id, expected, raw) =>
      match projection_worker {
        None => (model, @rabbita_runtime.none)
        Some(worker) => {
          guard worker.accepts(request_id, expected) else {
            return (model, @rabbita_runtime.none)
          }
          match projection_worker_response_artifact(raw) {
            Err(detail) => worker.recover(model, emit, detail)
            Ok((response_request_id, stamp, artifact)) =>
              if response_request_id != request_id || stamp != expected {
                worker.recover(
                  model, emit, "projection Worker response envelope mismatch",
                )
              } else {
                worker.mark_healthy()
                match artifact {
                  None => (model, @rabbita_runtime.none)
                  Some(preview_artifact) => {
                    let projection_error = model.error_code ==
                      Some("projection-failed") ||
                      model.error_code == Some("projection-pending")
                    (
                      {
                        ..model,
                        semantic_document: None,
                        preview_artifact: Some(preview_artifact),
                        semantic_read_count: model.semantic_read_count + 1,
                        error: if projection_error {
                          None
                        } else {
                          model.error
                        },
                        error_code: if projection_error {
                          None
                        } else {
                          model.error_code
                        },
                        error_operation: if projection_error {
                          None
                        } else {
                          model.error_operation
                        },
                      },
                      @rabbita_runtime.none,
                    )
                  }
                }
              }
          }
        }
      }
    Resize(viewport) => {
      let next = {
        ..model,
        compact_split: compact_split_for_width(viewport.width),
        resize_count: model.resize_count + 1,
      }
      (next, @rabbita_runtime.none)
    }
  }
}

///|
fn recovery_control_event(event : DriverEvent) -> Bool {
  match event {
    Lifecycle(
      RecoveryCopy
      | RecoveryDownload
      | RecoveryReload
      | RecoveryEffectFailed(_)
    ) => true
    _ => false
  }
}

///|
/// Total dispatch: the envelope constructor encodes the concern, so routing
/// cannot misclassify. Archive completions land even in fatal state; recovery
/// controls remain available while every editing event is rejected.
fn update_model(
  editor : @markdown.MarkdownEditor,
  attachment : @md_markdown.MarkdownSemanticAttachment,
  raw_input_coordinator : RawInputCoordinator,
  block_input_coordinator : BlockInputCoordinator,
  model : DriverModel,
  latest_model : @ref.Ref[DriverModel?],
  event : DriverEvent,
  emit : @cmd.Emit[DriverEvent],
  projection_session? : @ref.Ref[ProjectionSession?],
  projection_worker? : ProjectionWorkerRuntime,
) -> (DriverModel, @cmd.Cmd) raise {
  let (next, command) = match event {
    Archive(completion) => update_archive_tracker(model, completion)
    _ if model.fatal && !recovery_control_event(event) => {
      match event {
        Editing(RawNativeInput(token~, ..)) =>
          raw_input_coordinator.cancel(token)
        Editing(BlockInput(..)) => block_input_coordinator.cancel_pending()
        _ => ()
      }
      let next = {
        ..model,
        rejection: Some(
          "operation=" + driver_event_name(event) + ";reason=fatal-state",
        ),
      }
      (next, @rabbita_runtime.none)
    }
    Editing(edit_event) =>
      update_editing(
        editor,
        attachment,
        raw_input_coordinator,
        block_input_coordinator,
        model,
        latest_model,
        edit_event,
        emit,
        projection_session?,
      )
    Navigation(nav_event) =>
      update_navigation(
        attachment,
        raw_input_coordinator,
        block_input_coordinator,
        model,
        latest_model,
        nav_event,
        emit,
        projection_session?,
      )
    Probe(probe_event) => update_probe(model, latest_model, probe_event, emit)
    Lifecycle(life_event) =>
      update_lifecycle(
        editor,
        attachment,
        raw_input_coordinator,
        block_input_coordinator,
        model,
        life_event,
        emit,
        projection_session?,
        projection_worker?,
      )
  }
  let next = match projection_session {
    None => next
    Some(session_ref) =>
      match session_ref.val {
        None => next
        Some(session) => update_projection_demand(session, next)
      }
  }
  let raw_input_token = match event {
    Editing(RawNativeInput(token~, ..)) => Some(token)
    _ => None
  }
  projection_trace_driver_model_adopted()
  publish(next, Some(raw_input_coordinator), raw_input_token)
  (next, command)
}

///|
fn driver_control_subscription_loader(
  payload : Error,
  scheduler : &@cmd.Scheduler,
) -> @sub.RunningSub? {
  match payload {
    DriverSubscription::Control(emit) => {
      let mut tagger = emit
      let mut disposed = false
      let mut subscription : @dom_boundary.CustomEventSubscription? = None
      let install = _ => {
        guard !disposed && subscription is None else { return }
        subscription = Some(
          @dom_boundary.listen_custom_event_id(
            "loomark-driver-target",
            "loomark-driver",
            detail => {
              guard !disposed else { return }
              scheduler.add(tagger(parse_driver_event(detail)))
            },
          ),
        ) catch {
          _ => None
        }
        match subscription {
          Some(_) => scheduler.add(tagger(Lifecycle(ControlInstalled)))
          None => ()
        }
      }
      scheduler.run_effect(@cmd.AfterRender, install)
      Some({
        unload: _ => {
          if !disposed {
            disposed = true
            match subscription {
              Some(running) => running.dispose() catch { _ => () }
              None => ()
            }
          }
        },
        update_tagger: payload => {
          guard payload is DriverSubscription::Control(new_emit) else { return }
          guard !disposed else { return }
          tagger = new_emit
        },
      })
    }
    _ => None
  }
}

///|
fn driver_test_subscription_loader(
  payload : Error,
  scheduler : &@cmd.Scheduler,
) -> @sub.RunningSub? {
  match payload {
    DriverSubscription::Test(emit, lifecycle) => {
      let mut tagger = emit
      let mut lifecycle_tagger = lifecycle
      let mut disposed = false
      let mut installed = false
      let mut subscription : @dom_boundary.CustomEventSubscription? = None
      let install = _ => {
        guard !disposed && subscription is None else { return }
        subscription = Some(
          @dom_boundary.listen_custom_event_id(
            "loomark-event-target",
            "loomark-test",
            detail => {
              guard !disposed else { return }
              scheduler.add(tagger(detail))
            },
          ),
        ) catch {
          _ => None
        }
        match subscription {
          Some(_) => {
            installed = true
            scheduler.add(lifecycle_tagger(Lifecycle(SubscriptionInstalled)))
          }
          None => ()
        }
      }
      scheduler.run_effect(@cmd.AfterRender, install)
      Some({
        unload: scheduler => {
          if !disposed {
            disposed = true
            match subscription {
              Some(running) => {
                running.dispose() catch {
                  _ => ()
                }
                subscription = None
              }
              None => ()
            }
            if installed {
              installed = false
              scheduler.add(lifecycle_tagger(Lifecycle(SubscriptionUnloaded)))
            }
          }
        },
        update_tagger: payload => {
          guard payload is DriverSubscription::Test(new_emit, new_lifecycle) else {
            return
          }
          guard !disposed else { return }
          tagger = new_emit
          lifecycle_tagger = new_lifecycle
        },
      })
    }
    _ => None
  }
}

///|
fn projection_worker_lifetime_loader(
  payload : Error,
  _scheduler : &@cmd.Scheduler,
) -> @sub.RunningSub? {
  match payload {
    DriverSubscription::WorkerLifetime(worker) =>
      Some({
        unload: _ => worker.dispose(),
        update_tagger: payload => {
          guard payload is DriverSubscription::WorkerLifetime(_) else { return }
        },
      })
    _ => None
  }
}

///|
fn driver_control_subscription(emit : @cmd.Emit[DriverEvent]) -> @sub.Sub {
  @sub.custom_sub(
    "loomark.driver-control",
    @sub.Local,
    DriverSubscription::Control(emit),
    driver_control_subscription_loader,
  )
}

///|
fn driver_test_subscription(
  emit : @cmd.Emit[DriverEvent],
  source : String,
) -> @sub.Sub {
  @sub.custom_sub(
    "loomark.driver-event",
    @sub.Local,
    DriverSubscription::Test(
      emit.map(detail => Lifecycle(CustomEvent(detail + "|" + source))),
      emit,
    ),
    driver_test_subscription_loader,
  )
}

///|
fn projection_worker_subscription(worker : ProjectionWorkerRuntime) -> @sub.Sub {
  @sub.custom_sub(
    "loomark.projection-worker-lifetime",
    @sub.Local,
    DriverSubscription::WorkerLifetime(worker),
    projection_worker_lifetime_loader,
  )
}

///|
fn standalone_subscriptions(
  model : DriverModel,
  emit : @cmd.Emit[DriverEvent],
) -> @sub.Sub {
  if model.fatal {
    @sub.none
  } else {
    @sub.on_resize(emit.map(viewport => Lifecycle(Resize(viewport))))
  }
}

///|
fn private_dev_host_subscriptions(
  model : DriverModel,
  emit : @cmd.Emit[DriverEvent],
) -> @sub.Sub {
  let control = driver_control_subscription(emit)
  if !model.listening || model.fatal {
    control
  } else {
    @sub.batch([
      @sub.on_resize(emit.map(viewport => Lifecycle(Resize(viewport)))),
      driver_test_subscription(emit, model.document.source()),
      control,
    ])
  }
}

///|
fn build_application(
  editor : @markdown.MarkdownEditor,
  attachment : @md_markdown.MarkdownSemanticAttachment,
  initial : DriverModel,
  baseline : (@repository.LocalArchiveRequestId, String)?,
  raw_input_telemetry : RawInputTelemetry?,
  subscriptions : (DriverModel, @cmd.Emit[DriverEvent]) -> @sub.Sub,
  view : (DriverModel, @cmd.Emit[DriverEvent], @rabbita_runtime.Html) -> @rabbita_runtime.Html,
  projection_session? : @ref.Ref[ProjectionSession?],
) -> @rabbita_runtime.App {
  projection_benchmark_trace_enable()
  let current_session : @ref.Ref[EditorSession] = {
    val: { editor, attachment },
  }
  let latest_model : @ref.Ref[DriverModel?] = { val: None }
  let raw_input_coordinator = RawInputCoordinator::RawInputCoordinator(
    raw_input_telemetry,
  )
  let block_input_coordinator = BlockInputCoordinator::BlockInputCoordinator()
  let projection_worker = match selected_projection_placement {
    ProjectionWorker =>
      Some(
        ProjectionWorkerRuntime::new("loomark-production-projection"),
      )
    ProjectionInProcess =>
      Some(
        ProjectionWorkerRuntime::new_in_process("loomark-comparison-projection"),
      )
    ProjectionSynchronous => None
  }
  let application_subscriptions = (model, emit) => {
    match projection_worker {
      Some(runtime) =>
        @sub.batch([
          subscriptions(model, emit),
          projection_worker_subscription(runtime),
        ])
      None => subscriptions(model, emit)
    }
  }
  let update = (model, event, emit) => {
    let session = current_session.val
    let (next, command) = update_model(
      session.editor,
      session.attachment,
      raw_input_coordinator,
      block_input_coordinator,
      model,
      latest_model,
      event,
      emit,
      projection_session?,
      projection_worker?,
    ) catch {
      Failure::Failure(_) as failure => {
        raw_input_coordinator.cancel_pending()
        block_input_coordinator.cancel_pending()
        let (next, command) = recover_after_parser_failure(
          current_session,
          model,
          failure,
          emit,
          projection_session?,
        )
        publish(next, Some(raw_input_coordinator), None)
        (next, command)
      }
      @markdown.MarkdownEditorError::Committed(..) as committed => {
        raw_input_coordinator.cancel_pending()
        block_input_coordinator.cancel_pending()
        let (next, command) = recover_after_parser_failure(
          current_session,
          model,
          committed,
          emit,
          projection_session?,
        )
        publish(next, Some(raw_input_coordinator), None)
        (next, command)
      }
      error => {
        raw_input_coordinator.cancel_pending()
        block_input_coordinator.cancel_pending()
        let (next, command) = quarantine_outer_error(
          current_session,
          model,
          error,
          projection_session?,
        )
        publish(next, Some(raw_input_coordinator), None)
        (next, command)
      }
    }
    let projection_command = match projection_worker {
      Some(runtime) => runtime.sync(next, emit)
      None => @rabbita_runtime.none
    }
    (next, @cmd.batch([command, projection_command]))
  }
  @rabbita_runtime.new(() => {
    let (model, emit) = @rabbita_runtime.create_state_with_init(
      init=fn(emit) {
        let persistence_command = match baseline {
          Some((request_id, encoded)) =>
            @archive_storage.replace(request_id, encoded, completed=completion => {
              emit(Archive(completion))
            })
          None => @rabbita_runtime.none
        }
        let projection_command = match projection_worker {
          Some(runtime) => runtime.sync(initial, emit)
          None => @rabbita_runtime.none
        }
        (
          initial,
          @cmd.batch([persistence_command, projection_command]),
        )
      },
      update~,
      subscriptions=application_subscriptions,
    )
    let active_view = application_view(
      model, emit, raw_input_coordinator, block_input_coordinator,
    )
    model.view2(active_view, (model, active_view) => {
      latest_model.val = Some(model)
      view(model, emit, active_view)
    })
  })
}

///|
fn standalone_application(
  editor : @markdown.MarkdownEditor,
  attachment : @md_markdown.MarkdownSemanticAttachment,
  initial : DriverModel,
  baseline : (@repository.LocalArchiveRequestId, String)?,
) -> @rabbita_runtime.App {
  build_application(
    editor,
    attachment,
    initial,
    baseline,
    None,
    standalone_subscriptions,
    standalone_preview_view,
  )
}

///|
fn private_dev_host_application(
  editor : @markdown.MarkdownEditor,
  attachment : @md_markdown.MarkdownSemanticAttachment,
  initial : DriverModel,
  baseline : (@repository.LocalArchiveRequestId, String)?,
) -> @rabbita_runtime.App {
  build_application(
    editor,
    attachment,
    initial,
    baseline,
    Some(RawInputTelemetry::new()),
    private_dev_host_subscriptions,
    private_dev_host_preview_view,
  )
}

///|
/// Build the shell model shared by private and standalone mounts.
fn initial_model(
  host_id : String,
  editor : @markdown.MarkdownEditor,
  document_id : @archive.LoomarkDocumentId,
  replica_id : String,
  archive_persistence_enabled~ : Bool,
) -> DriverModel raise {
  let host_width = @dom_boundary.measure_element_id(host_id)
    .offset_width()
    .to_int() catch {
      _ => SPLIT_STACK_BREAKPOINT
    }
  {
    state: @core.ApplicationState::ApplicationState(@core.Raw),
    runtime_state: EditorRuntimeState::Healthy,
    document: editor.snapshot(),
    document_version: editor.version(),
    document_id,
    raw_selection: None,
    archive_persistence_enabled,
    semantic_document: None,
    preview_artifact: None,
    semantic_read_count: 0,
    split_preview_open: false,
    compact_split: compact_split_for_width(host_width),
    active_block_key: None,
    replica_id,
    source_revision: 0,
    text_input_generation: 0,
    fatal: false,
    error: None,
    error_code: None,
    error_operation: None,
    error_count: 0,
    committed_change_count: 0,
    fail_next_editor_commit: false,
    force_parser_failure: false,
    force_reconstruction_failure: false,
    reconstruction_attempt_count: 0,
    resize_count: 0,
    selection: None,
    measurement: None,
    event_detail: None,
    event_count: 0,
    control_ready: false,
    event_install_count: 0,
    event_unload_count: 0,
    listening: true,
    rejection: None,
    archive_tracker: @repository.LocalArchiveRequestTracker::new(),
    local_storage_warning: false,
  }
}

///|
/// Build and mount the one shared application with an explicit host shell.
#warnings("-alert_unstable")
fn mount_application(
  host_id : String,
  source : String,
  replica_prefix : String,
  build : (
    @markdown.MarkdownEditor,
    @md_markdown.MarkdownSemanticAttachment,
    DriverModel,
    (@repository.LocalArchiveRequestId, String)?,
  ) -> @rabbita_runtime.App,
) -> String raise {
  if mounted.val {
    return "{\"ok\":false,\"error\":\"host-already-mounted\"}"
  }
  let replica_id = @archive_storage.fresh_id(replica_prefix)
  let document_id = @archive.LoomarkDocumentId::from_string(
    @archive_storage.fresh_id("loomark-document-"),
  ) catch {
    _ => return "{\"ok\":false,\"error\":\"document-id-allocation-failed\"}"
  }
  let (editor, attachment) = @markdown.MarkdownEditor::with_semantic_attachment(
    agent_id=replica_id,
    source~,
  ) catch {
    _ => return "{\"ok\":false,\"error\":\"editor-initialization-failed\"}"
  }
  let initial = initial_model(
    host_id,
    editor,
    document_id,
    replica_id,
    archive_persistence_enabled=false,
  )
  detached_focus_token.val = ""
  publish(initial, None, None)
  let app = build(editor, attachment, initial, None)
  app.mount(host_id)
  mounted.val = true
  "{\"ok\":true}"
}

///|
/// Mount the production standalone application once for the page lifetime.
pub fn mount_standalone(host_id : String, source : String) -> String {
  if mounted.val {
    return "{\"ok\":false,\"error\":\"host-already-mounted\"}"
  }
  mounted.val = true
  @archive_storage.load(loaded => {
    finish_standalone_bootstrap(host_id, source, loaded) catch {
      _ =>
        recovery_application(RecoveryCategory::EditorInitializationFailed).mount(
          host_id,
        )
    }
  })
  "{\"ok\":true}"
}

///|
/// Mount the private application exactly once into a fresh connected element.
pub fn mount(host_id : String, source : String) -> String {
  mount_application(
    host_id, source, "loomark-dev-host-", private_dev_host_application,
  ) catch {
    _ => "{\"ok\":false,\"error\":\"editor-initialization-failed\"}"
  }
}

///|
/// Return an immutable detached snapshot for private browser assertions.
pub fn snapshot() -> String {
  detached_snapshot.val
}

///|
/// Queue a typed source transaction through the Rabbita update loop.
pub fn request_source(source : String) -> Unit {
  dispatch_driver("source|" + source)
}

///|
/// Queue the Raw mode transition through the typed application event.
pub fn select_raw() -> Unit {
  dispatch_driver("select-raw")
}

///|
/// Queue the Block mode transition through the typed application event.
pub fn select_block() -> Unit {
  dispatch_driver("select-block")
}

///|
/// Queue the Preview mode transition through the typed application event.
pub fn select_preview() -> Unit {
  dispatch_driver("select-preview")
}

///|
/// Queue a versioned source/mode snapshot restore through one transaction.
pub fn restore_snapshot(version : Int, source : String, mode : String) -> Unit {
  let payload : Map[String, Json] = {
    "version": version.to_json(),
    "source": source.to_json(),
    "mode": mode.to_json(),
  }
  dispatch_driver("restore-snapshot|" + Json::object(payload).stringify())
}

///|
/// Arm the next real editor transaction to use a failing editor request.
pub fn force_editor_failure() -> Unit {
  dispatch_driver("editor-failure")
}

///|
/// Private dev-host control: the next normal edit fails after CRDT acceptance.
pub fn force_parser_failure() -> Unit {
  dispatch_driver("force-parser-failure")
}

///|
/// Private dev-host control: hold the next Raw transaction at AfterRender.
pub fn arm_raw_render_barrier() -> Unit {
  dispatch_driver("arm-raw-render-barrier")
}

///|
/// Private dev-host control: release a held Raw AfterRender transaction.
pub fn release_raw_render_barrier() -> Unit {
  dispatch_driver("release-raw-render-barrier")
}

///|
/// Private dev-host control: force the next recovery attempt into RawRecovery.
pub fn force_reconstruction_failure() -> Unit {
  dispatch_driver("force-reconstruction-failure")
}

///|
/// Queue the Preview focus operation; the DOM write is AfterRender.
pub fn focus_preview() -> Unit {
  dispatch_driver("focus-preview")
}

///|
/// Queue the Raw editor focus operation; the DOM write is AfterRender.
pub fn focus_raw() -> Unit {
  dispatch_driver("focus-raw")
}

///|
/// Queue the Block editor focus operation; the DOM write is AfterRender.
pub fn focus_block() -> Unit {
  dispatch_driver("focus-block")
}

///|
/// Queue a stale Block selection probe for the private browser harness.
pub fn probe_stale_block_selection() -> Unit {
  dispatch_driver("probe-stale-block-selection")
}

///|
/// Queue a deleted Block selection probe for the private browser harness.
pub fn probe_deleted_block_selection() -> Unit {
  dispatch_driver("probe-deleted-block-selection")
}

///|
/// Return the last committed logical focus token, detached from the DOM.
pub fn capture_focus() -> String {
  detached_focus_token.val
}

///|
/// Queue a logical focus restoration through the private driver.
pub fn restore_focus(token : String) -> Unit {
  dispatch_driver("restore-focus|" + token)
}

///|
/// Queue a selection write followed by a read through the DOM boundary.
pub fn write_selection(start : Int, end : Int) -> Unit {
  dispatch_driver(
    "write-selection|" + start.to_string() + "|" + end.to_string(),
  )
}

///|
/// Queue a selection write against a missing element.
pub fn write_selection_failure() -> Unit {
  dispatch_driver("write-selection-failure")
}

///|
/// Queue a detached preview measurement.
pub fn measure_preview() -> Unit {
  dispatch_driver("measure-preview")
}

///|
/// Queue a measurement against a missing element.
pub fn measure_failure() -> Unit {
  dispatch_driver("measure-failure")
}

///|
/// Dispose the custom event subscription through the update loop.
pub fn stop_listening() -> Unit {
  dispatch_driver("stop-listening")
}

///|
/// Queue a fatal driver state for negative-path assertions.
pub fn fail(message : String) -> Unit {
  dispatch_driver("fatal|" + message)
}
