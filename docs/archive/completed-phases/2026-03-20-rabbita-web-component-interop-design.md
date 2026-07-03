# Rabbita Web Component Interop Design

**Goal:** Bidirectional web component support for Rabbita — export Rabbita cells as custom elements, and consume external custom elements with first-class property/event binding.

**Context:** Rabbita currently supports rendering custom elements via `@html.node()` (the escape hatch), but lacks property-setting and typed CustomEvent handling on the Attrs API. There is no way to export a Rabbita cell as a `customElements.define()`-registered custom element. The ideal-editor project (`examples/ideal/`) demonstrates the consume pattern manually with JS FFI stubs and `document.querySelector` — this design eliminates that boilerplate.

**Approach:** Thin Wrapper Functions (Approach A from brainstorming). Each exported custom element gets its own Sandbox instance. Light DOM rendering by default. No automatic event emission — cells are self-contained, external communication via `cell_with_dispatch`.

---

## 1. Consume: Enhanced `@html` for Web Component Interop

### 1.1 `Attrs::property(name, value)` — promote to public API

`Attrs::property()` already exists as a package-private method (`fn`, not `pub fn`) at line 56 of `rabbita/html/attrs.mbt`. It writes into `Props.props` and returns `self`. The change is a one-keyword visibility promotion from `fn` to `pub fn`:

```moonbit
pub fn Attrs::property(self, name : String, value : @variant.Variant) -> Self
```

This allows setting JS properties (not just string attributes) on any element, which is essential for web components that accept complex data:

```moonbit
let attrs = @html.Attrs::build()
  .property("projNode", @variant.String(json))
  .property("sourceMap", @variant.String(map_json))
  .property("mode", @variant.String("text"))
```

The VDOM diff engine (`diff_props` in `rabbita/internal/runtime/vdom.mbt`, lines 461-475) already handles property patching — it compares old and new `Props.props` maps, removes stale properties, and sets changed ones via `element.set_property()`. No new diff logic needed.

**SSR note:** `.property()` values are silently dropped during `render_to_string` since JS properties have no HTML serialization. Only `.attribute()` values appear in SSR output. This is expected behavior, not a bug.

### 1.2 `Attrs::on_custom_event(name, handler)` — typed CustomEvent listener

Sugar over `.handler()` that automatically unwraps `event.detail`:

```moonbit
pub fn Attrs::on_custom_event(
  self,
  name : String,
  handler : (@js.Value) -> Cmd,
) -> Self
```

Usage:

```moonbit
let attrs = @html.Attrs::build()
  .on_custom_event("node-selected", fn(detail) {
    dispatch(NodeSelected(detail.get_string("nodeId")))
  })
```

Implementation: wraps the user's handler in a function that calls `event.to_custom_event().get_detail()` (both already exist in `rabbita/dom/custom_event.mbt`) and passes the detail value. Falls back to `@js.Value::null()` if the event is not a CustomEvent or has no detail. No new DOM FFI needed.

**Platform target note:** Must follow the `#cfg(target="js")` / `#cfg(not(target="js"))` dual-implementation pattern used by all existing event handlers in `attrs_event.mbt`. The non-JS stub should be a no-op that returns `self` without registering a handler, ensuring SSR correctness.

### 1.3 Typed wrapper pattern (convention)

For repeated use of a specific custom element, consuming projects write helper functions. This is a recommended pattern, not a framework type:

```moonbit
pub fn canopy_editor(
  mode~ : String = "text",
  proj_node~ : String = "",
  source_map~ : String = "",
  on_node_selected~ : ((String) -> Cmd)? = None,
  children~ : Array[@html.Html] = [],
) -> @html.Html {
  let attrs = @html.Attrs::build()
    .property("mode", @variant.String(mode))
    .property("projNode", @variant.String(proj_node))
    .property("sourceMap", @variant.String(source_map))
  match on_node_selected {
    Some(handler) =>
      // Attrs methods mutate via interior reference and return self;
      // the return value can be ignored since attrs is already mutated.
      ignore(attrs.on_custom_event("node-selected", fn(detail) {
        handler(detail.get_string("nodeId"))
      }))
    None => ()
  }
  @html.node("canopy-editor", attrs, children)
}
```

This eliminates the `bridge_ffi.mbt` FFI stubs and `document.querySelector` pattern visible in the ideal-editor project.

---

## 2. Export: `rabbita/custom_element/` Package

### 2.1 `define()` — register a Rabbita cell as a custom element

```moonbit
pub fn define(
  tag : String,
  observed_attributes~ : Array[String] = [],
  create~ : (Host) -> Cell,
) -> Unit
```

- `tag`: the custom element name (must contain a hyphen per spec, e.g. `"rabbita-counter"`)
- `observed_attributes`: HTML attributes that trigger `attributeChangedCallback`
- `create`: factory function called in `connectedCallback`; receives a `Host` handle, returns a `Cell`

### 2.2 `Host` type — bridge between custom element and cell factory

```moonbit
pub struct Host {
  priv element : @dom.Element
}

pub fn Host::get_attribute(self, name : String) -> String?
pub fn Host::get_property(self, name : String) -> @js.Value
pub fn Host::set_property(self, name : String, value : @js.Value) -> Unit
```

- `get_attribute` / `get_property`: read configuration at creation time
- `set_property`: expose APIs on the element (e.g. a dispatch function) for external JS consumers

### 2.3 Lifecycle mapping

| Custom element callback | Behavior |
|---|---|
| `connectedCallback` | Call `create(host)` → get `Cell` → create `Sandbox` with cell as root → set `sandbox.mount` to a generated container ID → `sandbox.initialize()` → `sandbox.flush()`. Children are rendered into the host element as Light DOM. |
| `disconnectedCallback` | Tear down Sandbox: remove all DOM children, call `drop_live_subtree` on the root instance, clear `live_map`, `dirty_set`, `msg_queue`. |
| `attributeChangedCallback` | Default: full rebuild (teardown → `create(host)` → reinitialize). For message-based updates, the cell author exposes per-action methods via `host.set_property()` and the external consumer calls them directly. |

**Rebuild caveats:** The full teardown-rebuild on attribute change has observable side effects: DOM event listeners are removed and re-attached, transient Sandbox state (dirty set, message queue) is lost, and focus state inside the element is destroyed. For attributes that change rapidly (e.g., animated values), this creates GC pressure. Authors should prefer the `cell_with_dispatch` + explicit property methods pattern for frequently-changing data, reserving observed attributes for values that change infrequently (e.g., initial configuration).

**Teardown ordering:** `Sandbox::teardown()` must run synchronously and set the `torn_down` flag before any pending rAF callback fires. The `flush()` rAF callback checks this flag and bails early, preventing DOM mutations on a disconnected element.

### 2.4 Implementation: JS FFI class generation

`define()` uses inline JS FFI to create and register a custom element class. Pseudocode:

```javascript
class GeneratedElement extends HTMLElement {
  static observedAttributes = [...observed_attributes];

  connectedCallback() {
    this._host = new Host(this);
    this._cell = create(this._host);
    this._sandbox = Sandbox.new(this._cell);
    // Render into `this` (Light DOM) — no shadow root
    this._sandbox.mount_into_element(this);
    this._sandbox.initialize();
    this._sandbox.flush();
  }

  disconnectedCallback() {
    this._sandbox.teardown();
    this.innerHTML = '';
  }

  attributeChangedCallback(name, oldVal, newVal) {
    if (this._sandbox) {
      this.disconnectedCallback();
      this.connectedCallback();
    }
  }
}
customElements.define(tag, GeneratedElement);
```

**Required Sandbox changes** (in `rabbita/internal/runtime/sandbox.mbt`):

1. **`Sandbox::initialize_with_element(element : @dom.Element)`** — new method. Currently `initialize()` looks up the mount element by ID string (`@dom.document().get_element_by_id(self.mount).unwrap()`). Custom elements need to mount into a provided element reference directly. This new method accepts the element and skips the ID lookup. Additionally, unlike `App::mount()` which inserts a wrapper `<div>` first, custom element mounting should render directly into the host element without a wrapper.

2. **`Sandbox::teardown()`** — new method. Must:
   - Cancel any pending `requestAnimationFrame` callback (set a `torn_down` flag checked by the rAF callback, since rAF IDs aren't currently tracked)
   - Call `drop_live_subtree` on the root instance to decrement attach counts and unregister cells
   - Drain and discard `after_render_queue` (do NOT execute pending effects — the element is being removed)
   - Clear `live_map`, `dirty_set`, `msg_queue`
   - Remove all DOM children from the host element

3. **rAF guard for torn-down Sandbox** — the `flush()` method's rAF callback must check a `torn_down` flag and bail early, since a pending rAF from before `disconnectedCallback` could fire after teardown.

### 2.5 `cell_with_dispatch` for external communication

Since cells are self-contained (no automatic event emission), external communication uses `cell_with_dispatch`:

```moonbit
@custom_element.define("rabbita-counter",
  observed_attributes=["initial-count"],
  create=fn(host) {
    let count = host.get_attribute("initial-count")
      .and_then(fn(s) { s.parse_int() })
      .or(0)
    let (dispatch, cell) = @rabbita.cell_with_dispatch(
      model=count,
      update=fn(_dispatch, msg, model) {
        match msg {
          Increment => (@cmd.none, model + 1)
          Decrement => (@cmd.none, model - 1)
          SetCount(n) => (@cmd.none, n)
        }
      },
      view=fn(dispatch, count) {
        @html.div([
          @html.button(on_click=dispatch(Decrement), ["-"]),
          @html.span([@html.text(count.to_string())]),
          @html.button(on_click=dispatch(Increment), ["+"]),
        ])
      },
    )
    // Expose a JS-callable function on the element.
    // The cell author wraps dispatch with a JS-value decoder
    // since Dispatch[Msg] is a MoonBit function (Msg) -> Cmd
    // and cannot be called directly from JS.
    host.set_property("setCount", fn(n) {
      dispatch(SetCount(n))
    } |> to_js_function)
    cell
  },
)
```

**Msg marshalling:** `Dispatch[Msg]` is a MoonBit function `(Msg) -> Cmd`. It has no `to_js_value()` method — MoonBit enum variants are not JS-callable. The cell author must provide explicit JS-facing methods per action they want to expose, converting JS values to MoonBit messages:

```moonbit
// Cell author writes thin adapters for each external action
host.set_property("setCount", fn(n : Int) {
  ignore(dispatch(SetCount(n)))
} |> to_js_function)

host.set_property("increment", fn() {
  ignore(dispatch(Increment))
} |> to_js_function)
```

JS consumer:

```javascript
const counter = document.querySelector('rabbita-counter');
counter.setCount(42);
counter.increment();
```

This avoids a generic serialization layer and keeps the JS API explicit and typed. Each exposed method is a deliberate choice by the cell author.

### 2.6 SSR

`render_to_string` already handles `VNode::Slot` by calling `cell.view()` recursively. Custom elements exported this way produce plain HTML (Light DOM), so existing SSR works without changes. The consumer renders `<rabbita-counter initial-count="5">` as a placeholder, the client-side `define()` hydrates it on `connectedCallback`.

Note: there is no hydration support — `connectedCallback` does a fresh render, replacing any server-rendered content inside the element.

---

## 3. Package Structure

### New package

- **`rabbita/custom_element/`** — `define()`, `Host`

### Modified packages

- **`rabbita/html/`** — promote `Attrs::property()` to `pub fn`, add `Attrs::on_custom_event()`. May need `rabbita/js` added to `moon.pkg` imports for `@js.Value` in the `on_custom_event` signature.
- **`rabbita/internal/runtime/`** — add `Sandbox::initialize_with_element()`, `Sandbox::teardown()`, and `torn_down` flag with rAF guard in `flush()`.

### Unchanged

- **`rabbita/cmd/`**, **`rabbita/dom/`**, **`rabbita/url/`**, etc.

### Internal package access

`rabbita/internal/runtime/` uses MoonBit's `internal` naming convention. Currently it is imported by `rabbita/` and `rabbita/html/`. The new `rabbita/custom_element/` package needs Sandbox access. Two strategies:

- **Preferred: route through `rabbita/`** — add a thin public API on the `rabbita` package that wraps the Sandbox operations needed by custom elements (e.g., `@rabbita.mount_cell_into_element(cell, element)` and `@rabbita.unmount(handle)`). This avoids `rabbita/custom_element/` importing `internal/runtime` directly.
- **Fallback:** If MoonBit allows sibling-level access to `internal` packages, import directly. Verify during implementation.

### Dependency graph

```
rabbita/custom_element/
  ├── rabbita/              (Cell, cell_with_dispatch, mount_cell_into_element)
  ├── rabbita/dom/          (Element, customElements FFI)
  └── rabbita/js/           (Value, interop)

rabbita/                    (modified — new public mount/unmount API)
  └── rabbita/internal/runtime/  (Sandbox — modified)

rabbita/html/               (modified)
  ├── rabbita/internal/runtime/  (Props — already has props field)
  └── rabbita/js/           (may need to add for @js.Value)
```

---

## 4. What's NOT in Scope

- **Shadow DOM** — Light DOM only. Can be added later as an option.
- **Automatic event emission** — cells are self-contained; use `cell_with_dispatch` + `host.set_property("dispatch", ...)` for external communication.
- **Build-time codegen** — no compiler annotations or macros. Pure runtime registration.
- **Shared Sandbox** — each custom element instance gets its own Sandbox.
- **Hydration** — `connectedCallback` does a fresh render, not DOM reconciliation.
- **Attribute → message routing** — default is rebuild; message-based is opt-in via `cell_with_dispatch`.

---

## 5. Migration Path for ideal-editor

Once this is implemented, the ideal-editor's consume-side code simplifies:

**Before** (current `view_editor.mbt` + `bridge_ffi.mbt`):
- Manual `@html.node("canopy-editor", attrs, ...)` with `.handler()` for events
- JS FFI stubs (`js_mount_editor`, `js_reconcile_editor`) for property setting
- `document.querySelector('canopy-editor')` to find the element

**After**:
- `@html.node("canopy-editor", attrs, ...)` with `.property()` for props and `.on_custom_event()` for events
- No FFI stubs needed — properties flow through VDOM diffing
- No `document.querySelector` — the diff engine handles element references

The `bridge_ffi.mbt` file can be removed entirely.
