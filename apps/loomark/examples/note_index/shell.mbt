// Startup connection point: the app's only DOM lookups. Measuring, observing,
// and focusing elements is `@browser`'s, which the app asks for through
// subscriptions and commands.

///|
/// Startup connection point. The host page provides `#grid-width`, an empty
/// element laid out like the index's content box; its width is the grid's.
/// The app starts once the card fonts have loaded, so cards are measured in
/// the faces the browser draws.
fn main {
  let document = @dom.document()
  let startup_route = route_of_href(@dom.window().current_url())
  guard document.get_element_by_id("grid-width").to_option() is Some(element) &&
    element.to_html_element() is Some(grid_probe) else {
    abort("the host page must provide #grid-width")
  }
  let page = { grid_probe, fonts: @browser.document_fonts(document), }
  let faces = @browser.document_font_faces(document)
  @browser.load_font_faces(faces, "13.5px \"iA Writer Quattro\"", "Aa")
  @browser.load_font_faces(faces, "13.5px \"IBM Plex Sans JP\"", "あ漢")
  @browser.when_font_faces_ready(faces, () => {
    @rabbita.new(() => app(startup_route, page)).mount("app")
  })
}

///|
/// What the app observes on the host page, resolved once at startup.
priv struct HostPage {
  /// The element whose width the grid follows.
  grid_probe : @dom.HTMLElement
  /// The document's font faces, which report faces that finish loading.
  fonts : @dom.EventTarget
}
