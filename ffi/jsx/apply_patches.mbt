///| Apply DomPatch[] to real DOM elements via js_ffi Any.
///| reconcile() produces pure patches; this turns them into DOM operations.
///
///| `container_json` — JSON string of the container DOM element (from JS).
///| `patches_json`   — JSON string of DomPatch[] from reconcile().
///| Returns a JSON string of remaining known NodeIds (for next reconcile call).

pub fn apply_patches(container_json : String, patches_json : String) -> String {
  let container = @js.parse(container_json)
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
        ignore(el.call("setAttribute", [@js.any("data-node-id"), @js.any(node_id.to_string())]))
        apply_attrs(el, attrs)
        let parent = find_or_get_container(container, parent_id)
        ignore(parent.call("appendChild", [el]))
        ignore(ids.call("push", [@js.any(node_id)]))
        stash_element(node_id, el)
      }
      "MakeText" => {
        let parent_id : Int = args.at(0).cast()
        let node_id : Int = args.at(1).cast()
        let text : String = args.at(2).cast()
        let el = @js.global().get("document").call("createTextNode", [@js.any(text)])
        let parent = find_or_get_container(container, parent_id)
        ignore(parent.call("appendChild", [el]))
        stash_element(node_id, el)
      }
      "MakeExprSpan" => {
        let parent_id : Int = args.at(0).cast()
        let node_id : Int = args.at(1).cast()
        let raw : String = args.at(2).cast()
        let el = create_element("span")
        el.set("textContent", @js.any("{" + raw + "}"))
        let parent = find_or_get_container(container, parent_id)
        ignore(parent.call("appendChild", [el]))
        stash_element(node_id, el)
      }
      "SetText" => {
        let node_id : Int = args.at(0).cast()
        let text : String = args.at(1).cast()
        let el = retrieve_element(node_id)
        el.set("textContent", @js.any(text))
      }
      "SetExpr" => {
        let node_id : Int = args.at(0).cast()
        let raw : String = args.at(1).cast()
        let el = retrieve_element(node_id)
        el.set("textContent", @js.any("{" + raw + "}"))
      }
      "SetAttrs" => {
        let node_id : Int = args.at(0).cast()
        let attrs : @js.Any = args.at(1)
        let el = retrieve_element(node_id)
        apply_attrs(el, attrs)
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

// ── Element registry under globalThis.__jsx_elements ──────────────────

fn registry() -> @js.Any {
  let g = @js.global()
  let reg = g.get("__jsx_elements")
  if reg.is_nullish() {
    let m = @js.global().get("Map").construct([])
    g.set("__jsx_elements", m)
    m
  } else {
    reg
  }
}

fn stash_element(node_id : Int, el : @js.Any) -> Unit {
  let _ = registry().call("set", [@js.any(node_id), el])
}

fn retrieve_element(node_id : Int) -> @js.Any {
  registry().call("get", [@js.any(node_id)])
}

fn forget_element(node_id : Int) -> Unit {
  let _ = registry().call("delete", [@js.any(node_id)])
}

// ── Helpers ───────────────────────────────────────────────────────────

fn create_element(tag : String) -> @js.Any {
  @js.global().get("document").call("createElement", [@js.any(tag)])
}

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

fn find_or_get_container(container : @js.Any, parent_id : Int) -> @js.Any {
  if parent_id == -1 { container }
  else { retrieve_element(parent_id) }
}
