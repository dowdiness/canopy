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
  ReadTextSelection
  WriteTextValue
  WriteTextSelection
  MeasureElement
  DispatchCustomEvent
  CopyText
  DownloadText
  Reload
  ListenCustomEvent
  RemoveCustomEventListener
} derive(Debug, Eq)

///|
pub(all) enum TextSelectionDirection {
  NoDirection
  Forward
  Backward
} derive(Debug, Eq)

///|
/// An immutable half-open text selection measured in UTF-16 code units.
pub struct TextSelection {
  priv start : Int
  priv end : Int
  priv direction : TextSelectionDirection
} derive(Debug, Eq)

///|
/// A detached element measurement in CSS pixels.
pub struct ElementMeasurement {
  priv offset_width : Double
  priv offset_height : Double
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
  InvalidTextSelection(
    selection~ : TextSelection,
    value_length~ : Int,
    target~ : DomTarget
  )
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
pub fn TextSelection::TextSelection(
  start : Int,
  end : Int,
  direction : TextSelectionDirection,
) -> TextSelection {
  { start, end, direction }
}

///|
pub fn TextSelection::start(self : TextSelection) -> Int {
  self.start
}

///|
pub fn TextSelection::end(self : TextSelection) -> Int {
  self.end
}

///|
pub fn TextSelection::direction(self : TextSelection) -> TextSelectionDirection {
  self.direction
}

///|
fn ElementMeasurement::ElementMeasurement(
  offset_width : Double,
  offset_height : Double,
) -> ElementMeasurement {
  { offset_width, offset_height }
}

///|
pub fn ElementMeasurement::offset_width(self : ElementMeasurement) -> Double {
  self.offset_width
}

///|
pub fn ElementMeasurement::offset_height(self : ElementMeasurement) -> Double {
  self.offset_height
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
    InvalidTextSelection(selection~, value_length~, target~) =>
      "invalid text selection [\{selection.start()}, \{selection.end()}) for UTF-16 length \{value_length}: \{target.describe()}"
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
pub fn read_text_selection_id(
  id : String,
) -> TextSelection raise DomBoundaryError {
  read_text_selection_target(LOOKUP_ID, id, Id(id))
}

///|
pub fn read_text_selection_selector(
  selector : String,
) -> TextSelection raise DomBoundaryError {
  read_text_selection_target(LOOKUP_SELECTOR, selector, Selector(selector))
}

///|
pub fn write_text_value_id(
  id : String,
  value : String,
) -> Unit raise DomBoundaryError {
  write_text_value_target(LOOKUP_ID, id, Id(id), value)
}

///|
pub fn write_text_value_selector(
  selector : String,
  value : String,
) -> Unit raise DomBoundaryError {
  write_text_value_target(LOOKUP_SELECTOR, selector, Selector(selector), value)
}

///|
pub fn write_text_selection_id(
  id : String,
  selection : TextSelection,
) -> Unit raise DomBoundaryError {
  write_text_selection_target(LOOKUP_ID, id, Id(id), selection)
}

///|
pub fn write_text_selection_selector(
  selector : String,
  selection : TextSelection,
) -> Unit raise DomBoundaryError {
  write_text_selection_target(
    LOOKUP_SELECTOR,
    selector,
    Selector(selector),
    selection,
  )
}

///|
pub fn measure_element_id(
  id : String,
) -> ElementMeasurement raise DomBoundaryError {
  measure_element_target(LOOKUP_ID, id, Id(id))
}

///|
pub fn measure_element_selector(
  selector : String,
) -> ElementMeasurement raise DomBoundaryError {
  measure_element_target(LOOKUP_SELECTOR, selector, Selector(selector))
}

///|
/// Copy exact text through the host clipboard boundary.
pub fn copy_text(text : String) -> Unit raise DomBoundaryError {
  let target = EventSubscription
  guard !js_document_unavailable() else { raise DocumentUnavailable }
  guard js_copy_text(text) else {
    raise UnsupportedAction(action=CopyText, target~)
  }
}

///|
/// Download exact text as a named file through the host DOM boundary.
pub fn download_text(
  filename : String,
  text : String,
) -> Unit raise DomBoundaryError {
  let target = EventSubscription
  guard !js_document_unavailable() else { raise DocumentUnavailable }
  guard js_download_text(filename, text) else {
    raise ActionFailed(action=DownloadText, target~, detail="download failed")
  }
}

///|
/// Explicitly reload the host page.
pub fn reload() -> Unit raise DomBoundaryError {
  let target = EventSubscription
  guard !js_document_unavailable() else { raise DocumentUnavailable }
  guard js_reload() else {
    raise ActionFailed(action=Reload, target~, detail="reload failed")
  }
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
