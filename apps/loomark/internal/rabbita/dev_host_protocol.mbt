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
pub fn dispatch_private_dev_host(detail : String) -> Unit {
  @dom_boundary.dispatch_custom_event_id(
    "loomark-driver-target",
    "loomark-driver",
    detail~,
  ) catch {
    _ => ()
  }
}
