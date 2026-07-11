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
fn focus_target(
  lookup_kind : String,
  raw_target : String,
  target : DomTarget,
) -> Unit raise DomBoundaryError {
  let element = resolve_target(lookup_kind, raw_target, Focus, target)
  guard js_has_method(element, "focus") else {
    raise UnsupportedAction(action=Focus, target~)
  }
  raise_action_detail(js_focus(element), Focus, target)
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
  raise_action_detail(js_click(element), Click, target)
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
  raise_action_detail(
    js_scroll_into_view(
      element,
      behavior.to_dom_string(),
      block.to_dom_string(),
    ),
    ScrollIntoView,
    target,
  )
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
  raise_action_detail(
    js_dispatch_custom_event(element, event_type, detail, bubbles~, composed~),
    DispatchCustomEvent,
    target,
  )
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
  decode_subscription_status(
    js_listen_custom_event(
      STATUS_OK,
      STATUS_ACTION_FAILED,
      element,
      event_type,
      on_event,
    ),
    ListenCustomEvent,
    target,
  )
}

///|
fn dispose_subscription(
  handle : DomEventSubscriptionHandle,
) -> Unit raise DomBoundaryError {
  decode_status(
    js_dispose_custom_event_subscription(
      STATUS_OK,
      STATUS_UNSUPPORTED_ACTION,
      STATUS_ACTION_FAILED,
      handle,
    ),
    RemoveCustomEventListener,
    EventSubscription,
  )
}

///|
fn resolve_target(
  lookup_kind : String,
  raw_target : String,
  action : DomAction,
  target : DomTarget,
) -> DomElement raise DomBoundaryError {
  if js_document_unavailable() {
    raise DocumentUnavailable
  }
  let status = match lookup_kind {
    LOOKUP_ID => js_get_element_by_id(STATUS_OK, STATUS_NOT_FOUND, raw_target)
    LOOKUP_SELECTOR =>
      js_query_selector(
        STATUS_OK,
        STATUS_NOT_FOUND,
        STATUS_INVALID_SELECTOR,
        raw_target,
      )
    _ => js_status(STATUS_ACTION_FAILED, "unknown lookup kind: \{lookup_kind}")
  }
  decode_status(status, action, target)
  dom_status_element(status)
}

///|
fn raise_action_detail(
  detail : String,
  action : DomAction,
  target : DomTarget,
) -> Unit raise DomBoundaryError {
  if detail != "" {
    raise ActionFailed(action~, target~, detail~)
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
fn decode_subscription_status(
  status : DomStatus,
  action : DomAction,
  target : DomTarget,
) -> CustomEventSubscription raise DomBoundaryError {
  decode_status(status, action, target)
  { handle: dom_status_handle(status) }
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
extern "js" fn js_status(status : Int, detail : String) -> DomStatus =
  #| (status, detail) => ({ status, detail })

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
extern "js" fn dom_status_handle(
  status : DomStatus,
) -> DomEventSubscriptionHandle =
  #| (status) => status.handle

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
extern "js" fn js_query_selector(
  status_ok : Int,
  status_not_found : Int,
  status_invalid_selector : Int,
  selector : String,
) -> DomStatus =
  #| (statusOk, statusNotFound, statusInvalidSelector, selector) => {
  #|   try {
  #|     const element = document.querySelector(selector);
  #|     return element
  #|       ? { status: statusOk, detail: "", element }
  #|       : { status: statusNotFound, detail: "" };
  #|   } catch (error) {
  #|     const detail = error && typeof error.message === "string" ? error.message : String(error);
  #|     return { status: statusInvalidSelector, detail };
  #|   }
  #| }

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
extern "js" fn js_focus(element : DomElement) -> String =
  #| (element) => {
  #|   try {
  #|     element.focus();
  #|     return "";
  #|   } catch (error) {
  #|     return error && typeof error.message === "string" ? error.message : String(error);
  #|   }
  #| }

///|
extern "js" fn js_click(element : DomElement) -> String =
  #| (element) => {
  #|   try {
  #|     element.click();
  #|     return "";
  #|   } catch (error) {
  #|     return error && typeof error.message === "string" ? error.message : String(error);
  #|   }
  #| }

///|
extern "js" fn js_scroll_into_view(
  element : DomElement,
  behavior : String,
  block : String,
) -> String =
  #| (element, behavior, block) => {
  #|   try {
  #|     element.scrollIntoView({ behavior, block });
  #|     return "";
  #|   } catch (error) {
  #|     return error && typeof error.message === "string" ? error.message : String(error);
  #|   }
  #| }

///|
extern "js" fn js_dispatch_custom_event(
  element : DomElement,
  event_type : String,
  detail : String,
  bubbles~ : Bool,
  composed~ : Bool,
) -> String =
  #| (element, eventType, detail, bubbles, composed) => {
  #|   try {
  #|     element.dispatchEvent(new CustomEvent(eventType, { detail, bubbles, composed }));
  #|     return "";
  #|   } catch (error) {
  #|     return error && typeof error.message === "string" ? error.message : String(error);
  #|   }
  #| }

///|
extern "js" fn js_listen_custom_event(
  status_ok : Int,
  status_action_failed : Int,
  element : DomElement,
  event_type : String,
  on_event : (String) -> Unit,
) -> DomStatus =
  #| (statusOk, statusActionFailed, element, eventType, onEvent) => {
  #|   const detailToString = (event) => {
  #|     const detail = event && "detail" in event ? event.detail : "";
  #|     if (typeof detail === "string") return detail;
  #|     if (detail == null) return "";
  #|     try {
  #|       return JSON.stringify(detail);
  #|     } catch (_) {
  #|       return String(detail);
  #|     }
  #|   };
  #|   try {
  #|     const listener = (event) => onEvent(detailToString(event));
  #|     element.addEventListener(eventType, listener);
  #|     return {
  #|       status: statusOk,
  #|       detail: "",
  #|       handle: { element, eventType, listener, disposed: false },
  #|     };
  #|   } catch (error) {
  #|     const detail = error && typeof error.message === "string" ? error.message : String(error);
  #|     return { status: statusActionFailed, detail };
  #|   }
  #| }

///|
extern "js" fn js_dispose_custom_event_subscription(
  status_ok : Int,
  status_unsupported_action : Int,
  status_action_failed : Int,
  handle : DomEventSubscriptionHandle,
) -> DomStatus =
  #| (statusOk, statusUnsupportedAction, statusActionFailed, handle) => {
  #|   if (!handle || handle.disposed) return { status: statusOk, detail: "" };
  #|   if (!handle.element || typeof handle.element.removeEventListener !== "function") {
  #|     return { status: statusUnsupportedAction, detail: "" };
  #|   }
  #|   try {
  #|     handle.element.removeEventListener(handle.eventType, handle.listener);
  #|     handle.disposed = true;
  #|     return { status: statusOk, detail: "" };
  #|   } catch (error) {
  #|     const detail = error && typeof error.message === "string" ? error.message : String(error);
  #|     return { status: statusActionFailed, detail };
  #|   }
  #| }
