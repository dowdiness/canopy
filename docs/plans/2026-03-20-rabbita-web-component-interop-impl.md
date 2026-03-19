# Rabbita Web Component Interop Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add bidirectional web component interop to Rabbita — promote `Attrs::property()` to public, add `Attrs::on_custom_event()`, add Sandbox lifecycle methods, add `rabbita/custom_element/` package with `define()` and `Host`.

**Architecture:** The consume side (Tasks 1-2) enhances `rabbita/html/` with two small API additions. The export side (Tasks 3-5) adds `Sandbox::initialize_with_element()` and `Sandbox::teardown()` to the runtime, exposes them through a thin public API on `rabbita/`, then builds `rabbita/custom_element/` on top. Each task is independently testable.

**Tech Stack:** MoonBit, Rabbita v0.11.5, JS FFI (`extern "js"`)

**Spec:** `docs/plans/2026-03-20-rabbita-web-component-interop-design.md`

**Codebase:** `/home/antisatori/ghq/github.com/dowdiness/rabbita/` (module `moonbit-community/rabbita`)

---

## File Structure

### Modified files

| File | Change |
|---|---|
| `rabbita/html/attrs.mbt:56` | Promote `Attrs::property()` from `fn` to `pub fn` |
| `rabbita/html/attrs_event.mbt` | Add `Attrs::on_custom_event()` (JS + non-JS stubs) |
| `rabbita/html/moon.pkg` | Add `rabbita/js` import for `@js.Value` |
| `rabbita/internal/runtime/sandbox.mbt` | Add `torn_down` flag, `initialize_with_element()`, `teardown()`, rAF guard |
| `rabbita/top.mbt` | Add `mount_cell_into_element()` and `unmount_cell()` public wrappers |
| `rabbita/moon.pkg` | (already imports `rabbita/internal/runtime`, no change needed) |

### New files

| File | Purpose |
|---|---|
| `rabbita/custom_element/moon.pkg` | Package config — imports `rabbita/`, `rabbita/dom/`, `rabbita/js/` |
| `rabbita/custom_element/custom_element.mbt` | `define()` function + `Host` type (JS target) |
| `rabbita/custom_element/custom_element_stub.mbt` | Non-JS stubs for `define()` and `Host` |

---

## Task 1: Promote `Attrs::property()` to public

**Files:**
- Modify: `rabbita/html/attrs.mbt:56`
- Verify: `rabbita/html/pkg.generated.mbti`

- [ ] **Step 1: Change `fn` to `pub fn` on `Attrs::property()`**

In `rabbita/html/attrs.mbt`, line 56, change:

```moonbit
fn Attrs::property(self : Attrs, key : String, value : Variant) -> Attrs {
```

to:

```moonbit
/// Set a JavaScript property on the element.
///
/// Properties are applied via the DOM property API (`element[key] = value`),
/// not as HTML attributes. The VDOM diff engine patches properties
/// automatically on re-render.
///
/// **SSR note:** Property values are silently dropped during
/// `render_to_string` since JS properties have no HTML serialization.
pub fn Attrs::property(self : Attrs, key : String, value : Variant) -> Attrs {
```

The method body (`self.0.props[key] = value; self`) stays the same.

- [ ] **Step 2: Verify it compiles**

Run: `cd rabbita && moon check --target js 2>&1 | tail -5`
Expected: no errors

- [ ] **Step 3: Verify the generated interface includes the new public method**

Run: `cd rabbita && moon check --target js && grep 'Attrs::property' rabbita/html/pkg.generated.mbti`
Expected: line showing `pub fn Attrs::property(...)` in the interface

- [ ] **Step 4: Commit**

```bash
cd rabbita && git add rabbita/html/attrs.mbt rabbita/html/pkg.generated.mbti
git commit -m "feat(html): promote Attrs::property() to public API"
```

---

## Task 2: Add `Attrs::on_custom_event()`

**Files:**
- Modify: `rabbita/html/attrs_event.mbt`
- Modify: `rabbita/html/moon.pkg`

- [ ] **Step 1: Add `rabbita/js` import to `rabbita/html/moon.pkg`**

In `rabbita/html/moon.pkg`, add the `rabbita/js` import so `@js.Value` is available:

```json
import {
  "moonbit-community/rabbita/internal/runtime" @runtime,
  "moonbit-community/rabbita/dom",
  "moonbit-community/rabbita/variant",
  "moonbit-community/rabbita/js",
  "moonbitlang/core/debug",
  "moonbitlang/core/list",
}

import {
  "moonbit-community/rabbita",
} for "test"
```

- [ ] **Step 2: Add JS-target `on_custom_event` to `attrs_event.mbt`**

Append to `rabbita/html/attrs_event.mbt`:

```moonbit
///|
/// Listen for a [CustomEvent](https://developer.mozilla.org/en-US/docs/Web/API/CustomEvent)
/// and receive its `detail` payload.
///
/// The handler receives the `detail` value from the CustomEvent. If the event
/// is not a CustomEvent or has no detail, `@js.Value::null()` is passed.
///
/// ```moonbit nocheck
/// attrs.on_custom_event("node-selected", fn(detail) {
///   dispatch(NodeSelected(detail.get_string("nodeId")))
/// })
/// ```
#cfg(target="js")
pub fn Attrs::on_custom_event(
  self : Attrs,
  name : String,
  handler : (@js.Value) -> Cmd,
) -> Attrs {
  self.handler(name, (event, scheduler) => {
    let detail = match event.to_custom_event() {
      Some(ce) => ce.get_detail()
      None => @js.Value::null()
    }
    scheduler.add(handler(detail))
  })
}

```

**Non-JS stub note:** Unlike other event handlers (e.g., `on_scroll`, `on_input`) that use
MoonBit wrapper types (`UIEvent = Unit`, `InputEvent = Unit`), `on_custom_event` uses
`@js.Value` which does not exist on non-JS targets. Since the handler signature contains
`@js.Value`, the non-JS stub is omitted — the `#cfg(target="js")` guard is sufficient.
The `rabbita/html/` package does not currently compile for non-JS targets with `@js.Value`
in signatures, and the `custom_element` package is inherently JS-only.

If non-JS compilation of `rabbita/html/` is needed in the future, a `#cfg(not(target="js"))
type JsValue = Unit` alias can be added to the html package's event types (like `DomEvent = Unit`)
to stub the type.

- [ ] **Step 3: Verify it compiles for both targets**

Run: `cd rabbita && moon check --target js 2>&1 | tail -5`
Expected: no errors

Run: `cd rabbita && moon check --target wasm 2>&1 | tail -5`
Expected: no errors (non-JS stub compiles cleanly)

- [ ] **Step 4: Commit**

```bash
cd rabbita && git add rabbita/html/attrs_event.mbt rabbita/html/moon.pkg rabbita/html/pkg.generated.mbti
git commit -m "feat(html): add Attrs::on_custom_event() for CustomEvent detail handling"
```

---

## Task 3: Add Sandbox lifecycle methods for custom element support

**Files:**
- Modify: `rabbita/internal/runtime/sandbox.mbt`

- [ ] **Step 1: Add `torn_down` flag to Sandbox struct**

In `rabbita/internal/runtime/sandbox.mbt`, add a `torn_down` field to the `Sandbox` struct (line 16-28):

```moonbit
#cfg(target="js")
pub(all) struct Sandbox {
  priv live_map : Map[Id, (&IsCell, Map[InstId, Instance])]
  priv msg_queue : Queue[Id]
  priv after_render_queue : Queue[(&Scheduler) -> Unit]
  priv mut drain_scheduled : Bool
  priv dirty_set : Set[Id]
  priv mut paint_scheduled : Bool
  priv mut torn_down : Bool
  priv root : Instance
  priv captured_link_listener : @dom.Listener
  mut mount : String
  mut on_url_changed : ((Url) -> Cmd)?
  mut on_url_request : ((UrlRequest) -> Cmd)?
}
```

- [ ] **Step 2: Initialize `torn_down` to `false` in `Sandbox::new()`**

In `Sandbox::new()` (around line 63), add `torn_down: false` to the struct literal:

```moonbit
  sandbox = Some({
    root,
    live_map,
    msg_queue: Queue::new(),
    dirty_set: Set::new(),
    on_url_changed: None,
    on_url_request: None,
    paint_scheduled: false,
    drain_scheduled: false,
    torn_down: false,
    mount: "",
    captured_link_listener,
    after_render_queue: Queue::new(),
  })
```

- [ ] **Step 3: Add rAF guard in `flush()` for torn-down Sandbox**

In `Sandbox::flush()`, add a guard at the top of the rAF callback (after `@dom.window().request_animation_frame(fn(_) {`, before `let dirty = ...`):

```moonbit
    @dom.window().request_animation_frame(fn(_) {
      if self.torn_down {
        return
      }
      let dirty = self.dirty_set.to_array()
```

- [ ] **Step 4: Add `Sandbox::initialize_with_element()`**

Add this method after `Sandbox::initialize()`:

```moonbit
///|
/// Initialize the sandbox by mounting into a provided DOM element directly.
///
/// Unlike `initialize()` which looks up the mount element by ID string,
/// this method accepts an element reference. Used by custom element
/// integration where the host element is already available.
#cfg(target="js")
pub fn Sandbox::initialize_with_element(self : Self, element : @dom.Element) -> Unit {
  let root = self.root
  self.dirty_set.add(root.cell.flags().id)
  let vnode = root.cell.view()
  let inode = vnode.insert(self, root, element.as_node(), null())
  self.root.inode = Some(inode)
}
```

- [ ] **Step 5: Add `Sandbox::teardown()`**

Add this method:

```moonbit
///|
/// Tear down the sandbox, cleaning up all live cells and pending state.
///
/// Sets the `torn_down` flag so any pending rAF callback will bail early.
/// Removes all live cell instances, clears queues, and removes DOM children
/// from the host element.
#cfg(target="js")
pub fn Sandbox::teardown(self : Self, host : @dom.Element) -> Unit {
  self.torn_down = true
  // Drop all live cell instances
  self.drop_live_subtree(self.root)
  // Clear all pending state
  while self.msg_queue.pop() is Some(_) { }
  while self.after_render_queue.pop() is Some(_) { }
  self.dirty_set.clear()
  self.live_map.clear()
  // Remove DOM children
  host.set_inner_html("")
}
```

- [ ] **Step 6: Verify it compiles**

Run: `cd rabbita && moon check --target js 2>&1 | tail -5`
Expected: no errors

- [ ] **Step 7: Commit**

```bash
cd rabbita && git add rabbita/internal/runtime/sandbox.mbt rabbita/internal/runtime/pkg.generated.mbti
git commit -m "feat(runtime): add Sandbox lifecycle methods for custom element support

Add initialize_with_element() for mounting into a provided element ref,
teardown() for clean disposal, and torn_down guard in flush() to prevent
post-disconnect DOM mutations."
```

---

## Task 4: Add public mount/unmount API on `rabbita/`

**Files:**
- Modify: `rabbita/top.mbt`

The `rabbita/custom_element/` package cannot import `rabbita/internal/runtime/` directly (internal convention). We expose thin wrappers on the `rabbita/` package which already imports it.

- [ ] **Step 1: Add `MountHandle` type and `mount_cell_into_element()`**

Append to `rabbita/top.mbt`:

```moonbit
///|
/// Opaque handle to a mounted cell, used for teardown.
#cfg(target="js")
pub struct MountHandle {
  priv sandbox : @runtime.Sandbox
}

///|
/// Mount a cell into a DOM element, rendering as Light DOM children.
///
/// Returns a `MountHandle` for later teardown via `unmount_cell()`.
/// Unlike `App::mount()`, this does not insert a wrapper div or set up
/// routing — it renders the cell's view directly into the element.
#cfg(target="js")
pub fn mount_cell_into_element(
  root : Cell,
  element : @dom.Element,
) -> MountHandle {
  let sandbox = @runtime.Sandbox::new(root.0)
  sandbox.initialize_with_element(element)
  sandbox.flush()
  MountHandle::{ sandbox }
}

///|
/// Tear down a previously mounted cell, removing all DOM children and
/// cleaning up runtime state.
#cfg(target="js")
pub fn unmount_cell(handle : MountHandle, host : @dom.Element) -> Unit {
  handle.sandbox.teardown(host)
}
```

- [ ] **Step 2: Verify it compiles**

Run: `cd rabbita && moon check --target js 2>&1 | tail -5`
Expected: no errors

- [ ] **Step 3: Commit**

```bash
cd rabbita && git add rabbita/top.mbt rabbita/pkg.generated.mbti
git commit -m "feat: add mount_cell_into_element() and unmount_cell() public API

Thin wrappers over Sandbox lifecycle methods, enabling custom element
integration without importing internal/runtime directly."
```

---

## Task 5: Create `rabbita/custom_element/` package

**Files:**
- Create: `rabbita/custom_element/moon.pkg`
- Create: `rabbita/custom_element/custom_element.mbt`
- Create: `rabbita/custom_element/custom_element_stub.mbt`

- [ ] **Step 1: Create `moon.pkg`**

Create `rabbita/custom_element/moon.pkg`:

```json
import {
  "moonbit-community/rabbita",
  "moonbit-community/rabbita/dom",
  "moonbit-community/rabbita/js",
}
```

- [ ] **Step 2: Create the JS-target implementation**

Create `rabbita/custom_element/custom_element.mbt`:

```moonbit
///|
/// A handle to the host custom element, available inside the `create` factory.
///
/// Provides access to the element's attributes and properties so the cell
/// factory can read configuration and expose JS-callable APIs.
#cfg(target="js")
pub struct Host {
  priv element : @dom.Element
}

///|
/// Read an HTML attribute from the host element.
///
/// Note: `@dom.Element.get_attribute` returns `String` (empty string if absent).
/// We wrap it to return `String?` for a more ergonomic API — empty string maps
/// to `None` since HTML attributes are never intentionally empty in this context.
#cfg(target="js")
pub fn Host::get_attribute(self : Host, name : String) -> String? {
  let v = self.element.get_attribute(name)
  if v == "" { None } else { Some(v) }
}

///|
/// Read a JavaScript property from the host element as a raw JS value.
///
/// Uses a direct FFI call since `@dom.Element.get_property` returns
/// `@js.Optional[String]` which is too narrow for arbitrary property types.
#cfg(target="js")
pub fn Host::get_property(self : Host, name : String) -> @js.Value {
  js_host_get_property(self.element, name)
}

///|
#cfg(target="js")
extern "js" fn js_host_get_property(
  element : @dom.Element,
  name : String,
) -> @js.Value = "(el, name) => el[name] ?? null"

///|
/// Set a JavaScript property on the host element.
///
/// Use this to expose JS-callable functions or data on the element instance.
#cfg(target="js")
pub fn Host::set_property(self : Host, name : String, value : @js.Value) -> Unit {
  self.element.set_property(name, value)
}

///|
/// Register a Rabbita cell as a custom element.
///
/// - `tag`: the custom element name (must contain a hyphen, e.g. `"my-counter"`)
/// - `observed_attributes`: HTML attributes that trigger rebuild on change
/// - `create`: factory function called in `connectedCallback`; receives a `Host`
///   handle and returns a `Cell`
///
/// Each custom element instance gets its own Sandbox. Content is rendered as
/// Light DOM (no Shadow Root). On `disconnectedCallback`, the Sandbox is torn
/// down and DOM children are removed.
///
/// ## Example
///
/// ```moonbit nocheck
/// @custom_element.define("my-counter",
///   observed_attributes=["initial-count"],
///   create=fn(host) {
///     let count = host.get_attribute("initial-count")
///       .and_then(fn(s) { try { s.to_int!() } catch { _ => None } })
///       .or(0)
///     @rabbita.simple_cell(model=count, update=..., view=...)
///   },
/// )
/// ```
#cfg(target="js")
pub fn define(
  tag : String,
  observed_attributes~ : Array[String] = [],
  create~ : (Host) -> @rabbita.Cell,
) -> Unit {
  js_define_custom_element(tag, observed_attributes, create)
}

///|
#cfg(target="js")
extern "js" fn js_define_custom_element(
  tag : String,
  observed_attributes : Array[String],
  create : (Host) -> @rabbita.Cell,
) -> Unit =
  #| (tag, observedAttributes, createFn) => {
  #|   class RabbitaElement extends HTMLElement {
  #|     static get observedAttributes() { return observedAttributes; }
  #|     connectedCallback() {
  #|       this._mountHandle = globalThis.__rabbita_mount(createFn, this);
  #|     }
  #|     disconnectedCallback() {
  #|       if (this._mountHandle) {
  #|         globalThis.__rabbita_unmount(this._mountHandle, this);
  #|         this._mountHandle = null;
  #|       }
  #|     }
  #|     attributeChangedCallback(name, oldVal, newVal) {
  #|       if (oldVal !== newVal && this._mountHandle) {
  #|         this.disconnectedCallback();
  #|         this.connectedCallback();
  #|       }
  #|     }
  #|   }
  #|   customElements.define(tag, RabbitaElement);
  #| }

///|
/// Register the global JS bridge functions that the custom element class calls.
///
/// Must be called once before any `define()` calls. This is separated from
/// `define()` because MoonBit extern JS cannot capture MoonBit closures
/// directly in class methods — the bridge uses global functions instead.
#cfg(target="js")
pub fn init_bridge() -> Unit {
  js_init_bridge(
    fn(create, element) {
      let host = Host::{ element }
      let cell = create(host)
      @rabbita.mount_cell_into_element(cell, element)
    },
    fn(handle, element) { @rabbita.unmount_cell(handle, element) },
  )
}

///|
#cfg(target="js")
extern "js" fn js_init_bridge(
  mount_fn : ((Host) -> @rabbita.Cell, @dom.Element) -> @rabbita.MountHandle,
  unmount_fn : (@rabbita.MountHandle, @dom.Element) -> Unit,
) -> Unit =
  #| (mountFn, unmountFn) => {
  #|   globalThis.__rabbita_mount = mountFn;
  #|   globalThis.__rabbita_unmount = unmountFn;
  #| }
```

- [ ] **Step 3: Create the non-JS stub**

Create `rabbita/custom_element/custom_element_stub.mbt`.

**Important:** `@js.Value` is defined with `#cfg(target="js")` only and does not exist
on non-JS targets. The stub must avoid referencing it. Since `Host` and `define()` are
only meaningful in a browser, the non-JS stubs provide the minimal type definitions
needed for cross-compilation but no `get_property`/`set_property` (which require `@js.Value`).

```moonbit
///|
#cfg(not(target="js"))
pub struct Host {}

///|
#cfg(not(target="js"))
pub fn Host::get_attribute(self : Host, name : String) -> String? {
  ignore((self, name))
  None
}

///|
/// `Host::get_property` and `Host::set_property` are JS-only — they use
/// `@js.Value` which does not exist on non-JS targets. No stubs provided;
/// the `#cfg(target="js")` guard on the JS-target methods is sufficient.

///|
#cfg(not(target="js"))
pub fn define(
  tag : String,
  observed_attributes~ : Array[String] = [],
  create~ : (Host) -> @rabbita.Cell,
) -> Unit {
  ignore((tag, observed_attributes, create))
}

///|
#cfg(not(target="js"))
pub fn init_bridge() -> Unit {
  ()
}
```

- [ ] **Step 4: Verify it compiles for both targets**

Run: `cd rabbita && moon check --target js 2>&1 | tail -5`
Expected: no errors

Run: `cd rabbita && moon check --target wasm 2>&1 | tail -5`
Expected: no errors

- [ ] **Step 5: Commit**

```bash
cd rabbita && git add rabbita/custom_element/
git commit -m "feat(custom_element): add define() and Host for exporting cells as custom elements

New rabbita/custom_element/ package. Each custom element instance gets
its own Sandbox with Light DOM rendering. Host type provides attribute/
property access for the cell factory. init_bridge() registers the global
JS functions used by the generated element class."
```

---

## Task 6: End-to-end verification

**Files:**
- None (verification only)

- [ ] **Step 1: Full project build check**

Run: `cd rabbita && moon check --target js 2>&1 | tail -10`
Expected: all packages compile cleanly

- [ ] **Step 2: Run existing tests to ensure no regressions**

Run: `cd rabbita && moon test 2>&1 | tail -20`
Expected: all existing tests pass

- [ ] **Step 3: Verify public API surface**

Run: `cd rabbita && grep -n 'pub fn' rabbita/custom_element/custom_element.mbt`
Expected: `Host::get_attribute`, `Host::get_property`, `Host::set_property`, `define`, `init_bridge`

Run: `cd rabbita && grep 'pub fn Attrs::property' rabbita/html/attrs.mbt`
Expected: `pub fn Attrs::property`

Run: `cd rabbita && grep 'pub fn Attrs::on_custom_event' rabbita/html/attrs_event.mbt`
Expected: two entries (JS and non-JS)

- [ ] **Step 4: Tag completion**

No tagging — this is a feature branch. Verify with `git log --oneline -6` that all commits are present.
