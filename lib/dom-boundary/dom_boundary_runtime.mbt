///|
const STATUS_OK = 0

///|
const STATUS_DOCUMENT_UNAVAILABLE = 1

///|
const STATUS_NOT_FOUND = 2

///|
const STATUS_UNSUPPORTED_ACTION = 3

///|
const STATUS_INVALID_SELECTOR = 4

///|
const STATUS_ACTION_FAILED = 5

///|
const LOOKUP_ID : String = "id"

///|
const LOOKUP_SELECTOR : String = "selector"

///|
fn js_find_by_id(scope : @js.Any, id : String) -> @js.Any? {
  guard !scope.is_nullish() else { return None }
  if scope.get("id").to_str() == id {
    Some(scope)
  } else {
    let getter = scope.get("getElementById")
    if getter.is_function() {
      let found = scope.call("getElementById", [@js.any(id)])
      if found.is_nullish() {
        js_find_in_children(scope, id)
      } else {
        Some(found)
      }
    } else {
      js_find_in_children(scope, id)
    }
  }
}

///|
fn js_find_in_children(scope : @js.Any, id : String) -> @js.Any? {
  let children = scope.get("children")
  guard !children.is_nullish() else { return None }
  let length : Int = children.get("length").cast()
  for i in 0..<length; found = None {
    match found {
      Some(_) => continue found
      None => continue js_find_by_id(children.at(i), id)
    }
  } nobreak {
    found
  }
}

///|
fn focus_selector_in_scope(
  scope : @js.Any,
  ancestor_id : String,
  selector : String,
) -> Unit raise DomBoundaryError {
  guard js_find_by_id(scope, ancestor_id) is Some(ancestor) else {
    decode_status_parts(STATUS_NOT_FOUND, "", Focus, Id(ancestor_id))
  }
  let query_selector = ancestor.get("querySelector")
  guard query_selector.is_function() else {
    decode_status_parts(STATUS_UNSUPPORTED_ACTION, "", Focus, Id(ancestor_id))
  }
  let item = @js.try_sync(() => {
    ancestor.call("querySelector", [@js.any(selector)])
  }) catch {
    @js.JsError(raw) => {
      let detail = @js.error_detail(raw)
      decode_status_parts(
        STATUS_INVALID_SELECTOR,
        detail,
        Focus,
        Selector(selector),
      )
      @js.undefined()
    }
  }
  guard !item.is_nullish() else {
    decode_status_parts(STATUS_NOT_FOUND, "", Focus, Selector(selector))
  }
  let element : DomElement = item.cast()
  guard js_has_method(element, "focus") else {
    decode_status_parts(
      STATUS_UNSUPPORTED_ACTION,
      "",
      Focus,
      Selector(selector),
    )
  }
  let _ = run_dom_operation(Focus, Selector(selector), () => {
    js_focus(element)
    @js.undefined()
  })
}

///|
pub fn focus_selector_id(
  ancestor_id : String,
  selector : String,
) -> Unit raise DomBoundaryError {
  guard !js_document_unavailable() else { raise DocumentUnavailable }
  let document = @js.global().get("document")
  focus_selector_in_scope(document, ancestor_id, selector)
}

///|
pub fn focus_selector_id_within(
  root_id : String,
  ancestor_id : String,
  selector : String,
) -> Unit raise DomBoundaryError {
  guard !js_document_unavailable() else { raise DocumentUnavailable }
  let document = @js.global().get("document")
  guard js_find_by_id(document, root_id) is Some(root) else {
    decode_status_parts(STATUS_NOT_FOUND, "", Focus, Id(root_id))
  }
  let shadow_root = root.get("shadowRoot")
  let scope = if shadow_root.is_nullish() { root } else { shadow_root }
  focus_selector_in_scope(scope, ancestor_id, selector)
}

///|
fn run_dom_operation(
  action : DomAction,
  target : DomTarget,
  effect : () -> @js.Any,
) -> @js.Any raise DomBoundaryError {
  let result = @js.try_sync(effect) catch {
    @js.JsError(raw) =>
      raise ActionFailed(action~, target~, detail=@js.error_detail(raw))
  }
  result
}

///|
fn focus_target(
  lookup_kind : String,
  raw_target : String,
  target : DomTarget,
) -> Unit raise DomBoundaryError {
  let element = resolve_target(lookup_kind, raw_target, Focus, target)
  guard js_has_method(element, "focus") else {
    raise UnsupportedAction(action=Focus, target~)
  }
  let _ = run_dom_operation(Focus, target, () => {
    js_focus(element)
    @js.undefined()
  })
}

///|
fn click_target(
  lookup_kind : String,
  raw_target : String,
  target : DomTarget,
) -> Unit raise DomBoundaryError {
  let element = resolve_target(lookup_kind, raw_target, Click, target)
  guard js_has_method(element, "click") else {
    raise UnsupportedAction(action=Click, target~)
  }
  let _ = run_dom_operation(Click, target, () => {
    js_click(element)
    @js.undefined()
  })
}

///|
fn scroll_target(
  lookup_kind : String,
  raw_target : String,
  target : DomTarget,
  behavior : ScrollBehavior,
  block : ScrollBlock,
) -> Unit raise DomBoundaryError {
  let element = resolve_target(lookup_kind, raw_target, ScrollIntoView, target)
  guard js_has_method(element, "scrollIntoView") else {
    raise UnsupportedAction(action=ScrollIntoView, target~)
  }
  let _ = run_dom_operation(ScrollIntoView, target, () => {
    js_scroll_into_view(
      element,
      behavior.to_dom_string(),
      block.to_dom_string(),
    )
    @js.undefined()
  })
}

///|
fn dispatch_custom_event_target(
  lookup_kind : String,
  raw_target : String,
  target : DomTarget,
  event_type : String,
  detail : String,
  bubbles~ : Bool,
  composed~ : Bool,
) -> Unit raise DomBoundaryError {
  let element = resolve_target(
    lookup_kind,
    raw_target,
    DispatchCustomEvent,
    target,
  )
  guard js_has_method(element, "dispatchEvent") && js_custom_event_available() else {
    raise UnsupportedAction(action=DispatchCustomEvent, target~)
  }
  let _ = run_dom_operation(DispatchCustomEvent, target, () => {
    js_dispatch_custom_event(element, event_type, detail, bubbles~, composed~)
    @js.undefined()
  })
}

///|
fn listen_custom_event_target(
  lookup_kind : String,
  raw_target : String,
  target : DomTarget,
  event_type : String,
  on_event : (String) -> Unit,
) -> CustomEventSubscription raise DomBoundaryError {
  let element = resolve_target(
    lookup_kind,
    raw_target,
    ListenCustomEvent,
    target,
  )
  guard js_has_method(element, "addEventListener") &&
    js_has_method(element, "removeEventListener") else {
    raise UnsupportedAction(action=ListenCustomEvent, target~)
  }
  let handle = run_dom_operation(ListenCustomEvent, target, () => {
    @js.any(js_listen_custom_event(element, event_type, on_event))
  })
  { handle: handle.cast() }
}

///|
fn dispose_subscription(
  handle : DomEventSubscriptionHandle,
) -> Unit raise DomBoundaryError {
  guard js_subscription_can_dispose(handle) else {
    raise UnsupportedAction(
      action=RemoveCustomEventListener,
      target=EventSubscription,
    )
  }
  let _ = run_dom_operation(RemoveCustomEventListener, EventSubscription, () => {
    js_dispose_custom_event_subscription(handle)
    @js.undefined()
  })
}

///|
fn resolve_target(
  lookup_kind : String,
  raw_target : String,
  action : DomAction,
  target : DomTarget,
) -> DomElement raise DomBoundaryError {
  guard !js_document_unavailable() else { raise DocumentUnavailable }
  let document = @js.global().get("document")
  match lookup_kind {
    LOOKUP_ID => {
      let status = js_get_element_by_id(STATUS_OK, STATUS_NOT_FOUND, raw_target)
      decode_status(status, action, target)
      dom_status_element(status)
    }
    LOOKUP_SELECTOR => {
      let element = @js.try_sync(() => js_query_selector(raw_target)) catch {
        @js.JsError(raw) => {
          decode_status_parts(
            STATUS_INVALID_SELECTOR,
            @js.error_detail(raw),
            action,
            target,
          )
          @js.undefined()
        }
      }
      guard !element.is_nullish() else { raise ElementNotFound(target~) }
      element.cast()
    }
    _ => {
      decode_status_parts(
        STATUS_ACTION_FAILED,
        "unknown lookup kind: \{lookup_kind}",
        action,
        target,
      )
      document.cast()
    }
  }
}

///|
fn decode_status(
  status : DomStatus,
  action : DomAction,
  target : DomTarget,
) -> Unit raise DomBoundaryError {
  decode_status_parts(
    dom_status_code(status),
    dom_status_detail(status),
    action,
    target,
  )
}

///|
fn decode_status_parts(
  status : Int,
  detail : String,
  action : DomAction,
  target : DomTarget,
) -> Unit raise DomBoundaryError {
  match status {
    STATUS_OK => ()
    STATUS_DOCUMENT_UNAVAILABLE => raise DocumentUnavailable
    STATUS_NOT_FOUND => raise ElementNotFound(target~)
    STATUS_UNSUPPORTED_ACTION => raise UnsupportedAction(action~, target~)
    STATUS_INVALID_SELECTOR =>
      match target {
        Selector(selector) => raise InvalidSelector(selector~, detail~)
        Id(_) | EventSubscription =>
          raise UnknownStatus(status~, action~, target~, detail~)
      }
    STATUS_ACTION_FAILED => raise ActionFailed(action~, target~, detail~)
    _ => raise UnknownStatus(status~, action~, target~, detail~)
  }
}

///|
fn DomTarget::describe(self : DomTarget) -> String {
  match self {
    Id(id) => "#\{id}"
    Selector(selector) => selector
    EventSubscription => "custom-event subscription"
  }
}

///|
fn DomAction::describe(self : DomAction) -> String {
  match self {
    Focus => "focus"
    Click => "click"
    ScrollIntoView => "scrollIntoView"
    DispatchCustomEvent => "dispatchCustomEvent"
    ListenCustomEvent => "listenCustomEvent"
    RemoveCustomEventListener => "removeCustomEventListener"
  }
}

///|
fn ScrollBehavior::to_dom_string(self : ScrollBehavior) -> String {
  match self {
    Auto => "auto"
    Instant => "instant"
    Smooth => "smooth"
  }
}

///|
fn ScrollBlock::to_dom_string(self : ScrollBlock) -> String {
  match self {
    Start => "start"
    Center => "center"
    End => "end"
    Nearest => "nearest"
  }
}

///|
fn with_detail(message : String, detail : String) -> String {
  if detail == "" {
    message
  } else {
    message + ": " + detail
  }
}

///|
extern "js" fn dom_status_code(status : DomStatus) -> Int =
  #| (status) => status.status

///|
extern "js" fn dom_status_detail(status : DomStatus) -> String =
  #| (status) => typeof status.detail === "string" ? status.detail : ""

///|
extern "js" fn dom_status_element(status : DomStatus) -> DomElement =
  #| (status) => status.element

///|

///|
extern "js" fn js_document_unavailable() -> Bool =
  #| () => typeof document === "undefined"

///|
extern "js" fn js_get_element_by_id(
  status_ok : Int,
  status_not_found : Int,
  id : String,
) -> DomStatus =
  #| (statusOk, statusNotFound, id) => {
  #|   const element = document.getElementById(id);
  #|   return element
  #|     ? { status: statusOk, detail: "", element }
  #|     : { status: statusNotFound, detail: "" };
  #| }

///|
extern "js" fn js_query_selector(selector : String) -> @js.Any =
  #| (selector) => document.querySelector(selector)

///|
extern "js" fn js_has_method(
  element : DomElement,
  method_name : String,
) -> Bool =
  #| (element, methodName) => !!element && typeof element[methodName] === "function"

///|
extern "js" fn js_custom_event_available() -> Bool =
  #| () => typeof CustomEvent !== "undefined"

///|
extern "js" fn js_focus(element : DomElement) -> Unit =
  #| (element) => { element.focus(); }

///|
extern "js" fn js_click(element : DomElement) -> Unit =
  #| (element) => { element.click(); }

///|
extern "js" fn js_scroll_into_view(
  element : DomElement,
  behavior : String,
  block : String,
) -> Unit =
  #| (element, behavior, block) => {
  #|   element.scrollIntoView({ behavior, block });
  #| }

///|
extern "js" fn js_dispatch_custom_event(
  element : DomElement,
  event_type : String,
  detail : String,
  bubbles~ : Bool,
  composed~ : Bool,
) -> Unit =
  #| (element, eventType, detail, bubbles, composed) => {
  #|   element.dispatchEvent(new CustomEvent(eventType, { detail, bubbles, composed }));
  #|}

///|
/// The listener callback normalizes event detail because it crosses JS later.
extern "js" fn js_listen_custom_event(
  element : DomElement,
  event_type : String,
  on_event : (String) -> Unit,
) -> DomEventSubscriptionHandle =
  #| (element, eventType, onEvent) => {
  #|   const detailToString = (event) => {
  #|     const detail = event && "detail" in event ? event.detail : "";
  #|     if (typeof detail === "string") return detail;
  #|     if (detail == null) return "";
  #|     try {
  #|       const json = JSON.stringify(detail);
  #|       if (typeof json === "string") return json;
  #|       return "";
  #|     } catch (_) {
  #|       try {
  #|         return String(detail);
  #|       } catch (_) {
  #|         return "";
  #|       }
  #|     }
  #|   };
  #|   const listener = (event) => onEvent(detailToString(event));
  #|   element.addEventListener(eventType, listener);
  #|   return { element, eventType, listener, disposed: false };
  #| }

///|
extern "js" fn js_subscription_can_dispose(
  handle : DomEventSubscriptionHandle,
) -> Bool =
  #| (handle) => !!handle &&
  #|   (handle.disposed === true ||
  #|     !!handle.element && typeof handle.element.removeEventListener === "function")

///|
extern "js" fn js_dispose_custom_event_subscription(
  handle : DomEventSubscriptionHandle,
) -> Unit =
  #| (handle) => {
  #|   if (!handle || handle.disposed) return;
  #|   handle.element.removeEventListener(handle.eventType, handle.listener);
  #|   handle.disposed = true;
  #| }
