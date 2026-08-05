///|
/// Private pre-`MountedApp` application and test-driver seam.
priv enum DriverEvent {
  ReplaceSource(String)
  SelectRaw
  SelectBlock
  SelectPreview
  ToggleSplitPreview
  BlockFocused(String)
  BlockHeading(Int, BlockSelection?)
  BlockToggleList(BlockSelection?)
  BlockDelete
  RawInput(String, @dom_boundary.TextSelection?)
  BlockInput(
    node_id~ : @markdown.MarkdownNodeId,
    input_id~ : String,
    text~ : String,
    selection_offset~ : Int
  )
  BlockSplit(node_id~ : @markdown.MarkdownNodeId, offset~ : Int)
  BlockMerge(node_id~ : @markdown.MarkdownNodeId, selection~ : BlockSelection)
  BlockNavigate(key~ : String, direction~ : Int)
  BlockSelectionRejected(String, BlockSelection?)
  ProbeBlockSelection(String)
  EditorFailure
  RestoreSnapshot(
    version~ : Int,
    source~ : String,
    mode~ : @core.ApplicationMode
  )
  FocusPreview
  FocusBlock
  FocusRaw
  RestoreFocus(String)
  FocusRejected(@core.FocusDecisionError)
  WriteSelection(start~ : Int, end~ : Int)
  WriteSelectionFailure
  MeasurePreview
  MeasureFailure
  SelectionRead(start~ : Int, end~ : Int)
  Measured(width~ : Double, height~ : Double)
  EffectFailed(String)
  CustomEvent(String)
  ControlInstalled
  SubscriptionInstalled
  SubscriptionUnloaded
  InvalidRequest(String)
  StopListening
  Fatal(String)
  Resize(@common.Viewport)
}

///|
/// Versioned errors owned by the private focus-token codec.
priv enum FocusTokenError {
  Malformed
  UnsupportedVersion(Int)
  Ambiguous
}

///|
priv suberror DriverSubscription {
  Control(@cmd.Emit[DriverEvent])
  Test(@cmd.Emit[String], @cmd.Emit[DriverEvent])
}

///|
priv struct DriverModel {
  state : @core.ApplicationState
  document : @markdown.MarkdownDocumentSnapshot
  semantic_document : @md_markdown.MarkdownIR?
  semantic_read_count : Int
  split_preview_open : Bool
  compact_split : Bool
  active_block_key : String?
  replica_id : String
  source_revision : Int
  text_input_generation : Int
  fatal : Bool
  error : String?
  error_code : String?
  error_operation : String?
  error_count : Int
  committed_change_count : Int
  fail_next_editor_commit : Bool
  resize_count : Int
  selection : String?
  measurement : String?
  event_detail : String?
  event_count : Int
  control_ready : Bool
  event_install_count : Int
  event_unload_count : Int
  listening : Bool
  rejection : String?
} derive(Eq)

///|
/// The private harness has exactly one mount per page/process. This is a
/// bounded test seam, not a reusable handle registry or lifecycle API.
let mounted : @ref.Ref[Bool] = { val: false }

///|
let detached_snapshot : @ref.Ref[String] = { val: "{}" }

///|
/// Latest committed model for deferred browser effects in this private shell.
let detached_model : @ref.Ref[DriverModel?] = { val: None }

///|
/// Detached logical focus state for the private driver only.
let detached_focus_token : @ref.Ref[String] = { val: "" }

///|
/// Focus tokens have a private wire version independent from snapshots.
const FOCUS_TOKEN_VERSION : Int = 1

///|
const HELLO_EXAMPLE_SOURCE : String = "# Hello World\n\nWelcome to the Canopy Markdown editor.\n\nThis editor has three modes: raw, block, and preview.\n"

///|
const BLOG_EXAMPLE_SOURCE : String = "# Getting Started\n\nCanopy is an incremental projectional editor.\n\n## Features\n\nThe editor supports real-time collaboration via CRDT.\n\nEvery keystroke is incrementally parsed and projected into a structured view."

///|
const LIST_EXAMPLE_SOURCE : String = "# Shopping List\n\nThings to pick up:\n\n- Apples\n- Bread\n- Coffee\n- Dark chocolate"

///|
const CODE_EXAMPLE_SOURCE : String = "# README\n\nA minimal example project.\n\n## Install\n\n```bash\nnpm install\n```\n\n## Usage\n\n- Run the dev server\n- Open the browser\n- Start editing"

///|
/// Allocate one globally unique CRDT replica identity per mount.
extern "js" fn js_replica_uuid() -> String =
  #| () => globalThis.crypto.randomUUID()

///|
fn mode_name(mode : @core.ApplicationMode) -> String {
  match mode {
    @core.Raw => "raw"
    @core.Block => "block"
    @core.Preview => "preview"
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
/// The private driver maps a pure focus target to one mounted control.
fn focus_target_id(target : @core.FocusTarget) -> String {
  match target {
    @core.RawEditor => "loomark-input"
    @core.BlockEditor => "loomark-block-input"
    @core.PreviewControl => "loomark-preview"
  }
}

///|
fn focus_target_name(target : @core.FocusTarget) -> String {
  match target {
    @core.RawEditor => "raw"
    @core.BlockEditor => "block"
    @core.PreviewControl => "preview"
  }
}

///|
/// Serialize a known focus target and revision at the private shell boundary.
fn encode_focus_token(
  target : @core.FocusTarget,
  source_revision : Int,
) -> String {
  "v" +
  FOCUS_TOKEN_VERSION.to_string() +
  "|" +
  focus_target_name(target) +
  "|" +
  source_revision.to_string()
}

///|
/// Decode a token exactly once before handing its typed locator to the core.
fn decode_focus_token(
  token : String,
) -> Result[@core.FocusLocator, FocusTokenError] {
  let parts = token.split("|").to_array()
  guard parts.length() == 3 else { return Err(FocusTokenError::Malformed) }
  guard parts[0].has_prefix("v") else { return Err(FocusTokenError::Malformed) }
  let version = @string.parse_int(parts[0][1:], base=10) catch {
    _ => return Err(FocusTokenError::Malformed)
  }
  if version != FOCUS_TOKEN_VERSION {
    return Err(FocusTokenError::UnsupportedVersion(version))
  }
  let target = match parts[1] {
    "raw" => @core.RawEditor
    "block" => @core.BlockEditor
    "preview" => @core.PreviewControl
    _ => return Err(FocusTokenError::Ambiguous)
  }
  let source_revision = @string.parse_int(parts[2], base=10) catch {
    _ => return Err(FocusTokenError::Malformed)
  }
  Ok(@core.FocusLocator(target~, source_revision~))
}

///|
/// Map codec failures to one private-driver error category.
fn focus_token_error(error : FocusTokenError) -> (String, String) {
  match error {
    FocusTokenError::Malformed => ("malformed-focus", "malformed focus token")
    FocusTokenError::UnsupportedVersion(version) =>
      (
        "unsupported-focus-version",
        "unsupported focus token version: " + version.to_string(),
      )
    FocusTokenError::Ambiguous => ("ambiguous-focus", "ambiguous focus target")
  }
}

///|
/// Map pure focus compatibility rejections to one private-driver category.
fn focus_rejection(error : @core.FocusDecisionError) -> (String, String) {
  match error {
    @core.Stale => ("stale-focus", "stale focus token")
    @core.ModeInapplicable =>
      (
        "focus-mode-inapplicable", "focus target is inapplicable in current mode",
      )
  }
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
fn reject_focus(
  model : DriverModel,
  error : @core.FocusDecisionError,
) -> (DriverModel, @cmd.Cmd) {
  let (code, message) = focus_rejection(error)
  let next = record_error(model, code, "browser-effect", message)
  publish(next)
  (next, @rabbita_runtime.none)
}

///|
fn reject_focus_token(
  model : DriverModel,
  error : FocusTokenError,
) -> (DriverModel, @cmd.Cmd) {
  let (code, message) = focus_token_error(error)
  let next = record_error(model, code, "browser-effect", message)
  publish(next)
  (next, @rabbita_runtime.none)
}

///|
/// Keep editor failures categorized without exposing the editor error value.
fn editor_error_detail(error : @markdown.MarkdownEditorError) -> String {
  match error {
    @markdown.InvalidAgentId => "invalid-agent-id"
    @markdown.InitializationFailed(detail~) => detail
    @markdown.ProjectionUnavailable => "projection-unavailable"
    @markdown.InvalidTextRange(..) => "invalid text range"
    @markdown.EditFailed(detail~) => detail
  }
}

///|
/// Commit one canonical source request and install state only after success.
fn commit_source(
  editor : @markdown.MarkdownEditor,
  model : DriverModel,
  state : @core.ApplicationState,
  source : String,
  operation : String,
) -> (DriverModel, Bool, Bool) {
  let fail_commit = model.fail_next_editor_commit
  let next = { ..model, fail_next_editor_commit: false }
  let request = if fail_commit {
    @markdown.MarkdownEditRequest::ReplaceText(
      start=-1,
      delete_len=0,
      inserted="",
    )
  } else {
    @markdown.MarkdownEditRequest::ReplaceSource(source)
  }
  match editor.commit(request) {
    Ok(@markdown.Applied(document, _)) =>
      (
        {
          ..next,
          state,
          document,
          source_revision: model.source_revision + 1,
          committed_change_count: model.committed_change_count + 1,
        },
        true,
        true,
      )
    Ok(@markdown.Unchanged(document)) =>
      ({ ..next, state, document }, true, false)
    Err(error) => {
      let failed = record_error(
        next,
        "editor-commit-failed",
        operation,
        "editor commit failed: " + editor_error_detail(error),
      )
      (failed, false, false)
    }
  }
}

///|
/// Commit one typed block request through the atomic façade boundary.
/// Structural callers receive the deep selection outcome without reading
/// SyncEditor cursor state in this shell.
fn commit_block_request(
  editor : @markdown.MarkdownEditor,
  attachment : @md_markdown.MarkdownSemanticAttachment,
  model : DriverModel,
  request : @markdown.MarkdownEditRequest,
  operation : String,
) -> (DriverModel, @markdown.MarkdownBlockSelection?, Bool) {
  let fail_commit = model.fail_next_editor_commit
  let next = { ..model, fail_next_editor_commit: false }
  let request = if fail_commit {
    @markdown.MarkdownEditRequest::ReplaceText(
      start=-1,
      delete_len=0,
      inserted="",
    )
  } else {
    request
  }
  match editor.commit(request) {
    Ok(@markdown.Applied(document, selection)) => {
      let committed = {
        ..next,
        document,
        source_revision: model.source_revision + 1,
        committed_change_count: model.committed_change_count + 1,
      }
      (
        update_preview_document(
          attachment,
          committed,
          preview_requested(model),
          accepted=true,
          changed=true,
        ),
        selection,
        true,
      )
    }
    Ok(@markdown.Unchanged(document)) =>
      (
        update_preview_document(
          attachment,
          { ..next, document, },
          preview_requested(model),
          accepted=true,
          changed=false,
        ),
        None,
        true,
      )
    Err(error) => {
      let failed = record_error(
        next,
        "editor-commit-failed",
        operation,
        "editor commit failed: " + editor_error_detail(error),
      )
      (
        update_preview_document(
          attachment,
          failed,
          preview_requested(model),
          accepted=false,
          changed=false,
        ),
        None,
        false,
      )
    }
  }
}

///|
/// Reconcile one toolbar commit with the immutable block view and schedule
/// the typed selection only after Rabbita renders that committed document.
fn commit_block_toolbar_request(
  editor : @markdown.MarkdownEditor,
  attachment : @md_markdown.MarkdownSemanticAttachment,
  model : DriverModel,
  request : @markdown.MarkdownEditRequest,
  originating_selection : BlockSelection?,
  control_id : String,
  emit : @cmd.Emit[DriverEvent],
) -> (DriverModel, @cmd.Cmd) {
  let (committed, committed_selection, _) = commit_block_request(
    editor, attachment, model, request, "editor-dispatch",
  )
  let selection = committed_selection.bind(selection => {
    block_selection_from_commit(committed.document, selection)
  })
  let applied = committed.source_revision != model.source_revision
  let next = {
    ..committed,
    active_block_key: match selection {
      Some(selection) => Some(selection.key)
      None => if applied { None } else { model.active_block_key }
    },
    selection: match selection {
      Some(selection) => Some(block_selection_label(selection))
      None => if applied { None } else { committed.selection }
    },
  }
  publish(next)
  match selection {
    Some(selection) =>
      (
        next,
        block_selection_after_render(
          selection,
          next.source_revision,
          report_superseded=false,
          emit,
        ),
      )
    None =>
      if applied {
        (next, @rabbita_runtime.none)
      } else {
        match originating_selection {
          Some(selection) =>
            (
              next,
              block_selection_after_render(
                selection,
                next.source_revision,
                report_superseded=true,
                emit,
              ),
            )
          None =>
            (
              next,
              after_render(
                scheduler => {
                  ignore(scheduler)
                  @dom_boundary.focus_id(control_id)
                },
                emit,
              ),
            )
        }
      }
  }
}

///|
fn publish(model : DriverModel) -> Unit {
  let fields : Map[String, Json] = {
    "source": model.document.source().to_json(),
    "replica_id": model.replica_id.to_json(),
    "version": @core.SNAPSHOT_VERSION.to_json(),
    "mode": mode_name(model.state.mode()).to_json(),
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
    "resize_count": model.resize_count.to_json(),
    "selection": match model.selection {
      Some(selection) => selection.to_json()
      None => Json::null()
    },
    "measurement": match model.measurement {
      Some(measurement) => measurement.to_json()
      None => Json::null()
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
  detached_model.val = Some(model)
}

///|
fn preview_document_surface(model : DriverModel) -> @rabbita_runtime.Html {
  let source = model.document.source()
  match model.semantic_document {
    Some(document) => preview_surface(source, document)
    None =>
      @html.div(
        id="loomark-preview",
        attrs=@html.Attrs::build()
          .data_set("loomark-preview-fallback", "unavailable")
          .role("region")
          .tabindex(0)
          .aria_label("Markdown preview"),
        style=["display:grid;gap:1rem"],
        @rui.typography_muted(
          "Preview is unavailable for the current accepted document.",
        ),
      )
  }
}

///|
fn editor_surface(
  model : DriverModel,
  emit : @cmd.Emit[DriverEvent],
) -> @rabbita_runtime.Html {
  let source = model.document.source()
  match model.state.mode() {
    @core.Raw =>
      @rui.textarea(
        id="loomark-input",
        value=source,
        rows=4,
        attrs=@html.Attrs::build().aria_label("Raw Markdown source"),
        style=[
          "min-height:clamp(24rem,70vh,36rem);flex:1;field-sizing:fixed;resize:none;--rui-control-base-border:transparent;--rui-control-base-shadow:none;border-radius:0;background:transparent;padding:1rem;font-family:ui-monospace,SFMono-Regular,Menlo,Monaco,Consolas,\"Liberation Mono\",\"Courier New\",monospace;font-size:0.875rem;line-height:1.65",
        ],
        on_input=@cmd.Emit(source => raw_input_command(source, emit)),
      )
    @core.Preview => preview_document_surface(model)
    @core.Block => block_surface(model, emit)
  }
}

///|
fn preview_view(
  model : DriverModel,
  emit : @cmd.Emit[DriverEvent],
  surface : @rabbita_runtime.Html,
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
      .on_click(_ => emit(SelectRaw)),
    style=["min-height:2.75rem;flex:0 0 3.25rem;padding:0"],
    mode_icon("m8 9-3 3 3 3m8-6 3 3-3 3m-2-8-4 16"),
  )
  let preview_button = @rui.tabs_trigger(
    value="preview",
    id="loomark-mode-preview",
    selected=preview_selected,
    attrs=@html.Attrs::build()
      .aria_label("Preview")
      .on_click(_ => emit(SelectPreview)),
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
      .on_click(_ => emit(SelectBlock)),
    style=["min-height:2.75rem;flex:0 0 3.25rem;padding:0"],
    mode_icon("M4 4h6v6H4V4Zm10 0h6v6h-6V4ZM4 14h6v6H4v-6Zm10 0h6v6h-6v-6Z"),
  )
  let (panel_id, panel_labelledby) = match model.state.mode() {
    @core.Raw => ("loomark-panel-raw", "loomark-mode-raw")
    @core.Block => ("loomark-panel-block", "loomark-mode-block")
    @core.Preview => ("loomark-panel-preview", "loomark-mode-preview")
  }
  let split_toggle = if preview_selected {
    @html.nothing
  } else {
    @rui.button(
      id="loomark-split-toggle",
      variant=@rui.Ghost,
      size=@rui.Xs,
      attrs=@html.Attrs::build()
        .aria_label(
          if model.split_preview_open {
            "Close split Preview"
          } else {
            "Open split Preview"
          },
        )
        .aria_pressed(model.split_preview_open.to_string()),
      on_click=emit(ToggleSplitPreview),
      if model.split_preview_open {
        "Close split"
      } else {
        "Split"
      },
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
        attrs=@html.Attrs::build().aria_label("Apply Hello example"),
        on_click=emit(ReplaceSource(HELLO_EXAMPLE_SOURCE)),
        "Hello",
      ),
      @rui.button(
        variant=@rui.Ghost,
        size=@rui.Xs,
        attrs=@html.Attrs::build().aria_label("Guide: Apply Blog example"),
        on_click=emit(ReplaceSource(BLOG_EXAMPLE_SOURCE)),
        "Guide",
      ),
      @rui.button(
        variant=@rui.Ghost,
        size=@rui.Xs,
        attrs=@html.Attrs::build().aria_label("Apply List example"),
        on_click=emit(ReplaceSource(LIST_EXAMPLE_SOURCE)),
        "List",
      ),
      @rui.button(
        variant=@rui.Ghost,
        size=@rui.Xs,
        attrs=@html.Attrs::build().aria_label("Apply Code example"),
        on_click=emit(ReplaceSource(CODE_EXAMPLE_SOURCE)),
        "Code",
      ),
    ],
  )
  let event_button = @html.button(
    id="loomark-event-target",
    type_="button",
    hidden=true,
    "Driver event",
  )
  let driver_button = @html.button(
    id="loomark-driver-target",
    type_="button",
    hidden=true,
    "Driver",
  )
  let error_view = match model.error {
    Some(error) =>
      @rui.alert(
        id="loomark-error",
        variant=@rui.Destructive,
        @rui.alert_description("error: " + error),
      )
    None => @html.nothing
  }
  @rui.theme(
    id="loomark-root",
    attrs=@html.Attrs::build()
      .role("region")
      .aria_label("Loomark Markdown Editor"),
    style=[
      "min-height:100vh;min-height:100dvh;box-sizing:border-box;background:oklch(0.968 0.008 85);color:oklch(0.24 0.018 265);padding:clamp(0.5rem,2vw,1.5rem);--rui-background:oklch(0.991 0.004 85);--rui-foreground:oklch(0.24 0.018 265);--rui-muted:oklch(0.94 0.01 85);--rui-muted-foreground:oklch(0.5 0.02 265);--rui-border:oklch(0.86 0.012 85);--rui-primary:oklch(0.48 0.12 276);--rui-radius:0.5rem",
    ],
    [
      @html.div(
        id="loomark-editor-shell",
        style=[
          if model.split_preview_open && !preview_selected {
            "width:min(100%,76rem);height:calc(100dvh - clamp(1rem,4vw,3rem));margin-inline:auto;display:flex;flex-direction:column"
          } else {
            "width:min(100%,53.75rem);min-height:calc(100dvh - clamp(1rem,4vw,3rem));margin-inline:auto;display:flex;flex-direction:column"
          },
        ],
        [
          @rui.tabs_root(
            value=mode_name(model.state.mode()),
            id="loomark-editor-frame",
            style=[
              "flex:1;gap:0;overflow:hidden;border:1px solid var(--rui-border);border-radius:var(--rui-radius);background:var(--rui-background);box-shadow:0 1px 2px rgb(31 35 48 / 0.06),0 10px 30px rgb(31 35 48 / 0.05)",
            ],
            [
              @html.div(
                style=[
                  "display:flex;min-width:0;align-items:center;justify-content:space-between;gap:0.25rem;flex-wrap:wrap;padding-inline:0.5rem;border-bottom:1px solid var(--rui-border)",
                ],
                [
                  @rui.tabs_list(
                    variant=@rui.TabsLine,
                    aria_label="Editor view",
                    id="loomark-toolbar",
                    style=["min-height:3.25rem;padding:0;overflow:visible"],
                    [block_button, raw_button, preview_button],
                  ),
                  @html.div(
                    style=[
                      "display:flex;align-items:center;justify-content:flex-end;gap:0.125rem;flex-wrap:wrap",
                    ],
                    [split_toggle, examples],
                  ),
                ],
              ),
              @html.div(
                id=panel_id,
                attrs=@html.Attrs::build()
                  .role("tabpanel")
                  .aria_labelledby(panel_labelledby),
                style=["min-width:0;flex:1;display:flex"],
                surface,
              ),
            ],
          ),
        ],
      ),
      event_button,
      driver_button,
      error_view,
    ],
  )
}

///|
fn after_render(
  action : (&@cmd.Scheduler) -> Unit raise @dom_boundary.DomBoundaryError,
  failed : @cmd.Emit[DriverEvent],
) -> @cmd.Cmd {
  @cmd.custom_cmd(
    scheduler => {
      action(scheduler) catch {
        error => scheduler.add(failed(EffectFailed(error.message())))
      }
    },
    kind=@cmd.AfterRender,
  )
}

///|
/// Revalidate a structural selection after the edited blocks are rendered,
/// then focus the exact block and restore its relative UTF-16 caret.
/// Routine input may follow a newer render when keystrokes overtake one frame;
/// its superseded callback yields while structural edits report stale revisions.
fn block_selection_after_render(
  selection : BlockSelection,
  source_revision : Int,
  report_superseded~ : Bool,
  emit : @cmd.Emit[DriverEvent],
) -> @cmd.Cmd {
  after_render(
    scheduler => {
      match detached_model.val {
        Some(model) =>
          if model.state.mode() != @core.Block {
            scheduler.add(
              emit(
                BlockSelectionRejected("block selection mode is stale", None),
              ),
            )
          } else if model.source_revision != source_revision {
            // Rapid input can queue several post-render selections in one
            // frame. Rabbita runs AfterRender effects newest-first, so an older
            // superseded selection must not emit a message that schedules a
            // second render after the newest selection restored the caret.
            if report_superseded {
              scheduler.add(
                emit(BlockSelectionRejected("block selection is stale", None)),
              )
            }
          } else {
            match block_selection_target(model.document, selection) {
              Some(index) => {
                let id = block_input_id(index)
                @dom_boundary.focus_id(id)
                @dom_boundary.write_text_selection_id(
                  id,
                  @dom_boundary.TextSelection(
                    selection.start,
                    selection.end,
                    @dom_boundary.NoDirection,
                  ),
                )
              }
              None =>
                scheduler.add(
                  emit(
                    BlockSelectionRejected(
                      "block selection target is unavailable",
                      None,
                    ),
                  ),
                )
            }
          }
        None =>
          scheduler.add(
            emit(
              BlockSelectionRejected("block selection model unavailable", None),
            ),
          )
      }
    },
    emit,
  )
}

///|
/// Revalidate the latest model after rendering, then perform the final DOM
/// write without queuing a state update after it.
fn focus_latest_after_render(
  locator : @core.FocusLocator,
  token : String,
  emit : @cmd.Emit[DriverEvent],
) -> @cmd.Cmd {
  after_render(
    scheduler => {
      match detached_model.val {
        Some(model) =>
          match
            @core.decide_focus(model.state, model.source_revision, locator) {
            @core.Compatible(target) => {
              let previous_token = detached_focus_token.val
              detached_focus_token.val = token
              @dom_boundary.focus_id(focus_target_id(target)) catch {
                error => {
                  detached_focus_token.val = previous_token
                  scheduler.add(emit(EffectFailed(error.message())))
                }
              }
            }
            @core.Rejected(error) => scheduler.add(emit(FocusRejected(error)))
          }
        None => scheduler.add(emit(EffectFailed("focus model unavailable")))
      }
    },
    emit,
  )
}

///|
fn driver_event_name(event : DriverEvent) -> String {
  match event {
    ReplaceSource(_) => "source"
    SelectRaw => "select-raw"
    SelectBlock => "select-block"
    SelectPreview => "select-preview"
    ToggleSplitPreview => "toggle-split"
    BlockFocused(_) => "block-focused"
    BlockHeading(_, _) => "block-heading"
    BlockToggleList(_) => "block-toggle-list"
    BlockDelete => "block-delete"
    RawInput(_, _) => "raw-input"
    BlockInput(..) => "block-input"
    BlockSplit(..) => "block-split"
    BlockMerge(..) => "block-merge"
    BlockNavigate(..) => "block-navigate"
    BlockSelectionRejected(_, _) => "block-selection-rejected"
    ProbeBlockSelection(_) => "probe-block-selection"
    EditorFailure => "editor-failure"
    RestoreSnapshot(..) => "restore-snapshot"
    FocusPreview => "focus-preview"
    FocusBlock => "focus-block"
    FocusRaw => "focus-raw"
    RestoreFocus(_) => "restore-focus"
    FocusRejected(_) => "focus-rejected"
    WriteSelection(..) => "write-selection"
    WriteSelectionFailure => "write-selection-failure"
    MeasurePreview => "measure-preview"
    MeasureFailure => "measure-failure"
    SelectionRead(..) => "selection-read"
    Measured(..) => "measured"
    EffectFailed(_) => "effect-failed"
    CustomEvent(_) => "custom-event"
    ControlInstalled => "control-installed"
    SubscriptionInstalled => "subscription-installed"
    SubscriptionUnloaded => "subscription-unloaded"
    InvalidRequest(_) => "invalid-request"
    StopListening => "stop-listening"
    Fatal(_) => "fatal"
    Resize(_) => "resize"
  }
}

///|
/// Decode the private DOM transport without exposing a mutable application
/// handle to the generated JavaScript boundary.
fn parse_driver_event(detail : String) -> DriverEvent {
  if detail == "select-raw" {
    SelectRaw
  } else if detail == "select-block" {
    SelectBlock
  } else if detail == "select-preview" {
    SelectPreview
  } else if detail == "toggle-split" {
    ToggleSplitPreview
  } else if detail == "focus-preview" {
    FocusPreview
  } else if detail == "focus-block" {
    FocusBlock
  } else if detail == "focus-raw" {
    FocusRaw
  } else if detail == "probe-stale-block-selection" {
    ProbeBlockSelection("stale")
  } else if detail == "probe-deleted-block-selection" {
    ProbeBlockSelection("deleted")
  } else if detail == "write-selection-failure" {
    WriteSelectionFailure
  } else if detail == "measure-preview" {
    MeasurePreview
  } else if detail == "measure-failure" {
    MeasureFailure
  } else if detail == "stop-listening" {
    StopListening
  } else if detail.has_prefix("source|") {
    ReplaceSource(detail["source|".length():].to_owned())
  } else if detail.has_prefix("raw-input|") {
    RawInput(detail["raw-input|".length():].to_owned(), None)
  } else if detail == "editor-failure" {
    EditorFailure
  } else if detail.has_prefix("restore-focus|") {
    RestoreFocus(detail["restore-focus|".length():].to_owned())
  } else if detail.has_prefix("restore-snapshot|") {
    let payload = detail["restore-snapshot|".length():].to_owned()
    let parsed = @json.parse(payload) catch {
      _ => return InvalidRequest("restore-snapshot")
    }
    match parsed {
      Json::Object(fields) => {
        let version = match fields.get("version") {
          Some(Json::Number(value, ..)) => value.to_int()
          _ => return InvalidRequest("restore-snapshot")
        }
        let source = match fields.get("source") {
          Some(Json::String(value)) => value
          _ => return InvalidRequest("restore-snapshot")
        }
        let mode = match fields.get("mode") {
          Some(Json::String(value)) =>
            match value {
              "raw" => @core.Raw
              "block" => @core.Block
              "preview" => @core.Preview
              _ => return InvalidRequest("restore-snapshot")
            }
          _ => return InvalidRequest("restore-snapshot")
        }
        RestoreSnapshot(version~, source~, mode~)
      }
      _ => InvalidRequest("restore-snapshot")
    }
  } else if detail.has_prefix("write-selection|") {
    let parts = detail["write-selection|".length():].split("|").to_array()
    guard parts.length() == 2 else { return InvalidRequest("write-selection") }
    let start = @string.parse_int(parts[0], base=10) catch {
      _ => return InvalidRequest("write-selection")
    }
    let end = @string.parse_int(parts[1], base=10) catch {
      _ => return InvalidRequest("write-selection")
    }
    WriteSelection(start~, end~)
  } else if detail.has_prefix("fatal|") {
    Fatal(detail["fatal|".length():].to_owned())
  } else {
    InvalidRequest("unknown")
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
fn update_model(
  editor : @markdown.MarkdownEditor,
  attachment : @md_markdown.MarkdownSemanticAttachment,
  model : DriverModel,
  event : DriverEvent,
  emit : @cmd.Emit[DriverEvent],
) -> (DriverModel, @cmd.Cmd) {
  if model.fatal {
    let next = {
      ..model,
      rejection: Some(
        "operation=" + driver_event_name(event) + ";reason=fatal-state",
      ),
    }
    publish(next)
    return (next, @rabbita_runtime.none)
  }
  if model.state.mode() != @core.Raw && event is RawInput(_, _) {
    let next = record_error(
      model, "mode-inapplicable", "editor-dispatch", "Raw input is unavailable outside Raw mode",
    )
    publish(next)
    return (next, @rabbita_runtime.none)
  }
  if model.state.mode() != @core.Block &&
    (
      event is BlockInput(..) ||
      event is BlockSplit(..) ||
      event is BlockMerge(..) ||
      event is BlockNavigate(..) ||
      event is BlockFocused(_) ||
      event is BlockHeading(_, _) ||
      event is BlockToggleList(_) ||
      event is BlockDelete
    ) {
    let next = record_error(
      model, "mode-inapplicable", "editor-dispatch", "Block editing is unavailable outside Block mode",
    )
    publish(next)
    return (next, @rabbita_runtime.none)
  }
  match event {
    ReplaceSource(source) | RawInput(source, _) => {
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
      for decision in transition.decisions() {
        match decision {
          @core.ReplaceCanonicalSource(source) => {
            let old_requested = preview_requested(next)
            let (committed, accepted, changed) = commit_source(
              editor,
              next,
              transition.state(),
              source,
              "editor-dispatch",
            )
            next = update_preview_document(
              attachment,
              committed,
              old_requested,
              accepted~,
              changed~,
            )
            restore_raw_value = restore_raw_value || (raw_event && !accepted)
          }
          @core.SnapshotRejected(_) =>
            next = record_error(
              next, "invalid-snapshot", "editor-dispatch", "snapshot rejected",
            )
        }
      }
      publish(next)
      let command = if restore_raw_value {
        let repair_generation = next.text_input_generation
        let repair_source_revision = next.source_revision
        after_render(
          scheduler => {
            ignore(scheduler)
            let accepted_source = next.document.source()
            match detached_model.val {
              Some(current) if current.state.mode() == @core.Raw &&
                current.text_input_generation == repair_generation &&
                current.source_revision == repair_source_revision => {
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
              _ => ()
            }
          },
          emit,
        )
      } else {
        @rabbita_runtime.none
      }
      (next, command)
    }
    BlockFocused(key) =>
      if model.active_block_key == Some(key) {
        publish(model)
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
            publish(next)
            (next, @rabbita_runtime.none)
          }
          Some(index) => {
            let next = { ..model, active_block_key: Some(key) }
            publish(next)
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
          publish(next)
          (next, @rabbita_runtime.none)
        }
        Some(block) => {
          guard block_allows_heading(block.kind()) else {
            publish(model)
            let command = originating_selection
              .map(selection => {
                block_selection_after_render(
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
            publish(model)
            let command = originating_selection
              .map(selection => {
                block_selection_after_render(
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
          commit_block_toolbar_request(
            editor,
            attachment,
            model,
            @markdown.MarkdownEditRequest::ChangeHeadingLevel(
              node_id=block.node_id(),
              level=target_level,
            ),
            originating_selection,
            "loomark-heading-" + requested_level.to_string(),
            emit,
          )
        }
      }
    BlockToggleList(originating_selection) =>
      match block_format_target(model, originating_selection) {
        None => {
          let next = record_error(
            model, "block-selection-rejected", "editor-dispatch", "formatting requires an active block",
          )
          publish(next)
          (next, @rabbita_runtime.none)
        }
        Some(block) => {
          guard block_allows_list(block.kind()) else {
            publish(model)
            let command = originating_selection
              .map(selection => {
                block_selection_after_render(
                  selection,
                  model.source_revision,
                  report_superseded=true,
                  emit,
                )
              })
              .unwrap_or(@rabbita_runtime.none)
            return (model, command)
          }
          commit_block_toolbar_request(
            editor,
            attachment,
            model,
            @markdown.MarkdownEditRequest::ToggleListItem(
              node_id=block.node_id(),
            ),
            originating_selection,
            "loomark-toggle-list",
            emit,
          )
        }
      }
    BlockDelete =>
      match active_block(model) {
        None => {
          let next = record_error(
            model, "block-selection-rejected", "editor-dispatch", "deletion requires an active block",
          )
          publish(next)
          (next, @rabbita_runtime.none)
        }
        Some(block) =>
          commit_block_toolbar_request(
            editor,
            attachment,
            model,
            @markdown.MarkdownEditRequest::Delete(node_id=block.node_id()),
            None,
            "loomark-delete-block",
            emit,
          )
      }
    BlockInput(node_id~, input_id~, text=proposed_text, selection_offset~) => {
      let (next, committed_selection, accepted) = commit_block_request(
        editor,
        attachment,
        model,
        @markdown.MarkdownEditRequest::CommitTextControlEdit(
          node_id~,
          new_text=proposed_text,
        ),
        "editor-dispatch",
      )
      let selection = match committed_selection {
        Some(selection) =>
          block_selection_from_commit(
            next.document,
            selection,
            offset=selection_offset,
          )
        None => None
      }
      let next = {
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
      publish(next)
      match selection {
        Some(selection) =>
          (
            next,
            block_selection_after_render(
              selection,
              next.source_revision,
              report_superseded=false,
              emit,
            ),
          )
        None =>
          if accepted {
            (next, @rabbita_runtime.none)
          } else {
            let accepted_text = next.document
              .blocks()
              .fold(init=None, (found, block) => {
                match found {
                  Some(_) => found
                  None =>
                    if block.node_id() == node_id {
                      Some(block.text())
                    } else {
                      None
                    }
                }
              })
            match accepted_text {
              Some(text) => {
                let offset = rejected_text_offset(
                  text, proposed_text, selection_offset,
                )
                let repair_generation = next.text_input_generation
                let repair_source_revision = next.source_revision
                (
                  next,
                  after_render(
                    scheduler => {
                      ignore(scheduler)
                      match detached_model.val {
                        Some(current) if current.state.mode() == @core.Block &&
                          current.text_input_generation == repair_generation &&
                          current.source_revision == repair_source_revision => {
                          @dom_boundary.write_text_value_id(input_id, text)
                          @dom_boundary.focus_id(input_id)
                          @dom_boundary.write_text_selection_id(
                            input_id,
                            @dom_boundary.TextSelection(
                              offset,
                              offset,
                              @dom_boundary.NoDirection,
                            ),
                          )
                        }
                        _ => ()
                      }
                    },
                    emit,
                  ),
                )
              }
              None => (next, @rabbita_runtime.none)
            }
          }
      }
    }
    BlockSplit(node_id~, offset~) => {
      let (next, committed_selection, _) = commit_block_request(
        editor,
        attachment,
        model,
        @markdown.MarkdownEditRequest::SplitBlock(node_id~, offset~),
        "editor-dispatch",
      )
      let selection = match committed_selection {
        Some(selection) => block_selection_from_commit(next.document, selection)
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
      publish(next)
      match selection {
        Some(selection) =>
          (
            next,
            block_selection_after_render(
              selection,
              next.source_revision,
              report_superseded=false,
              emit,
            ),
          )
        None => (next, @rabbita_runtime.none)
      }
    }
    BlockMerge(node_id~, selection=originating_selection) => {
      let (next, committed_selection, _) = commit_block_request(
        editor,
        attachment,
        model,
        @markdown.MarkdownEditRequest::MergeWithPrevious(node_id~),
        "editor-dispatch",
      )
      let resolved_selection = match committed_selection {
        Some(selection) => block_selection_from_commit(next.document, selection)
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
      publish(next)
      match resolved_selection {
        Some(selection) =>
          (
            next,
            block_selection_after_render(
              selection,
              next.source_revision,
              report_superseded=false,
              emit,
            ),
          )
        None =>
          (
            next,
            block_selection_after_render(
              originating_selection,
              next.source_revision,
              report_superseded=true,
              emit,
            ),
          )
      }
    }
    BlockNavigate(key~, direction~) =>
      match block_navigation_selection(model.document, key, direction) {
        None => {
          publish(model)
          (model, @rabbita_runtime.none)
        }
        Some(selection) => {
          let next = {
            ..model,
            active_block_key: Some(selection.key),
            selection: Some(block_selection_label(selection)),
          }
          publish(next)
          (
            next,
            block_selection_after_render(
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
        publish(next)
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
        let (committed, accepted, changed) = commit_source(
          editor,
          model,
          model.state,
          source,
          "editor-dispatch",
        )
        let next = update_preview_document(
          attachment,
          committed,
          preview_requested(model),
          accepted~,
          changed~,
        )
        publish(next)
        let expected_revision = if kind == "stale" {
          previous_revision
        } else {
          next.source_revision
        }
        (
          next,
          block_selection_after_render(
            selection,
            expected_revision,
            report_superseded=true,
            emit,
          ),
        )
      }
    }
    EditorFailure => {
      let next = { ..model, fail_next_editor_commit: true }
      publish(next)
      (next, @rabbita_runtime.none)
    }
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
      for decision in transition.decisions() {
        match decision {
          @core.ReplaceCanonicalSource(source) => {
            let (committed, commit_accepted, changed) = commit_source(
              editor,
              next,
              transition.state(),
              source,
              "restore-snapshot",
            )
            next = committed
            accepted = accepted && commit_accepted
            source_changed = source_changed || changed
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
        next = { ..next, state: transition.state() }
      }
      next = update_preview_document(
        attachment,
        next,
        preview_requested(model),
        accepted~,
        changed=source_changed,
      )
      publish(next)
      (next, @rabbita_runtime.none)
    }
    SelectRaw | SelectBlock | SelectPreview => {
      let mode = match event {
        SelectRaw => @core.Raw
        SelectBlock => @core.Block
        SelectPreview => @core.Preview
        _ => @core.Raw
      }
      let transition = @core.reduce(
        model.state,
        @core.ApplicationEvent::SelectMode(mode~),
      )
      let next = update_preview_document(
        attachment,
        { ..model, state: transition.state() },
        preview_requested(model),
        accepted=true,
        changed=false,
      )
      publish(next)
      (next, @rabbita_runtime.none)
    }
    ToggleSplitPreview => {
      let old_requested = preview_requested(model)
      let next = update_preview_document(
        attachment,
        { ..model, split_preview_open: !model.split_preview_open },
        old_requested,
        accepted=true,
        changed=false,
      )
      publish(next)
      (next, @rabbita_runtime.none)
    }
    FocusRaw | FocusBlock | FocusPreview => {
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
          publish(next)
          (next, focus_latest_after_render(locator, token, emit))
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
              publish(next)
              (next, focus_latest_after_render(locator, token, emit))
            }
            @core.Rejected(error) => reject_focus(model, error)
          }
        Err(error) => reject_focus_token(model, error)
      }
    WriteSelection(start~, end~) => {
      publish(model)
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
              emit(SelectionRead(start=read.start(), end=read.end())),
            )
          },
          emit,
        ),
      )
    }
    WriteSelectionFailure => {
      publish(model)
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
    }
    MeasurePreview => {
      publish(model)
      (
        model,
        after_render(
          scheduler => {
            let measurement = @dom_boundary.measure_element_id(
              "loomark-preview",
            )
            scheduler.add(
              emit(
                Measured(
                  width=measurement.offset_width(),
                  height=measurement.offset_height(),
                ),
              ),
            )
          },
          emit,
        ),
      )
    }
    MeasureFailure => {
      publish(model)
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
    }
    SelectionRead(start~, end~) => {
      let next = {
        ..model,
        selection: Some(start.to_string() + ":" + end.to_string()),
      }
      publish(next)
      (next, @rabbita_runtime.none)
    }
    Measured(width~, height~) => {
      let next = {
        ..model,
        measurement: Some(width.to_string() + ":" + height.to_string()),
      }
      publish(next)
      (next, @rabbita_runtime.none)
    }
    EffectFailed(message) => {
      let next = record_error(
        model, "browser-effect-failed", "browser-effect", message,
      )
      publish(next)
      (next, @rabbita_runtime.none)
    }
    BlockSelectionRejected(message, selection) => {
      let next = record_error(
        model, "block-selection-rejected", "browser-effect", message,
      )
      publish(next)
      let command = match selection {
        Some(selection) =>
          block_selection_after_render(
            selection,
            next.source_revision,
            report_superseded=true,
            emit,
          )
        None => @rabbita_runtime.none
      }
      (next, command)
    }
    CustomEvent(detail) => {
      let next = {
        ..model,
        event_detail: Some(detail),
        event_count: model.event_count + 1,
      }
      publish(next)
      (next, @rabbita_runtime.none)
    }
    ControlInstalled => {
      let next = { ..model, control_ready: true }
      publish(next)
      (next, @rabbita_runtime.none)
    }
    SubscriptionInstalled => {
      let next = { ..model, event_install_count: model.event_install_count + 1 }
      publish(next)
      (next, @rabbita_runtime.none)
    }
    SubscriptionUnloaded => {
      let next = { ..model, event_unload_count: model.event_unload_count + 1 }
      publish(next)
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
      publish(next)
      (next, @rabbita_runtime.none)
    }
    StopListening => {
      let next = { ..model, listening: false }
      publish(next)
      (next, @rabbita_runtime.none)
    }
    Fatal(message) => {
      let next = { ..model, fatal: true, error: Some(message), rejection: None }
      publish(next)
      (next, @rabbita_runtime.none)
    }
    Resize(viewport) => {
      let next = {
        ..model,
        compact_split: compact_split_for_width(viewport.width),
        resize_count: model.resize_count + 1,
      }
      publish(next)
      (next, @rabbita_runtime.none)
    }
  }
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
          Some(_) => scheduler.add(tagger(ControlInstalled))
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
            scheduler.add(lifecycle_tagger(SubscriptionInstalled))
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
              scheduler.add(lifecycle_tagger(SubscriptionUnloaded))
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
      emit.map(detail => CustomEvent(detail + "|" + source)),
      emit,
    ),
    driver_test_subscription_loader,
  )
}

///|
fn subscriptions(
  model : DriverModel,
  emit : @cmd.Emit[DriverEvent],
) -> @sub.Sub {
  let control = driver_control_subscription(emit)
  if !model.listening || model.fatal {
    control
  } else {
    @sub.batch([
      @sub.on_resize(emit.map(viewport => Resize(viewport))),
      driver_test_subscription(emit, model.document.source()),
      control,
    ])
  }
}

///|
/// Mount the private application exactly once into a fresh connected element.
#warnings("-alert_unstable")
pub fn mount(host_id : String, source : String) -> String {
  if mounted.val {
    return "{\"ok\":false,\"error\":\"host-already-mounted\"}"
  }
  let replica_id = "loomark-dev-host-" + js_replica_uuid()
  let (editor, attachment) = @markdown.MarkdownEditor::with_semantic_attachment(
    agent_id=replica_id,
    source~,
  ) catch {
    _ => return "{\"ok\":false,\"error\":\"editor-initialization-failed\"}"
  }
  let host_width = @dom_boundary.measure_element_id(host_id)
    .offset_width()
    .to_int() catch {
      _ => SPLIT_STACK_BREAKPOINT
    }
  let initial : DriverModel = {
    state: @core.ApplicationState::ApplicationState(@core.Raw),
    document: editor.snapshot(),
    semantic_document: None,
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
  }
  detached_model.val = None
  detached_focus_token.val = ""
  publish(initial)
  let update = (model, event, emit) => {
    update_model(editor, attachment, model, event, emit)
  }
  let app = @rabbita_runtime.new(() => {
    let (model, emit) = @rabbita_runtime.create_state(
      initial,
      update~,
      subscriptions~,
    )
    let surface = application_surface(model, emit)
    model.view2(surface, (model, surface) => preview_view(model, emit, surface))
  })
  app.mount(host_id)
  mounted.val = true
  "{\"ok\":true}"
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
