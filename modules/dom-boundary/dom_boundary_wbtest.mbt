///|
extern "js" fn clear_fake_document() -> Unit =
  #| () => { delete globalThis.document; }

///|
extern "js" fn install_focus_document(id : String) -> Unit =
  #| (id) => {
  #|   globalThis.document = {
  #|     getElementById: (target) => target === id
  #|       ? { focus() {} }
  #|       : null,
  #|   };
  #| }

///|
extern "js" fn install_throwing_query_document(message : String) -> Unit =
  #| (message) => {
  #|   globalThis.document = {
  #|     querySelector() {
  #|       throw new Error(message);
  #|     },
  #|   };
  #| }

///|
extern "js" fn install_unsupported_query_document() -> Unit =
  #| () => {
  #|   globalThis.document = {
  #|     getElementById() {
  #|       return { focus() {} };
  #|     },
  #|   };
  #| }

///|
extern "js" fn install_descendant_document(
  root_id : String,
  menu_id : String,
  item_id : String,
  fail_focus : Bool,
  invalid_selector : Bool,
) -> Unit =
  #| (rootId, menuId, itemId, failFocus, invalidSelector) => {
  #|   const log = [];
  #|   const item = {
  #|     id: itemId,
  #|     focus() {
  #|       if (failFocus) throw new Error("focus failed");
  #|       log.push(itemId);
  #|     },
  #|   };
  #|   const menu = {
  #|     id: menuId,
  #|     querySelector(selector) {
  #|       if (invalidSelector) throw new Error("bad selector");
  #|       return selector === '[data-active="true"]' ? item : null;
  #|     },
  #|   };
  #|   const listeners = [];
  #|   const host = {
  #|     id: rootId,
  #|     shadowRoot: { children: [menu] },
  #|     children: [menu],
  #|     focus() {
  #|       if (failFocus) throw new Error("focus failed");
  #|       log.push(rootId);
  #|     },
  #|     click() {
  #|       if (failFocus) throw new Error("click failed");
  #|     },
  #|     scrollIntoView() {
  #|       if (failFocus) throw new Error("scroll failed");
  #|     },
  #|     dispatchEvent() {
  #|       if (failFocus) throw new Error("dispatch failed");
  #|       return true;
  #|     },
  #|     addEventListener(eventType, listener) {
  #|       if (failFocus) throw new Error("listen failed");
  #|       listeners.push({ eventType, listener });
  #|     },
  #|     removeEventListener(eventType, listener) {
  #|       if (globalThis.__canopyFailRemove) throw new Error("remove failed");
  #|       const index = listeners.findIndex(
  #|         entry => entry.eventType === eventType && entry.listener === listener,
  #|       );
  #|       if (index >= 0) listeners.splice(index, 1);
  #|     },
  #|   };
  #|   globalThis.__canopyFocusLog = log;
  #|   globalThis.__canopyListeners = listeners;
  #|   globalThis.__canopyFailRemove = false;
  #|   globalThis.document = {
  #|     children: [host],
  #|     getElementById(target) {
  #|       if (target === rootId) return host;
  #|       return null;
  #|     },
  #|   };
  #| }

///|
extern "js" fn set_fail_remove(value : Bool) -> Unit =
  #| (value) => { globalThis.__canopyFailRemove = value; }

///|
extern "js" fn listener_count() -> Int =
  #| () => globalThis.__canopyListeners.length

///|
extern "js" fn remove_remove_method() -> Unit =
  #| () => {
  #|   const host = globalThis.document.getElementById("host");
  #|   delete host.removeEventListener;
  #| }

///|
extern "js" fn emit_detail(kind : Int) -> Unit =
  #| (kind) => {
  #|   const entry = globalThis.__canopyListeners[0];
  #|   let detail = { value: 1 };
  #|   if (kind === 1) detail = () => {};
  #|   if (kind === 2) {
  #|     detail = {};
  #|     detail.self = detail;
  #|   }
  #|   if (kind === 3) {
  #|     detail = {};
  #|     detail.self = detail;
  #|     detail.toString = () => { throw new Error("toString failed"); };
  #|   }
  #|   entry.listener({ detail });
  #| }

///|
extern "js" fn focus_log() -> String =
  #| () => globalThis.__canopyFocusLog.join(",")

///|
extern "js" fn clear_descendant_document() -> Unit =
  #| () => {
  #|   delete globalThis.document;
  #|   delete globalThis.__canopyFocusLog;
  #|   delete globalThis.__canopyListeners;
  #|   delete globalThis.__canopyFailRemove;
  #| }

///|
extern "js" fn install_text_control_document(
  id : String,
  value : String,
  start : Int,
  end : Int,
  direction : String,
) -> Unit =
  #| (id, value, start, end, direction) => {
  #|   const control = {
  #|     id,
  #|     value,
  #|     selectionStart: start,
  #|     selectionEnd: end,
  #|     selectionDirection: direction,
  #|     setSelectionRange(nextStart, nextEnd, nextDirection) {
  #|       globalThis.__canopyTextSelectionWrites += 1;
  #|       this.selectionStart = nextStart;
  #|       this.selectionEnd = nextEnd;
  #|       this.selectionDirection = nextDirection;
  #|     },
  #|   };
  #|   globalThis.__canopyTextSelectionWrites = 0;
  #|   globalThis.document = {
  #|     getElementById: target => target === id ? control : null,
  #|     querySelector: selector => selector === `#${id}` ? control : null,
  #|   };
  #| }

///|
extern "js" fn install_throwing_capability_document(
  id : String,
  message : String,
) -> Unit =
  #| (id, message) => {
  #|   const element = new Proxy({ id }, {
  #|     get(target, property) {
  #|       if (property === "id") return target.id;
  #|       throw new Error(message);
  #|     },
  #|   });
  #|   globalThis.document = {
  #|     getElementById: target => target === id ? element : null,
  #|     querySelector: selector => selector === `#${id}` ? element : null,
  #|   };
  #| }

///|
extern "js" fn install_unsupported_text_input_document(id : String) -> Unit =
  #| (id) => {
  #|   const input = {
  #|     id,
  #|     value: "123",
  #|     selectionStart: null,
  #|     selectionEnd: null,
  #|     selectionDirection: null,
  #|     setSelectionRange() {
  #|       throw new Error("selection unsupported");
  #|     },
  #|   };
  #|   globalThis.document = {
  #|     getElementById: target => target === id ? input : null,
  #|     querySelector: selector => selector === `#${id}` ? input : null,
  #|   };
  #| }

///|
extern "js" fn update_text_control_selection(
  id : String,
  start : Int,
  end : Int,
  direction : String,
) -> Unit =
  #| (id, start, end, direction) => {
  #|   const control = globalThis.document.getElementById(id);
  #|   control.setSelectionRange(start, end, direction);
  #| }

///|
extern "js" fn text_control_selection(id : String) -> String =
  #| (id) => {
  #|   const control = globalThis.document.getElementById(id);
  #|   return [
  #|     control.selectionStart,
  #|     control.selectionEnd,
  #|     control.selectionDirection,
  #|   ].join(":");
  #| }

///|
extern "js" fn text_control_value(id : String) -> String =
  #| (id) => globalThis.document.getElementById(id).value

///|
extern "js" fn text_selection_write_count() -> Int =
  #| () => globalThis.__canopyTextSelectionWrites

///|
extern "js" fn make_text_selection_write_throw(
  id : String,
  message : String,
) -> Unit =
  #| (id, message) => {
  #|   const element = globalThis.document.getElementById(id);
  #|   element.setSelectionRange = () => { throw new Error(message); };
  #| }

///|
extern "js" fn update_element_measurement(
  id : String,
  width : Double,
  height : Double,
) -> Unit =
  #| (id, width, height) => {
  #|   const element = globalThis.document.getElementById(id);
  #|   element.offsetWidth = width;
  #|   element.offsetHeight = height;
  #| }

///|
extern "js" fn clear_text_control_document() -> Unit =
  #| () => {
  #|   delete globalThis.document;
  #|   delete globalThis.__canopyTextSelectionWrites;
  #| }

///|
test "decode_status maps invalid selectors to typed errors" {
  let captured = try {
    decode_status_parts(
      STATUS_INVALID_SELECTOR,
      "not a valid selector",
      Focus,
      Selector("["),
    )
    None
  } catch {
    e => Some(e)
  }
  match captured {
    Some(InvalidSelector(selector~, detail~)) => {
      inspect(selector, content="[")
      inspect(detail, content="not a valid selector")
    }
    _ => fail("expected InvalidSelector")
  }
}

///|
test "focus_id reports unavailable document through JS boundary" {
  clear_fake_document()
  let captured = try {
    focus_id("missing")
    None
  } catch {
    e => Some(e)
  }
  match captured {
    Some(DocumentUnavailable) => ()
    _ => fail("expected DocumentUnavailable")
  }
}

///|
test "focus_id succeeds through JS boundary" {
  install_focus_document("target")
  let captured = try {
    focus_id("target")
    None
  } catch {
    e => Some(e)
  }
  clear_fake_document()
  match captured {
    None => ()
    Some(error) => fail("expected focus_id to succeed, got \{error}")
  }
}

///|
test "focus_selector reports invalid selector through JS boundary" {
  install_throwing_query_document("bad selector")
  let captured = try {
    focus_selector("[")
    None
  } catch {
    e => Some(e)
  }
  clear_fake_document()
  match captured {
    Some(InvalidSelector(selector~, detail~)) => {
      inspect(selector, content="[")
      inspect(detail, content="bad selector")
    }
    _ => fail("expected InvalidSelector")
  }
}

///|
test "decode_status maps missing elements with target context" {
  let captured = try {
    decode_status_parts(STATUS_NOT_FOUND, "", ScrollIntoView, Id("missing"))
    None
  } catch {
    e => Some(e)
  }
  match captured {
    Some(ElementNotFound(target~)) =>
      inspect(target.describe(), content="#missing")
    _ => fail("expected ElementNotFound")
  }
}

///|
test "DomBoundaryError message includes action and target" {
  let error = UnsupportedAction(action=Click, target=Selector(".item"))
  inspect(error.message(), content="DOM element does not support click: .item")
}

///|
test "DomBoundaryError message includes action failure detail" {
  let error = ActionFailed(
    action=DispatchCustomEvent,
    target=Id("btn"),
    detail="CustomEvent is not defined",
  )
  inspect(
    error.message(),
    content="DOM dispatchCustomEvent failed: #btn: CustomEvent is not defined",
  )
}

///|
test "focus_selector_id focuses an active descendant" {
  install_descendant_document("host", "menu", "item", false, false)
  let captured = try {
    focus_selector_id("menu", "[data-active=\"true\"]")
    None
  } catch {
    e => Some(e)
  }
  let log = focus_log()
  clear_descendant_document()
  match captured {
    None => inspect(log, content="item")
    Some(error) => fail("expected focus to succeed, got \{error}")
  }
}

///|
test "focus_selector_id_within searches a shadow root" {
  install_descendant_document("host", "menu", "item", false, false)
  let captured = try {
    focus_selector_id_within("host", "menu", "[data-active=\"true\"]")
    None
  } catch {
    e => Some(e)
  }
  let log = focus_log()
  clear_descendant_document()
  match captured {
    None => inspect(log, content="item")
    Some(error) => fail("expected focus to succeed, got \{error}")
  }
}

///|
test "focus_selector_id reports missing ancestor and item" {
  install_descendant_document("host", "menu", "item", false, false)
  let missing_ancestor = try {
    focus_selector_id("missing", "[data-active=\"true\"]")
    None
  } catch {
    e => Some(e)
  }
  let missing_item = try {
    focus_selector_id("menu", ".missing")
    None
  } catch {
    e => Some(e)
  }
  clear_descendant_document()
  match missing_ancestor {
    Some(ElementNotFound(target=Id("missing"))) => ()
    _ => fail("expected missing ancestor")
  }
  match missing_item {
    Some(ElementNotFound(target=Selector(".missing"))) => ()
    _ => fail("expected missing item")
  }
}

///|
test "focus_selector_id reports invalid selectors" {
  install_descendant_document("host", "menu", "item", false, true)
  let captured = try {
    focus_selector_id("menu", "[")
    None
  } catch {
    e => Some(e)
  }
  clear_descendant_document()
  match captured {
    Some(InvalidSelector(selector="[", detail="bad selector")) => ()
    _ => fail("expected InvalidSelector")
  }
}

///|
test "focus_selector_id reports unsupported query selectors" {
  install_unsupported_query_document()
  let captured = try {
    focus_selector_id("host", ".item")
    None
  } catch {
    e => Some(e)
  }
  clear_fake_document()
  match captured {
    Some(UnsupportedAction(action=Focus, target=Id("host"))) => ()
    _ => fail("expected unsupported focus action")
  }
}

///|
test "focus_selector_id reports focus failures" {
  install_descendant_document("host", "menu", "item", true, false)
  let captured = try {
    focus_selector_id("menu", "[data-active=\"true\"]")
    None
  } catch {
    e => Some(e)
  }
  clear_descendant_document()
  match captured {
    Some(ActionFailed(action=Focus, target=Selector(_), detail="focus failed")) =>
      ()
    _ => fail("expected focus failure")
  }
}

///|
test "listener disposal is idempotent" {
  install_descendant_document("host", "menu", "item", false, false)
  let subscription = listen_custom_event_id("host", "changed", _ => ())
  inspect(listener_count(), content="1")
  subscription.dispose()
  inspect(listener_count(), content="0")
  subscription.dispose()
  inspect(listener_count(), content="0")
  clear_descendant_document()
}

///|
test "listener detail normalization stays string-valued" {
  install_descendant_document("host", "menu", "item", false, false)
  let received : Array[String] = []
  let subscription = listen_custom_event_id("host", "changed", detail => {
    received.push(detail)
  })
  emit_detail(0)
  emit_detail(1)
  emit_detail(2)
  emit_detail(3)
  subscription.dispose()
  clear_descendant_document()
  inspect(received[0], content="{\"value\":1}")
  inspect(received[1], content="")
  inspect(received[2], content="[object Object]")
  inspect(received[3], content="")
}

///|
test "listener and disposal failures map to action errors" {
  install_descendant_document("host", "menu", "item", true, false)
  let listen_error = try {
    let _ = listen_custom_event_id("host", "changed", _ => ())
    None
  } catch {
    e => Some(e)
  }
  clear_descendant_document()
  match listen_error {
    Some(
      ActionFailed(
        action=ListenCustomEvent,
        target=Id("host"),
        detail="listen failed"
      )
    ) => ()
    _ => fail("expected listener failure")
  }

  install_descendant_document("host", "menu", "item", false, false)
  let subscription = listen_custom_event_id("host", "changed", _ => ())
  set_fail_remove(true)
  let dispose_error = try {
    subscription.dispose()
    None
  } catch {
    e => Some(e)
  }
  clear_descendant_document()
  match dispose_error {
    Some(
      ActionFailed(
        action=RemoveCustomEventListener,
        target=EventSubscription,
        detail="remove failed"
      )
    ) => ()
    _ => fail("expected disposal failure")
  }
}

///|
test "unsupported disposal maps to UnsupportedAction" {
  install_descendant_document("host", "menu", "item", false, false)
  let subscription = listen_custom_event_id("host", "changed", _ => ())
  remove_remove_method()
  let captured = try {
    subscription.dispose()
    None
  } catch {
    e => Some(e)
  }
  clear_descendant_document()
  match captured {
    Some(
      UnsupportedAction(
        action=RemoveCustomEventListener,
        target=EventSubscription
      )
    ) => ()
    _ => fail("expected unsupported disposal")
  }
}

///|
test "action failures preserve action context" {
  install_descendant_document("host", "menu", "item", true, false)
  let click_error = try {
    click_id("host")
    None
  } catch {
    e => Some(e)
  }
  let scroll_error = try {
    scroll_id("host", behavior=Instant, block=Start)
    None
  } catch {
    e => Some(e)
  }
  let dispatch_error = try {
    dispatch_custom_event_id("host", "changed")
    None
  } catch {
    e => Some(e)
  }
  clear_descendant_document()
  match click_error {
    Some(ActionFailed(action=Click, target=Id("host"), detail="click failed")) =>
      ()
    _ => fail("expected click failure")
  }
  match scroll_error {
    Some(
      ActionFailed(
        action=ScrollIntoView,
        target=Id("host"),
        detail="scroll failed"
      )
    ) => ()
    _ => fail("expected scroll failure")
  }
  match dispatch_error {
    Some(
      ActionFailed(
        action=DispatchCustomEvent,
        target=Id("host"),
        detail="dispatch failed"
      )
    ) => ()
    _ => fail("expected dispatch failure")
  }
}

///|
test "read_text_selection_id returns a detached UTF-16 selection" {
  install_text_control_document("editor", "A😀B", 1, 3, "backward")
  let selection = read_text_selection_id("editor")
  update_text_control_selection("editor", 0, 0, "none")
  clear_text_control_document()
  inspect(selection.start(), content="1")
  inspect(selection.end(), content="3")
  guard selection.direction() is Backward else {
    fail("expected backward selection direction")
  }
}

///|
test "write_text_selection_id applies UTF-16 offsets and direction" {
  install_text_control_document("editor", "A😀B", 0, 0, "none")
  write_text_selection_id("editor", TextSelection(1, 3, Backward))
  let selection = text_control_selection("editor")
  clear_text_control_document()
  inspect(selection, content="1:3:backward")
}

///|
test "write_text_value_id updates an existing text control" {
  install_text_control_document("editor", "rejected", 8, 8, "none")
  write_text_value_id("editor", "accepted")
  let value = text_control_value("editor")
  clear_text_control_document()
  inspect(value, content="accepted")
}

///|
test "write_text_value_selector resolves an existing text control" {
  install_text_control_document("editor", "before", 6, 6, "none")
  write_text_value_selector("#editor", "after")
  let value = text_control_value("editor")
  clear_text_control_document()
  inspect(value, content="after")
}

///|
test "measure_element_id returns a detached immutable measurement" {
  install_text_control_document("editor", "text", 0, 0, "none")
  update_element_measurement("editor", 120.5, 48.25)
  let measurement = measure_element_id("editor")
  update_element_measurement("editor", 0.0, 0.0)
  clear_text_control_document()
  inspect(measurement.offset_width(), content="120.5")
  inspect(measurement.offset_height(), content="48.25")
}

///|
test "selector text controls preserve collapsed forward selections" {
  install_text_control_document("editor", "A😀B", 1, 3, "backward")
  write_text_selection_selector("#editor", TextSelection(3, 3, Forward))
  let selection = read_text_selection_selector("#editor")
  clear_text_control_document()
  inspect(selection.start(), content="3")
  inspect(selection.end(), content="3")
  guard selection.direction() is Forward else {
    fail("expected forward selection direction")
  }
}

///|
test "invalid text selection ranges reject atomically" {
  install_text_control_document("editor", "A😀B", 1, 3, "backward")
  let negative = try {
    write_text_selection_id("editor", TextSelection(-1, 1, Forward))
    None
  } catch {
    error => Some(error)
  }
  let reversed = try {
    write_text_selection_id("editor", TextSelection(3, 2, Forward))
    None
  } catch {
    error => Some(error)
  }
  let too_long = try {
    write_text_selection_id("editor", TextSelection(0, 5, Forward))
    None
  } catch {
    error => Some(error)
  }
  let selection = text_control_selection("editor")
  let writes = text_selection_write_count()
  clear_text_control_document()
  guard negative is Some(InvalidTextSelection(value_length=4, ..)) else {
    fail("expected negative selection to be rejected")
  }
  guard reversed is Some(InvalidTextSelection(value_length=4, ..)) else {
    fail("expected reversed selection to be rejected")
  }
  guard too_long is Some(InvalidTextSelection(value_length=4, ..)) else {
    fail("expected overlong selection to be rejected")
  }
  inspect(selection, content="1:3:backward")
  inspect(writes, content="0")
}

///|
test "text selection and measurement reject unsupported elements" {
  install_descendant_document("host", "menu", "item", false, false)
  let read_error = try {
    let _ = read_text_selection_id("host")
    None
  } catch {
    error => Some(error)
  }
  let write_error = try {
    write_text_selection_id("host", TextSelection(0, 0, NoDirection))
    None
  } catch {
    error => Some(error)
  }
  let value_error = try {
    write_text_value_id("host", "value")
    None
  } catch {
    error => Some(error)
  }
  let measure_error = try {
    let _ = measure_element_id("host")
    None
  } catch {
    error => Some(error)
  }
  clear_descendant_document()
  guard read_error
    is Some(UnsupportedAction(action=ReadTextSelection, target=Id("host"))) else {
    fail("expected unsupported text selection read")
  }
  guard write_error
    is Some(UnsupportedAction(action=WriteTextSelection, target=Id("host"))) else {
    fail("expected unsupported text selection write")
  }
  guard value_error
    is Some(UnsupportedAction(action=WriteTextValue, target=Id("host"))) else {
    fail("expected unsupported text value write")
  }
  guard measure_error
    is Some(UnsupportedAction(action=MeasureElement, target=Id("host"))) else {
    fail("expected unsupported element measurement")
  }
}

///|
test "write rejects input types without text selection support" {
  install_unsupported_text_input_document("number-input")
  let captured = try {
    write_text_selection_id("number-input", TextSelection(0, 1, NoDirection))
    None
  } catch {
    error => Some(error)
  }
  clear_fake_document()
  guard captured
    is Some(
      UnsupportedAction(action=WriteTextSelection, target=Id("number-input"))
    ) else {
    fail("expected unsupported input type")
  }
}

///|
test "capability getter exceptions retain action context" {
  install_throwing_capability_document("editor", "getter failed")
  let selection_error = try {
    let _ = read_text_selection_id("editor")
    None
  } catch {
    error => Some(error)
  }
  let measurement_error = try {
    let _ = measure_element_selector("#editor")
    None
  } catch {
    error => Some(error)
  }
  clear_fake_document()
  guard selection_error
    is Some(
      ActionFailed(
        action=ReadTextSelection,
        target=Id("editor"),
        detail="getter failed"
      )
    ) else {
    fail("expected selection getter failure")
  }
  guard measurement_error
    is Some(
      ActionFailed(
        action=MeasureElement,
        target=Selector("#editor"),
        detail="getter failed"
      )
    ) else {
    fail("expected measurement getter failure")
  }
}

///|
test "measure_element_selector resolves selector targets" {
  install_text_control_document("editor", "text", 0, 0, "none")
  update_element_measurement("editor", 80.0, 32.0)
  let measurement = measure_element_selector("#editor")
  clear_text_control_document()
  inspect(measurement.offset_width(), content="80")
  inspect(measurement.offset_height(), content="32")
}

///|
test "new DOM actions retain missing and invalid target errors" {
  install_text_control_document("editor", "text", 0, 0, "none")
  let missing = try {
    let _ = read_text_selection_id("missing")
    None
  } catch {
    error => Some(error)
  }
  clear_text_control_document()
  install_throwing_query_document("bad selector")
  let invalid = try {
    let _ = measure_element_selector("[")
    None
  } catch {
    error => Some(error)
  }
  clear_fake_document()
  guard missing is Some(ElementNotFound(target=Id("missing"))) else {
    fail("expected missing text control")
  }
  guard invalid is Some(InvalidSelector(selector="[", detail="bad selector")) else {
    fail("expected invalid measurement selector")
  }
}

///|
test "text selection write exceptions retain action context" {
  install_text_control_document("editor", "text", 1, 2, "forward")
  make_text_selection_write_throw("editor", "write failed")
  let captured = try {
    write_text_selection_id("editor", TextSelection(0, 2, NoDirection))
    None
  } catch {
    error => Some(error)
  }
  let selection = text_control_selection("editor")
  clear_text_control_document()
  guard captured
    is Some(
      ActionFailed(
        action=WriteTextSelection,
        target=Id("editor"),
        detail="write failed"
      )
    ) else {
    fail("expected text selection write failure")
  }
  inspect(selection, content="1:2:forward")
}

///|
test "no-direction text selection round-trips" {
  install_text_control_document("editor", "text", 1, 2, "forward")
  write_text_selection_id("editor", TextSelection(2, 2, NoDirection))
  let selection = read_text_selection_id("editor")
  clear_text_control_document()
  guard selection.direction() is NoDirection else {
    fail("expected no-direction selection")
  }
}

///|
test "unknown text selection directions retain action context" {
  install_text_control_document("editor", "text", 1, 2, "sideways")
  let captured = try {
    let _ = read_text_selection_id("editor")
    None
  } catch {
    error => Some(error)
  }
  clear_text_control_document()
  guard captured
    is Some(
      ActionFailed(
        action=ReadTextSelection,
        target=Id("editor"),
        detail="unknown text selection direction: sideways"
      )
    ) else {
    fail("expected unknown selection direction failure")
  }
}

///|
test "invalid text selection error message includes UTF-16 context" {
  let error = InvalidTextSelection(
    selection=TextSelection(-1, 5, NoDirection),
    value_length=4,
    target=Selector("#editor"),
  )
  inspect(
    error.message(),
    content="invalid text selection [-1, 5) for UTF-16 length 4: #editor",
  )
}
