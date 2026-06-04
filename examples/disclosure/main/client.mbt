// Headless Disclosure PoC.
//
// The "behavior layer" (DisclosureModel + its *_attrs methods) carries state
// and ARIA only — no styling. The consumer's `view` spreads those attrs onto
// its own elements via `attrs=...` and supplies all classes locally. This
// mirrors `examples/resizable` / `lib/resizable`, which is canopy's existing
// instance of the same pattern (Zag `connect()` / Radix prop-spreading).
// This PoC keeps the behavior layer package-private; P2 extraction would be the
// point where these helpers become a library API.

///|
using @html {div, button, h1, p}

///|
using @rabbita {type Cmd, type Emit, type Html}

// ── Behavior layer (headless) ───────────────────────────────────────────────

///|
struct DisclosureModel {
  open : Bool
  content_id : String
}

///|
/// Create disclosure state for a panel whose `content_id` is unique on the page.
fn DisclosureModel::new(
  content_id~ : String,
  open? : Bool = false,
) -> DisclosureModel {
  { open, content_id }
}

///|
fn DisclosureModel::toggle(self : DisclosureModel) -> DisclosureModel {
  { ..self, open: !self.open }
}

///|
/// Trigger attributes: ARIA state + click wiring. No classes, no styling.
fn DisclosureModel::trigger_attrs(
  self : DisclosureModel,
  on_toggle : Cmd,
) -> @html.Attrs {
  @html.Attrs::build()
  .aria_expanded(if self.open { "true" } else { "false" })
  .aria_controls(self.content_id)
  .on_click(_evt => on_toggle)
}

///|
/// Content attributes: identity + collapsed state. No landmark role; this PoC is
/// a stack of independent Disclosure widgets, not an Accordion.
fn DisclosureModel::content_attrs(self : DisclosureModel) -> @html.Attrs {
  @html.Attrs::build().id(self.content_id).hidden(!self.open)
}

// ── Consumer app ────────────────────────────────────────────────────────────

///|
struct Section {
  title : String
  body : String
  disclosure : DisclosureModel
}

///|
fn Section::new(
  title~ : String,
  body~ : String,
  content_id~ : String,
  open? : Bool = false,
) -> Section {
  { title, body, disclosure: DisclosureModel::new(content_id~, open~) }
}

///|
fn Section::toggle_disclosure(self : Section) -> Section {
  { ..self, disclosure: self.disclosure.toggle() }
}

///|
struct Model {
  sections : Array[Section]
}

///|
enum Msg {
  Toggle(Int)
}

///|
let initial_model : Model = {
  sections: [
    Section::new(
      title="Structure reveals meaning",
      body="Color, spacing, and nesting communicate relationships before labels do.",
      content_id="sec-structure",
    ),
    Section::new(
      title="Progressive disclosure",
      body="Clean and focused by default; reveal depth on demand.",
      content_id="sec-progressive",
      open=true,
    ),
    Section::new(
      title="Typography carries weight",
      body="Inter for UI, JetBrains Mono for code — clear zones, calm confidence.",
      content_id="sec-typography",
    ),
  ],
}

///|
fn update(msg : Msg, model : Model) -> Model {
  match msg {
    Toggle(i) =>
      {
        sections: model.sections.mapi((j, section) => {
          if j == i {
            section.toggle_disclosure()
          } else {
            section
          }
        }),
      }
  }
}

///|
test "toggle updates selected section only" {
  let toggled = update(Toggle(0), initial_model)
  match toggled.sections {
    [first, second, third] => {
      assert_eq(first.disclosure.open, true)
      assert_eq(second.disclosure.open, true)
      assert_eq(third.disclosure.open, false)
    }
    _ => fail("expected three disclosure sections")
  }
}

///|
fn section_view(emit : Emit[Msg], index : Int, section : Section) -> Html {
  let disclosure = section.disclosure
  div(class="disclosure", [
    button(
      class="disclosure-trigger",
      attrs=disclosure.trigger_attrs(emit(Toggle(index))),
      section.title,
    ),
    div(class="disclosure-panel", attrs=disclosure.content_attrs(), [
      p(section.body),
    ]),
  ])
}

///|
fn view(emit : Emit[Msg], model : Model) -> Html {
  div(class="page", [
    div(class="hero", [
      p(class="eyebrow", "Headless UI · rabbita 0.12.3"),
      h1("Disclosure"),
      p(
        class="subtitle",
        "Behavior (state + ARIA) is reusable; markup and classes stay local.",
      ),
    ]),
    div(
      class="stack",
      model.sections.mapi((i, section) => section_view(emit, i, section)),
    ),
  ])
}

///|
#cfg(target="js")
fn main {
  let app = @rabbita.simple_cell(model=initial_model, update~, view~)
  @rabbita.new(app).mount("app")
}
