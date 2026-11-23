// Startup connection point: the app's only DOM lookups. Measuring, observing,
// and focusing elements is `@browser`'s, which the app asks for through
// subscriptions and commands.

///|
/// Startup connection point. The app starts once the card fonts have
/// loaded, so cards are measured in the faces the browser draws.
fn main {
  let document = @dom.document()
  let window = @dom.window()
  let startup_route = route_of_href(window.current_url())
  let fonts = @browser.document_fonts(document)
  let faces = @browser.document_font_faces(document)
  @browser.load_font_faces(faces, "13.5px \"iA Writer Quattro\"", "Aa")
  @browser.load_font_faces(faces, "13.5px \"IBM Plex Sans JP\"", "あ漢")
  @browser.when_font_faces_ready(faces, () => {
    @rabbita.new(() => app(startup_route, fonts)).mount("app")
  })
}
