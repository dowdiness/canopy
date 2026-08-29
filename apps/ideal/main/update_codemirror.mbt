///|
fn code_mirror_source_version_matches(
  event_source_version : String,
  current_source_version : String,
) -> Bool {
  event_source_version != "" && event_source_version == current_source_version
}

///|
fn apply_code_mirror_changes(
  editor : @editor.SyncEditor[@ast.Term],
  changes : Array[@cm.ChangeDelta],
  timestamp_ms : Int,
) -> Bool raise Failure {
  let cursor = editor.get_cursor()
  guard changes.length() == 1 else { return false }
  let change = changes[0]
  let accepted = editor.apply_text_edit_exact(
    change.from,
    change.to - change.from,
    change.insert,
    timestamp_ms,
  ) catch {
    error => {
      editor.move_cursor(cursor)
      raise error
    }
  }
  editor.move_cursor(cursor)
  accepted
}

///|
fn handle_codemirror(
  emit : Emit[Msg],
  msg : Msg,
  model : Model,
) -> (Cmd, Model)? raise {
  let _ = emit
  match msg {
    CmMounted => {
      let new_model = { ..model, mounted: true }
      Some((sync_after_external_crdt_change(new_model), new_model))
    }
    CmChanges(event) => {
      // Local single-range CodeMirror transactions already carry an exact
      // pre-transaction splice. Apply that directly only while the CRDT source
      // version still matches the source currently displayed in CodeMirror;
      // otherwise use the transaction's captured document snapshot fallback.
      let changes = event.changes
      let current_source_version = Hash::hash(model.editor.get_version()).to_string()
      js_perf_begin("cmDocChangedHandler")
      js_perf_begin("syncEditorApply")
      let timestamp_ms = js_now_ms()
      let fallback_text = try {
        js_perf_begin("incrementalTextApply")
        let applied = if code_mirror_source_version_matches(
            event.source_version,
            current_source_version,
          ) {
          apply_code_mirror_changes(model.editor, changes, timestamp_ms)
        } else {
          false
        }
        js_perf_end("incrementalTextApply")
        if applied {
          None
        } else {
          model.editor.set_text_and_record(event.doc, timestamp_ms)
          Some(event.doc)
        }
      } catch {
        error => {
          js_perf_end("incrementalTextApply")
          js_perf_end("syncEditorApply")
          js_perf_end("cmDocChangedHandler")
          raise error
        }
      }
      js_perf_end("syncEditorApply")
      js_perf_begin("projectionRefresh")
      let new_model = try {
        let next = refresh({ ..model, next_timestamp: model.next_timestamp + 1 })
        js_perf_end("projectionRefresh")
        next
      } catch {
        error => {
          js_perf_end("projectionRefresh")
          js_perf_end("cmDocChangedHandler")
          raise error
        }
      }
      let actual_text = new_model.editor.get_text()
      let source_version = Hash::hash(model.editor.get_version()).to_string()
      js_perf_begin("publicationPrepare")
      let sync_cmd = match fallback_text {
        Some(text) =>
          if actual_text != text {
            @cm.set_doc(model.cm_id, actual_text, source_version~)
          } else {
            @cm.set_source_version(model.cm_id, source_version)
          }
        None => @cm.set_source_version(model.cm_id, source_version)
      }
      let publication_effect = @rabbita.effect(fn() {
        js_perf_begin("localPublicationEffect")
        js_after_local_text_edit()
        js_perf_end("localPublicationEffect")
      })
      let cmd = @rabbita.batch([sync_cmd, publication_effect])
      js_perf_end("publicationPrepare")
      js_perf_end("cmDocChangedHandler")
      Some((cmd, new_model))
    }
    CmSelectionChanged(range) =>
      Some(
        (
          @rabbita.effect(() => {
            js_after_cm_selection_changed(range.from, range.to)
          }),
          model,
        ),
      )
    CmFocusChanged(_) => Some((none, model))
    _ => None
  }
}
