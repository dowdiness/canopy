///| Apply DomPatch[] to real DOM elements via js_ffi Any.

///| Container is looked up by ID ("html-preview").

///|
/// Element registry is a module-level JS Map (no globalThis).
let container_id : String = "html-preview"

///|
/// Module-level element registry: created once, persists across FFI calls.
let element_registry : @js.Any = {
  let map = @js.global().get("Map")
  map.construct([])
}

///|
/// Clear the element registry (call before starting a new stream).
pub fn reset_jsx_state() -> Unit {
  let _ = element_registry.call("clear", [])
}

///|
/// Apply patches and return JSON array of remaining NodeIds.
pub fn apply_patches(patches_json : String) -> String {
  let container = @js.global()
    .get("document")
    .call("getElementById", [@js.any(container_id)])
  let patches_arr : @js.Any = @js.parse(patches_json)
  let len : Int = patches_arr.get("length").cast()
  let ids : @js.Any = @js.array()
  for i in 0..<len {
    let patch = patches_arr.at(i)
    let tag : String = patch.get("$tag").to_str()
    let args = patch.get("_0")
    match tag {
      "MakeElement" => {
        let parent_id : Int = args.at(0).cast()
        let node_id : Int = args.at(1).cast()
        let tag_name : String = args.at(2).cast()
        let attrs : @js.Any = args.at(3)
        let el = create_element(tag_name)
        ignore(
          el.call("setAttribute", [
            @js.any("data-node-id"),
            @js.any(node_id.to_string()),
          ]),
        )
        apply_attrs(el, attrs)
        let parent = if parent_id == -1 {
          container
        } else {
          retrieve_element(parent_id)
        }
        ignore(parent.call("appendChild", [el]))
        stash_element(node_id, el)
        ignore(ids.call("push", [@js.any(node_id)]))
      }
      "MakeText" => {
        let parent_id : Int = args.at(0).cast()
        let node_id : Int = args.at(1).cast()
        let text : String = args.at(2).cast()
        let el = @js.global()
          .get("document")
          .call("createTextNode", [@js.any(text)])
        let parent = if parent_id == -1 {
          container
        } else {
          retrieve_element(parent_id)
        }
        ignore(parent.call("appendChild", [el]))
        stash_element(node_id, el)
        ignore(ids.call("push", [@js.any(node_id)]))
      }
      "MakeExprSpan" => {
        let parent_id : Int = args.at(0).cast()
        let node_id : Int = args.at(1).cast()
        let raw : String = args.at(2).cast()
        let el = create_element("span")
        el.set("textContent", @js.any("{" + raw + "}"))
        let parent = if parent_id == -1 {
          container
        } else {
          retrieve_element(parent_id)
        }
        ignore(parent.call("appendChild", [el]))
        stash_element(node_id, el)
        ignore(ids.call("push", [@js.any(node_id)]))
      }
      "SetText" => {
        let node_id : Int = args.at(0).cast()
        let text : String = args.at(1).cast()
        retrieve_element(node_id).set("textContent", @js.any(text))
        ignore(ids.call("push", [@js.any(node_id)]))
      }
      "SetExpr" => {
        let node_id : Int = args.at(0).cast()
        let raw : String = args.at(1).cast()
        retrieve_element(node_id).set("textContent", @js.any("{" + raw + "}"))
        ignore(ids.call("push", [@js.any(node_id)]))
      }
      "SetAttrs" => {
        let node_id : Int = args.at(0).cast()
        let attrs : @js.Any = args.at(1)
        apply_attrs(retrieve_element(node_id), attrs)
        ignore(ids.call("push", [@js.any(node_id)]))
      }
      "Release" => {
        let node_id : Int = args.at(0).cast()
        let el = retrieve_element(node_id)
        ignore(el.call("remove", []))
        forget_element(node_id)
      }
      _ => ()
    }
  }
  let joined : String = ids.call("join", [@js.any(",")]).cast()
  "[" + joined + "]"
}

// ── Element registry helpers ────────────────────────────────────────────

///|
fn stash_element(node_id : Int, el : @js.Any) -> Unit {
  let _ = element_registry.call("set", [@js.any(node_id), el])
}

///|
fn retrieve_element(node_id : Int) -> @js.Any {
  element_registry.call("get", [@js.any(node_id)])
}

///|
fn forget_element(node_id : Int) -> Unit {
  let _ = element_registry.call("delete", [@js.any(node_id)])
}

// ── Helpers ─────────────────────────────────────────────────────────────

///|
fn create_element(tag : String) -> @js.Any {
  @js.global().get("document").call("createElement", [@js.any(tag)])
}

///|
fn apply_attrs(el : @js.Any, attrs : @js.Any) -> Unit {
  let len : Int = attrs.get("length").cast()
  for i in 0..<len {
    let attr = attrs.at(i)
    let name : String = attr.get("name").cast()
    let v = attr.get("value")
    if !v.is_nullish() && v.type_of() == "string" {
      let val : String = v.cast()
      ignore(el.call("setAttribute", [@js.any(name), @js.any(val)]))
    }
  }
}
