///|
/// Public API for the CodeMirror–Rabbita binding.
///
/// Mirrors the function-based pattern used by `rabbita/rabbita/websocket/*`:
/// lifecycle and mutation ops return `@cmd.Cmd`, subscription helpers return
/// `@sub.Sub`, and the per-editor handle the consumer's Model holds is a
/// plain `String` id. All JS handles live in this package's private
/// `editors` registry; raw JavaScript declarations live in the `js/`
/// subpackage.

///|
using @cmd {trait Scheduler}

///|
#cfg(target="js")
pub struct SelRange {
  from : Int
  to : Int
}

///|
#cfg(target="js")
priv struct CmEntry {
  view : @js_ffi.CmView
  theme_comp : @js_ffi.Compartment
  readonly_comp : @js_ffi.Compartment
  keymap_comp : @js_ffi.Compartment
  line_numbers_comp : @js_ffi.Compartment
  line_wrapping_comp : @js_ffi.Compartment
  update_disposable : @js_ffi.Disposable
}

///|
#cfg(target="js")
let editors : Map[String, CmEntry] = {}

///|
priv suberror CmSubscription {
  CmListen(
    String,
    doc~ : @cmd.Emit[String]?,
    selection~ : @cmd.Emit[SelRange]?,
    focus~ : @cmd.Emit[Bool]?
  )
}

///|
#cfg(target="js")
fn report_failure(
  scheduler : &Scheduler,
  failed : @cmd.Emit[String]?,
  message : String,
) -> Unit {
  match failed {
    Some(failed) => scheduler.add(failed(message))
    None => ()
  }
}

///|
#cfg(target="js")
fn not_found_message(id : String) -> String {
  "codemirror editor not found: \{id}"
}

///|
#cfg(target="js")
fn empty_extension() -> @js_ffi.Extension {
  @js_ffi.js_extension_combine([])
}

///|
#cfg(target="js")
fn module_value(cm : @js_ffi.CmModule) -> @js_value.Value {
  cm.0
}

///|
#cfg(target="js")
fn module_value_of_view(view : @js_ffi.CmView) -> @js_value.Value {
  let value : @js_value.Value = view.0
  value.get_with_string("_cmModule")
}

///|
#cfg(target="js")
fn transaction_spec(value : @js_value.Value) -> @js_ffi.TransactionSpec {
  value.cast()
}

///|
#cfg(target="js")
fn theme_extension(theme : @theme.Theme?) -> @js_ffi.Extension {
  match theme {
    Some(theme) => theme.to_extension()
    None => empty_extension()
  }
}

///|
#cfg(target="js")
fn keymap_extension(keymap : @keymap.Keymap?) -> @js_ffi.Extension {
  match keymap {
    Some(keymap) => keymap.to_extension()
    None => empty_extension()
  }
}

///|
#cfg(target="js")
fn readonly_extension(
  cm_value : @js_value.Value,
  enabled : Bool,
) -> @js_ffi.Extension {
  let editor_state : @js_value.Value = cm_value.get_with_string("EditorState")
  let read_only : @js_value.Value = editor_state.get_with_string("readOnly")
  let extension : @js_value.Value = read_only.apply_with_string("of", [enabled])
  @js_ffi.raw_extension(extension)
}

///|
#cfg(target="js")
fn line_numbers_extension(
  cm_value : @js_value.Value,
  enabled : Bool,
) -> @js_ffi.Extension {
  if enabled {
    let extension : @js_value.Value = cm_value.apply_with_string(
      "lineNumbers",
      ([] : Array[@js_value.Value]),
    )
    @js_ffi.raw_extension(extension)
  } else {
    empty_extension()
  }
}

///|
#cfg(target="js")
fn line_wrapping_extension(
  cm_value : @js_value.Value,
  enabled : Bool,
) -> @js_ffi.Extension {
  if enabled {
    let editor_view : @js_value.Value = cm_value.get_with_string("EditorView")
    @js_ffi.raw_extension(editor_view.get_with_string("lineWrapping"))
  } else {
    empty_extension()
  }
}

///|
#cfg(target="js")
fn no_op_update_listener(view : @js_ffi.CmView) -> @js_ffi.Disposable {
  @js_ffi.js_add_update_listener(view, _ => (), _ => (), _ => ())
}

///|
#cfg(target="js")
fn dispose_entry(entry : CmEntry) -> Unit {
  entry.update_disposable.dispose()
  @js_ffi.js_view_destroy(entry.view)
}

///|
#cfg(target="js")
fn with_entry(
  id : String,
  failed : @cmd.Emit[String]?,
  scheduler : &Scheduler,
  op : (CmEntry) -> Unit,
) -> Unit {
  match editors.get(id) {
    Some(entry) => op(entry)
    None => report_failure(scheduler, failed, not_found_message(id))
  }
}

///|
#cfg(target="js")
fn change_spec(from : Int, to : Int?, text : String) -> @js_ffi.TransactionSpec {
  let changes = @js_value.Object::new()
  changes["from"] = from
  match to {
    Some(to) => changes["to"] = to
    None => ()
  }
  changes["insert"] = text
  let spec = @js_value.Object::new()
  spec["changes"] = changes.to_value()
  transaction_spec(spec.to_value())
}

///|
#cfg(target="js")
fn selection_spec(range : SelRange) -> @js_ffi.TransactionSpec {
  let selection = @js_value.Object::new()
  selection["anchor"] = range.from
  selection["head"] = range.to
  let spec = @js_value.Object::new()
  spec["selection"] = selection.to_value()
  transaction_spec(spec.to_value())
}

///|
#cfg(target="js")
fn selection_from_value(value : @js_value.Value) -> SelRange {
  { from: value.get_with_string("from"), to: value.get_with_string("to") }
}

///|
#cfg(target="js")
fn reconfigure(
  view : @js_ffi.CmView,
  compartment : @js_ffi.Compartment,
  extension : @js_ffi.Extension,
) -> Unit {
  @js_ffi.js_dispatch(
    view,
    @js_ffi.js_compartment_reconfigure(compartment, extension),
  )
}

///|
#cfg(target="js")
fn build_initial_extension(
  cm_value : @js_value.Value,
  theme_comp : @js_ffi.Compartment,
  readonly_comp : @js_ffi.Compartment,
  keymap_comp : @js_ffi.Compartment,
  line_numbers_comp : @js_ffi.Compartment,
  line_wrapping_comp : @js_ffi.Compartment,
  initial_theme : @theme.Theme?,
  initial_readonly : Bool,
  initial_keymap : @keymap.Keymap?,
  initial_line_numbers : Bool,
  initial_line_wrapping : Bool,
) -> @js_ffi.Extension {
  @js_ffi.js_extension_combine([
    @js_ffi.js_compartment_of(theme_comp, theme_extension(initial_theme)),
    @js_ffi.js_compartment_of(
      readonly_comp,
      readonly_extension(cm_value, initial_readonly),
    ),
    @js_ffi.js_compartment_of(keymap_comp, keymap_extension(initial_keymap)),
    @js_ffi.js_compartment_of(
      line_numbers_comp,
      line_numbers_extension(cm_value, initial_line_numbers),
    ),
    @js_ffi.js_compartment_of(
      line_wrapping_comp,
      line_wrapping_extension(cm_value, initial_line_wrapping),
    ),
  ])
}

///|
#cfg(target="js")
fn build_listen_key(
  id : String,
  has_doc : Bool,
  has_selection : Bool,
  has_focus : Bool,
) -> String {
  "codemirror.listen(id=\{id},doc=\{has_doc},selection=\{has_selection},focus=\{has_focus})"
}

///|
#cfg(target="js")
fn cm_sub_loader(
  payload : Error,
  scheduler : &@cmd.Scheduler,
) -> @sub.RunningSub? {
  match payload {
    CmListen(id, doc~, selection~, focus~) => {
      guard editors.get(id) is Some(entry) else { return None }

      let mut doc_tagger = doc
      let mut selection_tagger = selection
      let mut focus_tagger = focus

      fn on_doc(value : @js_value.Value) {
        guard doc_tagger is Some(msg) else { return }
        scheduler.add(msg(value.cast()))
      }
      fn on_selection(value : @js_value.Value) {
        guard selection_tagger is Some(msg) else { return }
        scheduler.add(msg(selection_from_value(value)))
      }
      fn on_focus(value : @js_value.Value) {
        guard focus_tagger is Some(msg) else { return }
        scheduler.add(msg(value.cast()))
      }

      entry.update_disposable.dispose()
      let disposable = @js_ffi.js_add_update_listener(
        entry.view,
        on_doc,
        on_selection,
        on_focus,
      )
      editors[id] = { ..entry, update_disposable: disposable }

      Some({
        unload: fn(_) { disposable.dispose() },
        update_tagger: fn(payload) {
          guard payload is CmListen(_, doc~, selection~, focus~) else { return }
          doc_tagger = doc
          selection_tagger = selection
          focus_tagger = focus
        },
      })
    }
    _ => None
  }
}

///|
/// Mount or replace a named CodeMirror editor.
#cfg(target="js")
pub fn mount(
  id : String,
  host_id : String,
  init_doc? : String = "",
  source? : String = "https://esm.sh",
  initial_theme? : @theme.Theme? = None,
  initial_readonly? : Bool = false,
  initial_keymap? : @keymap.Keymap? = None,
  initial_line_numbers? : Bool = true,
  initial_line_wrapping? : Bool = false,
  on_mounted? : @cmd.Cmd,
  failed? : @cmd.Emit[String],
) -> @cmd.Cmd {
  @cmd.custom_cmd(kind=Immediately, scheduler => {
    @js_value.async_run(() => {
      let loaded = Some(@js_ffi.load_codemirror(source~).wait()) catch {
        e => {
          report_failure(
            scheduler,
            failed,
            "codemirror module load failed: \{e.to_string()}",
          )
          None
        }
      }
      guard loaded is Some(value) else { return }
      let cm = @js_ffi.cm_module_of(value)
      let cm_value = module_value(cm)

      if editors.get(id) is Some(old_entry) {
        dispose_entry(old_entry)
        editors.remove(id)
      }

      let theme_comp = @js_ffi.js_compartment_new(cm)
      let readonly_comp = @js_ffi.js_compartment_new(cm)
      let keymap_comp = @js_ffi.js_compartment_new(cm)
      let line_numbers_comp = @js_ffi.js_compartment_new(cm)
      let line_wrapping_comp = @js_ffi.js_compartment_new(cm)
      let extension = build_initial_extension(
        cm_value, theme_comp, readonly_comp, keymap_comp, line_numbers_comp, line_wrapping_comp,
        initial_theme, initial_readonly, initial_keymap, initial_line_numbers, initial_line_wrapping,
      )
      let view = @js_ffi.js_create_view(cm, host_id, init_doc, extension)
      let update_disposable = no_op_update_listener(view)
      editors[id] = {
        view,
        theme_comp,
        readonly_comp,
        keymap_comp,
        line_numbers_comp,
        line_wrapping_comp,
        update_disposable,
      }
      match on_mounted {
        Some(cmd) => scheduler.add(cmd)
        None => ()
      }
    })
  })
}

///|
/// Unmount a named CodeMirror editor.
#cfg(target="js")
pub fn unmount(id : String, failed? : @cmd.Emit[String]) -> @cmd.Cmd {
  @cmd.custom_cmd(kind=Immediately, scheduler => {
    match editors.get(id) {
      Some(entry) => {
        dispose_entry(entry)
        editors.remove(id)
      }
      None => report_failure(scheduler, failed, not_found_message(id))
    }
  })
}

///|
/// Replace the full document, skipping echo dispatches when the document is
/// already current.
#cfg(target="js")
pub fn set_doc(
  id : String,
  doc : String,
  failed? : @cmd.Emit[String],
) -> @cmd.Cmd {
  @cmd.custom_cmd(kind=Immediately, scheduler => {
    with_entry(id, failed, scheduler, entry => {
      let current = @js_ffi.js_state_doc(entry.view)
      if doc != current {
        @js_ffi.js_dispatch(
          entry.view,
          change_spec(0, Some(current.length()), doc),
        )
      }
    })
  })
}

///|
/// Insert text at `pos`.
#cfg(target="js")
pub fn insert(
  id : String,
  pos : Int,
  text : String,
  failed? : @cmd.Emit[String],
) -> @cmd.Cmd {
  @cmd.custom_cmd(kind=Immediately, scheduler => {
    with_entry(id, failed, scheduler, entry => {
      @js_ffi.js_dispatch(entry.view, change_spec(pos, None, text))
    })
  })
}

///|
/// Replace text in `[from, to)` with `text`.
#cfg(target="js")
pub fn replace(
  id : String,
  from : Int,
  to : Int,
  text : String,
  failed? : @cmd.Emit[String],
) -> @cmd.Cmd {
  @cmd.custom_cmd(kind=Immediately, scheduler => {
    with_entry(id, failed, scheduler, entry => {
      @js_ffi.js_dispatch(entry.view, change_spec(from, Some(to), text))
    })
  })
}

///|
/// Set the primary selection range.
#cfg(target="js")
pub fn set_selection(
  id : String,
  range : SelRange,
  failed? : @cmd.Emit[String],
) -> @cmd.Cmd {
  @cmd.custom_cmd(kind=Immediately, scheduler => {
    with_entry(id, failed, scheduler, entry => {
      @js_ffi.js_dispatch(entry.view, selection_spec(range))
    })
  })
}

///|
/// Reconfigure the theme compartment.
#cfg(target="js")
pub fn set_theme(
  id : String,
  theme : @theme.Theme,
  failed? : @cmd.Emit[String],
) -> @cmd.Cmd {
  @cmd.custom_cmd(kind=Immediately, scheduler => {
    with_entry(id, failed, scheduler, entry => {
      reconfigure(entry.view, entry.theme_comp, theme.to_extension())
    })
  })
}

///|
/// Reconfigure the readonly compartment.
#cfg(target="js")
pub fn set_readonly(
  id : String,
  enabled : Bool,
  failed? : @cmd.Emit[String],
) -> @cmd.Cmd {
  @cmd.custom_cmd(kind=Immediately, scheduler => {
    with_entry(id, failed, scheduler, entry => {
      reconfigure(
        entry.view,
        entry.readonly_comp,
        readonly_extension(module_value_of_view(entry.view), enabled),
      )
    })
  })
}

///|
/// Reconfigure the keymap compartment.
#cfg(target="js")
pub fn set_keymap(
  id : String,
  keymap : @keymap.Keymap,
  failed? : @cmd.Emit[String],
) -> @cmd.Cmd {
  @cmd.custom_cmd(kind=Immediately, scheduler => {
    with_entry(id, failed, scheduler, entry => {
      reconfigure(entry.view, entry.keymap_comp, keymap.to_extension())
    })
  })
}

///|
/// Reconfigure the line-number compartment.
#cfg(target="js")
pub fn set_line_numbers(
  id : String,
  enabled : Bool,
  failed? : @cmd.Emit[String],
) -> @cmd.Cmd {
  @cmd.custom_cmd(kind=Immediately, scheduler => {
    with_entry(id, failed, scheduler, entry => {
      reconfigure(
        entry.view,
        entry.line_numbers_comp,
        line_numbers_extension(module_value_of_view(entry.view), enabled),
      )
    })
  })
}

///|
/// Reconfigure the line-wrapping compartment.
#cfg(target="js")
pub fn set_line_wrapping(
  id : String,
  enabled : Bool,
  failed? : @cmd.Emit[String],
) -> @cmd.Cmd {
  @cmd.custom_cmd(kind=Immediately, scheduler => {
    with_entry(id, failed, scheduler, entry => {
      reconfigure(
        entry.view,
        entry.line_wrapping_comp,
        line_wrapping_extension(module_value_of_view(entry.view), enabled),
      )
    })
  })
}

///|
/// Subscribe to CodeMirror document, selection, and focus changes.
#cfg(target="js")
pub fn listen(
  id : String,
  doc? : @cmd.Emit[String],
  selection? : @cmd.Emit[SelRange],
  focus? : @cmd.Emit[Bool],
) -> @sub.Sub {
  let has_doc = doc is Some(_)
  let has_selection = selection is Some(_)
  let has_focus = focus is Some(_)

  guard has_doc || has_selection || has_focus else { @sub.none }
  let key = build_listen_key(id, has_doc, has_selection, has_focus)
  @sub.custom_sub(
    key,
    Local,
    CmListen(id, doc~, selection~, focus~),
    cm_sub_loader,
  )
}
