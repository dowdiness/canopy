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
