///|
pub(all) enum DomTarget {
  Id(String)
  Selector(String)
  EventSubscription
} derive(Debug, Eq)

///|
pub(all) enum DomAction {
  Focus
  Click
  ScrollIntoView
  DispatchCustomEvent
  ListenCustomEvent
  RemoveCustomEventListener
} derive(Debug, Eq)

///|
pub(all) enum ScrollBehavior {
  Auto
  Instant
  Smooth
} derive(Debug, Eq)

///|
pub(all) enum ScrollBlock {
  Start
  Center
  End
  Nearest
} derive(Debug, Eq)

///|
pub(all) suberror DomBoundaryError {
  DocumentUnavailable
  InvalidSelector(selector~ : String, detail~ : String)
  ElementNotFound(target~ : DomTarget)
  UnsupportedAction(action~ : DomAction, target~ : DomTarget)
  ActionFailed(action~ : DomAction, target~ : DomTarget, detail~ : String)
  UnknownStatus(
    status~ : Int,
    action~ : DomAction,
    target~ : DomTarget,
    detail~ : String
  )
} derive(Debug, Eq)

///|
#external
priv type DomStatus

///|
#external
priv type DomEventSubscriptionHandle

///|
#external
priv type DomElement

///|
pub struct CustomEventSubscription {
  priv handle : DomEventSubscriptionHandle
}

///|
pub impl Show for DomBoundaryError with fn output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
pub fn DomBoundaryError::message(self : DomBoundaryError) -> String {
  match self {
    DocumentUnavailable => "document is unavailable"
    InvalidSelector(selector~, detail~) =>
      with_detail("invalid DOM selector: \{selector}", detail)
    ElementNotFound(target~) => "DOM element not found: \{target.describe()}"
    UnsupportedAction(action~, target~) =>
      "DOM element does not support \{action.describe()}: \{target.describe()}"
    ActionFailed(action~, target~, detail~) =>
      with_detail(
        "DOM \{action.describe()} failed: \{target.describe()}",
        detail,
      )
    UnknownStatus(status~, action~, target~, detail~) =>
      with_detail(
        "unknown DOM boundary status \{status} for \{action.describe()} on \{target.describe()}",
        detail,
      )
  }
}

///|
pub fn focus_id(id : String) -> Unit raise DomBoundaryError {
  focus_target(LOOKUP_ID, id, Id(id))
}

///|
pub fn focus_selector(selector : String) -> Unit raise DomBoundaryError {
  focus_target(LOOKUP_SELECTOR, selector, Selector(selector))
}

///|
pub fn click_id(id : String) -> Unit raise DomBoundaryError {
  click_target(LOOKUP_ID, id, Id(id))
}

///|
pub fn click_selector(selector : String) -> Unit raise DomBoundaryError {
  click_target(LOOKUP_SELECTOR, selector, Selector(selector))
}

///|
pub fn scroll_id(
  id : String,
  behavior? : ScrollBehavior = Smooth,
  block? : ScrollBlock = Nearest,
) -> Unit raise DomBoundaryError {
  scroll_target(LOOKUP_ID, id, Id(id), behavior, block)
}

///|
pub fn scroll_selector(
  selector : String,
  behavior? : ScrollBehavior = Smooth,
  block? : ScrollBlock = Nearest,
) -> Unit raise DomBoundaryError {
  scroll_target(LOOKUP_SELECTOR, selector, Selector(selector), behavior, block)
}

///|
pub fn dispatch_custom_event_id(
  id : String,
  event_type : String,
  detail? : String = "",
  bubbles? : Bool = true,
  composed? : Bool = true,
) -> Unit raise DomBoundaryError {
  dispatch_custom_event_target(
    LOOKUP_ID,
    id,
    Id(id),
    event_type,
    detail,
    bubbles~,
    composed~,
  )
}

///|
pub fn dispatch_custom_event_selector(
  selector : String,
  event_type : String,
  detail? : String = "",
  bubbles? : Bool = true,
  composed? : Bool = true,
) -> Unit raise DomBoundaryError {
  dispatch_custom_event_target(
    LOOKUP_SELECTOR,
    selector,
    Selector(selector),
    event_type,
    detail,
    bubbles~,
    composed~,
  )
}

///|
pub fn listen_custom_event_id(
  id : String,
  event_type : String,
  on_event : (String) -> Unit,
) -> CustomEventSubscription raise DomBoundaryError {
  listen_custom_event_target(LOOKUP_ID, id, Id(id), event_type, on_event)
}

///|
pub fn listen_custom_event_selector(
  selector : String,
  event_type : String,
  on_event : (String) -> Unit,
) -> CustomEventSubscription raise DomBoundaryError {
  listen_custom_event_target(
    LOOKUP_SELECTOR,
    selector,
    Selector(selector),
    event_type,
    on_event,
  )
}

///|
pub fn CustomEventSubscription::dispose(
  self : CustomEventSubscription,
) -> Unit raise DomBoundaryError {
  dispose_subscription(self.handle)
}
