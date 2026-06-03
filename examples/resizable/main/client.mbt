///|
using @html {code, div, h1, h2, p, span, nothing}

///|
using @rabbita {type Cmd, type Emit, type Html}

///|
struct Model {
  corner : @resizable.Model
  split : @resizable.Model
}

///|
enum Msg {
  Corner(@resizable.Msg)
  Split(@resizable.Msg)
}

///|
fn corner_constraints() -> @resizable.Constraints {
  { min_w: 160, max_w: 520, min_h: 110, max_h: 360 }
}

///|
fn split_constraints() -> @resizable.Constraints {
  { min_w: 180, max_w: 560, min_h: 240, max_h: 240 }
}

///|
let initial_model : Model = {
  corner: @resizable.Model::new(w=260, h=160, constraints=corner_constraints()),
  split: @resizable.Model::new(w=320, h=240, constraints=split_constraints()),
}

///|
fn update(_emit : Emit[Msg], msg : Msg, model : Model) -> (Cmd, Model) {
  match msg {
    Corner(resize_msg) => {
      let corner = model.corner.update(resize_msg)
      (@rabbita.none, { ..model, corner, })
    }
    Split(resize_msg) => {
      let split = model.split.update(resize_msg)
      (@rabbita.none, { ..model, split, })
    }
  }
}

///|
fn subscriptions(emit : Emit[Msg], model : Model) -> @sub.Sub {
  @sub.batch([
    model.corner.subscriptions(msg => emit(Corner(msg))),
    model.split.subscriptions(msg => emit(Split(msg))),
  ])
}

///|
fn size_badge(width : Int, height : Int) -> Html {
  span(class="size-badge", "\{width}px × \{height}px")
}

///|
fn corner_box(emit : Emit[Msg], model : @resizable.Model) -> Html {
  div(class="demo-card", [
    h2("Corner-resizable box"),
    p("Drag the corner handle, or focus it and use arrow keys."),
    div(class="corner-box", attrs=model.container_attrs(), [
      div(class="box-content", [
        p(class="eyebrow", "SouthEast handle"),
        h2("Headless behavior, styled by the consumer"),
        size_badge(model.width(), model.height()),
      ]),
      div(
        class="corner-handle",
        attrs=model.handle_attrs(@resizable.Edge::SouthEast, msg => {
          emit(Corner(msg))
        }),
        nothing,
      ),
    ]),
  ])
}

///|
fn split_pane(emit : Emit[Msg], model : @resizable.Model) -> Html {
  div(class="demo-card", [
    h2("Horizontal split pane"),
    p("Drag the vertical separator, or focus it and press Left/Right."),
    div(class="split-shell", [
      div(class="split-left", attrs=model.container_attrs(), [
        div(class="pane-copy", [
          p(class="eyebrow", "Resizable East edge"),
          h2("Inspector"),
          p("The handle is just a div with attrs supplied by resizable."),
          code("width = \{model.width()}px"),
        ]),
        div(
          class="split-handle",
          attrs=model.handle_attrs(@resizable.Edge::East, msg => {
            emit(Split(msg))
          }),
          nothing,
        ),
      ]),
      div(class="split-right", [
        p(class="eyebrow", "Flexible peer"),
        h2("Workspace"),
        p("The right pane does not know about resize state."),
      ]),
    ]),
  ])
}

///|
fn view(emit : Emit[Msg], model : Model) -> Html {
  div(class="page", [
    div(class="hero", [
      p(class="eyebrow", "Rabbita package demo"),
      h1("Headless resizable"),
      p(
        class="subtitle",
        "State, updates, subscriptions, and ARIA are reusable; markup and styling stay local.",
      ),
    ]),
    div(class="demo-grid", [
      corner_box(emit, model.corner),
      split_pane(emit, model.split),
    ]),
  ])
}

///|
#cfg(target="js")
fn main {
  let app = @rabbita.cell(model=initial_model, update~, view~, subscriptions~)
  @rabbita.new(app).mount("app")
}
