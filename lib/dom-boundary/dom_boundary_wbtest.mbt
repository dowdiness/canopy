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
  let result : Result[Unit, DomBoundaryError] = try? decode_status_parts(
    STATUS_INVALID_SELECTOR,
    "not a valid selector",
    Focus,
    Selector("["),
  )
  match result {
    Err(InvalidSelector(selector~, detail~)) => {
      inspect(selector, content="[")
      inspect(detail, content="not a valid selector")
    }
    _ => fail("expected InvalidSelector")
  }
}

///|
test "focus_id reports unavailable document through JS boundary" {
  clear_fake_document()
  let result : Result[Unit, DomBoundaryError] = try? focus_id("missing")
  match result {
    Err(DocumentUnavailable) => ()
    _ => fail("expected DocumentUnavailable")
  }
}

///|
test "focus_id succeeds through JS boundary" {
  install_focus_document("target")
  let result : Result[Unit, DomBoundaryError] = try? focus_id("target")
  clear_fake_document()
  match result {
    Ok(_) => ()
    Err(error) => fail("expected focus_id to succeed, got \{error}")
  }
}

///|
test "focus_selector reports invalid selector through JS boundary" {
  install_throwing_query_document("bad selector")
  let result : Result[Unit, DomBoundaryError] = try? focus_selector("[")
  clear_fake_document()
  match result {
    Err(InvalidSelector(selector~, detail~)) => {
      inspect(selector, content="[")
      inspect(detail, content="bad selector")
    }
    _ => fail("expected InvalidSelector")
  }
}

///|
test "decode_status maps missing elements with target context" {
  let result : Result[Unit, DomBoundaryError] = try? decode_status_parts(
    STATUS_NOT_FOUND,
    "",
    ScrollIntoView,
    Id("missing"),
  )
  match result {
    Err(ElementNotFound(target~)) =>
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
