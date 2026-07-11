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
