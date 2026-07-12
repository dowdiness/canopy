///| Whitebox tests for the V1 JSX FFI session contract.

///|
extern "js" fn install_session_test_document() -> Unit =
  #|() => {
  #|  const makeNode = (tag, text = "") => {
  #|    const node = {
  #|      tag,
  #|      textContent: text,
  #|      children: [],
  #|      get childNodes() { return this.children; },
  #|      parent: null,
  #|      attrs: {},
  #|      setAttribute(name, value) { this.attrs[name] = String(value); },
  #|      appendChild(child) {
  #|        if (globalThis.__canopySessionFailAppend) throw new Error("append failed");
  #|        if (child.parent) child.remove();
  #|        child.parent = this;
  #|        this.children.push(child);
  #|        return child;
  #|      },
  #|      insertBefore(child, reference) {
  #|        if (globalThis.__canopySessionFailAppend) throw new Error("append failed");
  #|        if (child.parent) child.remove();
  #|        const i = this.children.indexOf(reference);
  #|        child.parent = this;
  #|        if (i < 0) this.children.push(child); else this.children.splice(i, 0, child);
  #|        return child;
  #|      },
  #|      remove() {
  #|        if (!this.parent) return;
  #|        const i = this.parent.children.indexOf(this);
  #|        if (i >= 0) this.parent.children.splice(i, 1);
  #|        this.parent = null;
  #|      },
  #|    };
  #|    return node;
  #|  };
  #|  const roots = {
  #|    "session-root-a": makeNode("root"),
  #|    "session-root-b": makeNode("root"),
  #|  };
  #|  globalThis.__canopySessionRoots = roots;
  #|  globalThis.__canopySessionFailAppend = false;
  #|  globalThis.document = {
  #|    getElementById(id) { return roots[id] || null; },
  #|    createElement(tag) { return makeNode(tag); },
  #|    createTextNode(text) { return makeNode("#text", text); },
  #|  };
  #|}

///|
extern "js" fn set_session_test_append_failure(value : Bool) -> Unit =
  #|(value) => { globalThis.__canopySessionFailAppend = value; }

///|
extern "js" fn session_test_root_child_count(root_id : String) -> Int =
  #|(rootId) => globalThis.__canopySessionRoots[rootId].children.length

///|
extern "js" fn session_test_first_nested_tag(root_id : String) -> String =
  #|(rootId) => globalThis.__canopySessionRoots[rootId].children[0]?.children[0]?.tag ?? ""

///|
extern "js" fn session_test_nested_texts(root_id : String) -> String =
  #|(rootId) => globalThis.__canopySessionRoots[rootId].children[0].children.map(child => child.children[0]?.textContent ?? child.textContent).join("|")

///|
fn session_test_handle(result : @js.Any) -> Int {
  let encoded : String = result.get("handle").cast()
  @string.parse_int(encoded) catch {
    _ => abort("session result must contain a decimal handle")
  }
}

///|
test "render result uses the versioned envelope and string mounted ids" {
  let result = render_result_json(
    true,
    7,
    [3, 21],
    ["recoverable JSX diagnostic"],
    None,
  )
  let json = @js.parse(result)
  assert_eq(json.get("schema_version").cast(), 1)
  assert_true(json.get("success").cast())
  assert_eq(json.get("revision").cast(), 7)
  let mounted = json.get("mounted_ids")
  assert_eq(mounted.at(0).to_str(), "3")
  assert_eq(mounted.at(1).to_str(), "21")
  assert_eq(
    json.get("diagnostics").at(0).to_str(),
    "recoverable JSX diagnostic",
  )
  assert_true(json.get("error").is_nullish())
}

///|
test "render result exposes structured errors" {
  let result = render_result_json(
    false,
    2,
    [5],
    [],
    Some(("DisposedSession", "session handle has been disposed")),
  )
  let json = @js.parse(result)
  assert_false(json.get("success").cast())
  assert_eq(json.get("revision").cast(), 2)
  assert_eq(json.get("mounted_ids").at(0).to_str(), "5")
  let error = json.get("error")
  assert_eq(error.get("code").to_str(), "DisposedSession")
  assert_eq(error.get("message").to_str(), "session handle has been disposed")
}

///|
test "failed initial DOM render does not publish a usable handle" {
  let result = jsx_session_new("<div>hello</div>", "missing-jsx-session-root")
  let json = @js.parse(result)
  assert_false(json.get("success").cast())
  assert_true(json.get("handle").is_nullish())
  let render = json.get("result")
  assert_false(render.get("success").cast())
  assert_eq(render.get("revision").cast(), 0)
  assert_eq(render.get("mounted_ids").get("length").cast(), 0)
}

///|
test "mount-boundary detection is structural, not NodeId-dependent" {
  let old_text = @jsx_ast.JsxNode::Text("visible")
  let new_text = @jsx_ast.JsxNode::Text("visible")
  let old_child = @canopy_core.ProjNode::ProjNode(old_text, 1, 8, 20, [])
  let new_child = @canopy_core.ProjNode::ProjNode(new_text, 1, 8, 200, [])
  let old = @canopy_core.ProjNode::ProjNode(
    @jsx_ast.JsxNode::Element(tag="", attrs=[], children=[old_text]),
    0,
    8,
    10,
    [old_child],
  )
  let new = @canopy_core.ProjNode::ProjNode(
    @jsx_ast.JsxNode::Element(tag="section", attrs=[], children=[new_text]),
    0,
    8,
    100,
    [new_child],
  )
  assert_true(has_mount_boundary_transition(old, new))
}

///|
test "live session commits revisions, preserves ids, and disposes idempotently" {
  install_session_test_document()
  let created = @js.parse(jsx_session_new("<div>one</div>", "session-root-a"))
  assert_true(created.get("success").cast())
  let handle = session_test_handle(created)
  let first = created.get("result")
  assert_eq(first.get("revision").cast(), 1)
  let first_id : String = first.get("mounted_ids").at(0).cast()
  assert_eq(session_test_root_child_count("session-root-a"), 1)

  let second = @js.parse(jsx_session_render(handle, "<div>two</div>"))
  assert_true(second.get("success").cast())
  assert_eq(second.get("revision").cast(), 2)
  assert_eq(second.get("mounted_ids").at(0).cast(), first_id)

  jsx_session_dispose(handle)
  jsx_session_dispose(handle)
  assert_eq(session_test_root_child_count("session-root-a"), 0)
  let disposed = @js.parse(jsx_session_render(handle, "<div>three</div>"))
  assert_false(disposed.get("success").cast())
  assert_eq(disposed.get("error").get("code").to_str(), "DisposedSession")
}

///|
test "live sessions isolate DOM ownership" {
  install_session_test_document()
  let a = @js.parse(jsx_session_new("<div>a</div>", "session-root-a"))
  let b = @js.parse(jsx_session_new("<div>b</div>", "session-root-b"))
  let handle_a = session_test_handle(a)
  let handle_b = session_test_handle(b)
  assert_eq(session_test_root_child_count("session-root-a"), 1)
  assert_eq(session_test_root_child_count("session-root-b"), 1)
  jsx_session_dispose(handle_a)
  assert_eq(session_test_root_child_count("session-root-a"), 0)
  assert_eq(session_test_root_child_count("session-root-b"), 1)
  let b_update = @js.parse(jsx_session_render(handle_b, "<div>bb</div>"))
  assert_true(b_update.get("success").cast())
  jsx_session_dispose(handle_b)
}

///|
test "changed element tags remount descendants across the parent boundary" {
  install_session_test_document()
  let created = @js.parse(
    jsx_session_new("<di><span>x</span></di>", "session-root-a"),
  )
  let handle = session_test_handle(created)
  let updated = @js.parse(
    jsx_session_render(handle, "<div><span>x</span></div>"),
  )
  assert_true(updated.get("success").cast())
  assert_eq(session_test_first_nested_tag("session-root-a"), "span")
  jsx_session_dispose(handle)
}

///|
test "DOM adapter honors sibling indexes for inserted children" {
  install_session_test_document()
  let created = @js.parse(
    jsx_session_new("<div><span>a</span><span>b</span></div>", "session-root-a"),
  )
  let handle = session_test_handle(created)
  let updated = @js.parse(
    jsx_session_render(
      handle, "<div><span>x</span><span>a</span><span>b</span></div>",
    ),
  )
  assert_true(updated.get("success").cast())
  assert_eq(session_test_nested_texts("session-root-a"), "x|a|b")
  jsx_session_dispose(handle)
}

///|
test "DOM failure keeps the committed revision and next success repairs dirty state" {
  install_session_test_document()
  let created = @js.parse(jsx_session_new("<div>one</div>", "session-root-a"))
  let handle = session_test_handle(created)
  let committed_id : String = created
    .get("result")
    .get("mounted_ids")
    .at(0)
    .cast()
  set_session_test_append_failure(true)
  let failed = @js.parse(jsx_session_render(handle, "<div><p>two</p></div>"))
  assert_false(failed.get("success").cast())
  assert_eq(failed.get("revision").cast(), 1)
  assert_eq(failed.get("mounted_ids").at(0).cast(), committed_id)
  assert_eq(failed.get("error").get("code").to_str(), "DomApplyError")

  set_session_test_append_failure(false)
  let repaired = @js.parse(jsx_session_render(handle, "<div><p>two</p></div>"))
  assert_true(repaired.get("success").cast())
  assert_eq(repaired.get("revision").cast(), 2)
  assert_eq(session_test_root_child_count("session-root-a"), 1)
  jsx_session_dispose(handle)
}
