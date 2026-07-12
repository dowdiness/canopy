///| Apply DomPatch[] to real DOM elements via js_ffi Any.

///|
/// A legacy container/registry kept only for the compatibility API.
let legacy_container_id : String = "html-preview"

///|
/// JavaScript exceptions are not represented as MoonBit `raise` effects by
/// `Any::call`. Catch them at the JavaScript boundary so a DOM failure can
/// become the session's structured `DomApplyError` and dirty-state path.
extern "js" fn catch_js(callback : @js.Any) -> @js.Any =
  #|(callback) => {
  #|  try {
  #|    return { ok: true, value: callback() };
  #|  } catch (error) {
  #|    return { ok: false, error: String(error) };
  #|  }
  #|}

///|
/// Create a registry owned by one session. Session registries must never be
/// shared, even when two sessions happen to allocate equal internal NodeIds.
fn new_element_registry() -> @js.Any {
  let map = @js.global().get("Map")
  map.construct([])
}

///|
/// Compatibility registry for the old one-cycle API.
let legacy_element_registry : @js.Any = new_element_registry()

///|
fn clear_element_registry(registry : @js.Any) -> Unit {
  ignore(
    registry.call("forEach", [
      @js.fn2(fn(el : @js.Any, _key : @js.Any) {
        if !el.is_nullish() {
          ignore(el.call("remove", []))
        }
      }),
    ]),
  )
  let _ = registry.call("clear", [])
}

///|
/// Clear the legacy compatibility registry.
pub fn clear_registry() -> Unit {
  clear_element_registry(legacy_element_registry)
}

///|
/// Clear every node owned by one session. The caller must drop the registry
/// after this call; the DOM nodes are removed before the JS Map is cleared.
fn clear_session_registry(registry : @js.Any) -> Unit {
  clear_element_registry(registry)
}

///|
/// Apply patches to a specific root and registry. All DOM state used by this
/// function is supplied by the caller, so separate sessions cannot retrieve or
/// release each other's nodes.
fn apply_patches_with_registry(
  patches_json : String,
  root_id : String,
  registry : @js.Any,
) -> Result[Array[Int], String] {
  let outcome = catch_js(
    @js.fn0(fn() {
      @js.any(apply_patches_unchecked(patches_json, root_id, registry))
    }),
  )
  if !outcome.get("ok").cast() {
    Err(outcome.get("error").to_str())
  } else {
    outcome.get("value").cast()
  }
}

///|
fn apply_patches_unchecked(
  patches_json : String,
  root_id : String,
  registry : @js.Any,
) -> Result[Array[Int], String] {
  let document = @js.global().get("document")
  if document.is_nullish() {
    return Err("document is unavailable")
  }
  let container = document.call("getElementById", [@js.any(root_id)])
  if container.is_nullish() {
    return Err("root container is unavailable: " + root_id)
  }
  let patches_arr : @js.Any = @js.parse(patches_json)
  let len : Int = patches_arr.get("length").cast()
  let ids : Array[Int] = []
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
        let index : Int = args.at(4).cast()
        let el = create_element(tag_name)
        // Stash before the first potentially-throwing DOM call. This makes a
        // partial application cleanable by the session's disposal path.
        stash_element(registry, node_id, el)
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
          retrieve_element(registry, parent_id)
        }
        if parent.is_nullish() {
          return Err("missing parent node: " + parent_id.to_string())
        }
        insert_child(parent, el, index)
        ids.push(node_id)
      }
      "MakeText" => {
        let parent_id : Int = args.at(0).cast()
        let node_id : Int = args.at(1).cast()
        let text : String = args.at(2).cast()
        let index : Int = args.at(3).cast()
        let el = document.call("createTextNode", [@js.any(text)])
        stash_element(registry, node_id, el)
        let parent = if parent_id == -1 {
          container
        } else {
          retrieve_element(registry, parent_id)
        }
        if parent.is_nullish() {
          return Err("missing parent node: " + parent_id.to_string())
        }
        insert_child(parent, el, index)
        ids.push(node_id)
      }
      "MakeExprSpan" => {
        let parent_id : Int = args.at(0).cast()
        let node_id : Int = args.at(1).cast()
        let raw : String = args.at(2).cast()
        let index : Int = args.at(3).cast()
        let el = create_element("span")
        stash_element(registry, node_id, el)
        el.set("textContent", @js.any("{" + raw + "}"))
        let parent = if parent_id == -1 {
          container
        } else {
          retrieve_element(registry, parent_id)
        }
        if parent.is_nullish() {
          return Err("missing parent node: " + parent_id.to_string())
        }
        insert_child(parent, el, index)
        ids.push(node_id)
      }
      "SetText" => {
        let node_id : Int = args.at(0).cast()
        let text : String = args.at(1).cast()
        let el = retrieve_element(registry, node_id)
        if el.is_nullish() {
          return Err("missing node: " + node_id.to_string())
        }
        el.set("textContent", @js.any(text))
        ids.push(node_id)
      }
      "SetExpr" => {
        let node_id : Int = args.at(0).cast()
        let raw : String = args.at(1).cast()
        let el = retrieve_element(registry, node_id)
        if el.is_nullish() {
          return Err("missing node: " + node_id.to_string())
        }
        el.set("textContent", @js.any("{" + raw + "}"))
        ids.push(node_id)
      }
      "SetAttrs" => {
        let node_id : Int = args.at(0).cast()
        let attrs : @js.Any = args.at(1)
        let el = retrieve_element(registry, node_id)
        if el.is_nullish() {
          return Err("missing node: " + node_id.to_string())
        }
        apply_attrs(el, attrs)
        ids.push(node_id)
      }
      "Release" => {
        let node_id : Int = args.at(0).cast()
        let el = retrieve_element(registry, node_id)
        if !el.is_nullish() {
          ignore(el.call("remove", []))
          forget_element(registry, node_id)
        }
      }
      _ => ()
    }
  }
  Ok(ids)
}

///|
/// Apply patches using the legacy compatibility registry.
pub fn apply_patches(patches_json : String) -> String {
  match
    apply_patches_with_registry(
      patches_json, legacy_container_id, legacy_element_registry,
    ) {
    Ok(ids) => array_ids_to_json(ids)
    Err(_) => "[]"
  }
}

// ── Element registry helpers ────────────────────────────────────────────

///|
fn array_ids_to_json(ids : Array[Int]) -> String {
  Json::array(ids.map(id => Json::number(id.to_double()))).stringify()
}

///|
fn stash_element(registry : @js.Any, node_id : Int, el : @js.Any) -> Unit {
  let _ = registry.call("set", [@js.any(node_id), el])
}

///|
fn retrieve_element(registry : @js.Any, node_id : Int) -> @js.Any {
  registry.call("get", [@js.any(node_id)])
}

///|
fn forget_element(registry : @js.Any, node_id : Int) -> Unit {
  let _ = registry.call("delete", [@js.any(node_id)])
}

///|
/// Respect the projected sibling index. `childNodes` is used instead of
/// `children` because text nodes and expression spans are mounted too.
fn insert_child(parent : @js.Any, child : @js.Any, index : Int) -> Unit {
  let child_nodes = parent.get("childNodes")
  let len : Int = child_nodes.get("length").cast()
  if index < len {
    ignore(parent.call("insertBefore", [child, child_nodes.at(index)]))
  } else {
    ignore(parent.call("appendChild", [child]))
  }
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
