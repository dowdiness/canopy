///| Whitebox tests for the V1 JSX FFI session contract.

///|
extern "js" fn install_session_test_document() -> Unit =
  #|() => {
  #|  const state = { failAppend: false };
  #|  const makeNode = (tag, text = "") => {
  #|    const node = {
  #|      tag,
  #|      textContent: text,
  #|      children: [],
  #|      get childNodes() { return this.children; },
  #|      parent: null,
  #|      attrs: {},
  #|      setAttribute(name, value) { this.attrs[name] = String(value); },
  #|      getAttributeNames() { return Object.keys(this.attrs); },
  #|      removeAttribute(name) { delete this.attrs[name]; },
  #|      appendChild(child) {
  #|        if (state.failAppend) throw new Error("append failed");
  #|        if (child.parent) child.remove();
  #|        child.parent = this;
  #|        this.children.push(child);
  #|        return child;
  #|      },
  #|      insertBefore(child, reference) {
  #|        if (state.failAppend) throw new Error("append failed");
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
  #|  const testDocument = {
  #|    getElementById(id) { return roots[id] || null; },
  #|    createElement(tag) { return makeNode(tag); },
  #|    createTextNode(text) { return makeNode("#text", text); },
  #|  };
  #|  testDocument.__canopySessionState = state;
  #|  globalThis.document = testDocument;
  #|}

///|
extern "js" fn set_session_test_append_failure(value : Bool) -> Unit =
  #|(value) => { document.__canopySessionState.failAppend = value; }

///|
extern "js" fn session_test_root_child_count(root_id : String) -> Int =
  #|(rootId) => document.getElementById(rootId).children.length

///|
extern "js" fn session_test_first_nested_tag(root_id : String) -> String =
  #|(rootId) => document.getElementById(rootId).children[0]?.children[0]?.tag ?? ""

///|
extern "js" fn session_test_child_tag(root_id : String, index : Int) -> String =
  #|(rootId, i) => document.getElementById(rootId).children[0]?.children[i]?.tag ?? ""

///|
extern "js" fn session_test_root_attribute(
  root_id : String,
  name : String,
) -> String =
  #|(rootId, name) => document.getElementById(rootId).children[0]?.attrs[name] ?? ""

///|
extern "js" fn session_test_has_root_attribute(
  root_id : String,
  name : String,
) -> Bool =
  #|(rootId, name) => Object.prototype.hasOwnProperty.call(document.getElementById(rootId).children[0]?.attrs ?? {}, name)

///|
extern "js" fn session_test_nested_texts(root_id : String) -> String =
  #|(rootId) => document.getElementById(rootId).children[0].children.map(child => child.children[0]?.textContent ?? child.textContent).join("|")

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
test "live session publishes the complete mounted ID baseline" {
  install_session_test_document()
  let created = @js.parse(
    jsx_session_new("<div><span>one</span><i>two</i></div>", "session-root-a"),
  )
  let handle = session_test_handle(created)
  assert_eq(created.get("result").get("mounted_ids").get("length").cast(), 5)

  let second = @js.parse(
    jsx_session_render(handle, "<div><span>ONE</span><i>two</i></div>"),
  )
  assert_true(second.get("success").cast())
  assert_eq(second.get("mounted_ids").get("length").cast(), 5)

  let third = @js.parse(
    jsx_session_render(handle, "<div><span>ONE</span><i>TWO</i></div>"),
  )
  assert_true(third.get("success").cast())
  assert_eq(third.get("mounted_ids").get("length").cast(), 5)
  jsx_session_dispose(handle)
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
test "DOM adapter releases removed siblings before inserting replacements" {
  install_session_test_document()
  let created = @js.parse(
    jsx_session_new(
      "<div><span>a</span><span>b</span><span>c</span></div>", "session-root-a",
    ),
  )
  let handle = session_test_handle(created)
  let updated = @js.parse(
    jsx_session_render(handle, "<div><span>b</span><span>c</span>{e}</div>"),
  )
  assert_true(updated.get("success").cast())
  assert_eq(session_test_nested_texts("session-root-a"), "b|c|{e}")
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

///|
fn session_test_candidate() -> @cognition.GenerativeUiCandidate {
  let capabilities = @cognition.GenerativeUiHostCapabilities::GenerativeUiHostCapabilities(
    bindings=[
      @cognition.GenerativeUiBindingCapabilities::GenerativeUiBindingCapabilities(
        name="orders",
        fields=["name", "amount"],
        selection_keys=["id"],
      ),
    ],
    filter_operators=[@cognition.GenerativeUiFilterOperator::Contains],
    aggregations=[@cognition.GenerativeUiAggregation::Count],
  )
  let raw = @cognition.GenerativeUiRawNode::Component(
    name="stack",
    attributes=[],
    children=[
      @cognition.GenerativeUiRawNode::Component(
        name="text",
        attributes=[
          @cognition.GenerativeUiRawAttribute::GenerativeUiRawAttribute(
            name="value",
            value="Orders",
          ),
        ],
        children=[],
      ),
      @cognition.GenerativeUiRawNode::Component(
        name="table",
        attributes=[
          @cognition.GenerativeUiRawAttribute::GenerativeUiRawAttribute(
            name="data",
            value="orders",
          ),
          @cognition.GenerativeUiRawAttribute::GenerativeUiRawAttribute(
            name="selection",
            value="id",
          ),
        ],
        children=[
          @cognition.GenerativeUiRawNode::Component(
            name="column",
            attributes=[
              @cognition.GenerativeUiRawAttribute::GenerativeUiRawAttribute(
                name="field",
                value="name",
              ),
              @cognition.GenerativeUiRawAttribute::GenerativeUiRawAttribute(
                name="label",
                value="Name",
              ),
            ],
            children=[],
          ),
          @cognition.GenerativeUiRawNode::Component(
            name="filter",
            attributes=[
              @cognition.GenerativeUiRawAttribute::GenerativeUiRawAttribute(
                name="field",
                value="name",
              ),
              @cognition.GenerativeUiRawAttribute::GenerativeUiRawAttribute(
                name="operator",
                value="contains",
              ),
            ],
            children=[],
          ),
          @cognition.GenerativeUiRawNode::Component(
            name="summary",
            attributes=[
              @cognition.GenerativeUiRawAttribute::GenerativeUiRawAttribute(
                name="field",
                value="amount",
              ),
              @cognition.GenerativeUiRawAttribute::GenerativeUiRawAttribute(
                name="aggregation",
                value="count",
              ),
            ],
            children=[],
          ),
        ],
      ),
    ],
  )
  match @cognition.GenerativeUiCandidate::validate(raw~, capabilities~) {
    Ok(candidate) => candidate
    Err(_) => abort("candidate fixture must validate")
  }
}

///|
test "candidate lowering keeps host metadata declarative and non-duplicated" {
  let source = lower_generative_ui_candidate(session_test_candidate()).unwrap()
  assert_eq(
    source, "<div data-genui-kind=\"stack\">Orders<div data-genui-kind=\"table\" data-genui-binding=\"orders\" data-genui-selection=\"id\"><div data-genui-kind=\"column\" data-genui-field=\"name\" data-genui-label=\"Name\"></div><div data-genui-kind=\"filter\" data-genui-field=\"name\" data-genui-operator=\"contains\"></div><div data-genui-kind=\"summary\" data-genui-field=\"amount\" data-genui-aggregation=\"count\"></div></div></div>",
  )
}

///|
test "validated candidate commits only after the session dry run" {
  install_session_test_document()
  let created = @js.parse(
    jsx_session_new("<div>initial</div>", "session-root-a"),
  )
  let handle = session_test_handle(created)
  let result = @js.parse(
    jsx_session_commit_candidate(
      handle,
      @cognition.GenerativeUiRevision::GenerativeUiRevision(1),
      session_test_candidate(),
    ),
  )
  assert_true(result.get("success").cast())
  assert_eq(result.get("revision").cast(), 2)
  assert_eq(session_test_child_tag("session-root-a", 1), "div")
  assert_eq(session_test_root_child_count("session-root-a"), 1)
  jsx_session_dispose(handle)
}

///|
test "candidate base revision is checked before parser or DOM work" {
  install_session_test_document()
  let created = @js.parse(
    jsx_session_new("<div>initial</div>", "session-root-a"),
  )
  let handle = session_test_handle(created)
  let stale = @js.parse(
    jsx_session_commit_candidate(
      handle,
      @cognition.GenerativeUiRevision::GenerativeUiRevision(0),
      session_test_candidate(),
    ),
  )
  assert_false(stale.get("success").cast())
  assert_eq(stale.get("revision").cast(), 1)
  assert_eq(stale.get("error").get("code").to_str(), "BaseRevisionMismatch")
  assert_eq(session_test_nested_texts("session-root-a"), "initial")
  jsx_session_dispose(handle)
}

///|
test "candidate lowering rejects JSX syntax in text before commit" {
  let capabilities = @cognition.GenerativeUiHostCapabilities::GenerativeUiHostCapabilities(
    bindings=[],
    filter_operators=[],
    aggregations=[],
  )
  let raw = @cognition.GenerativeUiRawNode::Component(
    name="text",
    attributes=[
      @cognition.GenerativeUiRawAttribute::GenerativeUiRawAttribute(
        name="value",
        value="unsafe <tag>",
      ),
    ],
    children=[],
  )
  let candidate = match
    @cognition.GenerativeUiCandidate::validate(raw~, capabilities~) {
    Ok(value) => value
    Err(_) => fail("candidate fixture must validate")
  }
  match lower_generative_ui_candidate(candidate) {
    Ok(_) => fail("unsafe text unexpectedly lowered")
    Err(message) =>
      assert_eq(message, "candidate text contains JSX syntax characters")
  }
}

///|
test "DOM adapter decodes only generative UI metadata entities" {
  install_session_test_document()
  let created = @js.parse(
    jsx_session_new(
      "<div data-genui-label=\"a&amp;b &quot;c&quot;\" data-other=\"&amp;\"/>", "session-root-a",
    ),
  )
  let handle = session_test_handle(created)
  assert_true(created.get("success").cast())
  assert_eq(
    session_test_root_attribute("session-root-a", "data-genui-label"),
    "a&b \"c\"",
  )
  assert_eq(
    session_test_root_attribute("session-root-a", "data-other"),
    "&amp;",
  )
  jsx_session_dispose(handle)
}

///|
test "DOM adapter removes attributes absent from SetAttrs" {
  install_session_test_document()
  let created = @js.parse(
    jsx_session_new(
      "<div data-genui-label=\"old\" data-other=\"keep\"/>", "session-root-a",
    ),
  )
  let handle = session_test_handle(created)
  let updated = @js.parse(
    jsx_session_render(handle, "<div data-genui-label=\"new\"/>"),
  )
  assert_true(updated.get("success").cast())
  assert_eq(
    session_test_root_attribute("session-root-a", "data-genui-label"),
    "new",
  )
  assert_false(session_test_has_root_attribute("session-root-a", "data-other"))
  assert_true(
    session_test_root_attribute("session-root-a", "data-node-id").length() > 0,
  )
  assert_true(session_test_has_root_attribute("session-root-a", "data-node-id"))
  jsx_session_dispose(handle)
}

///|
test "DOM adapter reserves the renderer node identity attribute" {
  install_session_test_document()
  let created = @js.parse(
    jsx_session_new("<div data-node-id=\"spoof\"/>", "session-root-a"),
  )
  let handle = session_test_handle(created)
  assert_true(created.get("success").cast())
  let initial_id = session_test_root_attribute("session-root-a", "data-node-id")
  assert_true(initial_id != "spoof")

  let updated = @js.parse(
    jsx_session_render(handle, "<div data-node-id=\"spoof-again\"/>"),
  )
  assert_true(updated.get("success").cast())
  assert_true(
    session_test_root_attribute("session-root-a", "data-node-id") !=
    "spoof-again",
  )
  jsx_session_dispose(handle)
}

///|
test "DOM adapter uses the last applicable duplicate attribute" {
  install_session_test_document()
  let created = @js.parse(
    jsx_session_new(
      "<div data-genui-label=\"first\" data-genui-label=\"second\"/>", "session-root-a",
    ),
  )
  let handle = session_test_handle(created)
  assert_true(created.get("success").cast())
  assert_eq(
    session_test_root_attribute("session-root-a", "data-genui-label"),
    "second",
  )
  jsx_session_dispose(handle)
}

///|
test "DOM adapter normalizes bare and opaque expression attributes" {
  install_session_test_document()
  let created = @js.parse(
    jsx_session_new("<div data-genui-label=\"old\"/>", "session-root-a"),
  )
  let handle = session_test_handle(created)
  let expression = @js.parse(
    jsx_session_render(handle, "<div data-genui-label={value}/>"),
  )
  assert_true(expression.get("success").cast())
  assert_false(
    session_test_has_root_attribute("session-root-a", "data-genui-label"),
  )

  let bare = @js.parse(jsx_session_render(handle, "<div hidden/>"))
  assert_true(bare.get("success").cast())
  assert_true(session_test_has_root_attribute("session-root-a", "hidden"))
  assert_eq(session_test_root_attribute("session-root-a", "hidden"), "")
  assert_false(
    session_test_has_root_attribute("session-root-a", "data-genui-label"),
  )
  jsx_session_dispose(handle)
}

///|
test "dry-run failure leaves the candidate uncommitted and repairs next time" {
  install_session_test_document()
  let created = @js.parse(
    jsx_session_new("<div>initial</div>", "session-root-a"),
  )
  let handle = session_test_handle(created)
  let session = session_registry.get(handle).unwrap()
  // Simulate an internal model divergence without touching the real DOM.
  session.dry_run_model = @jsx_proj.DryRunModel::empty()

  let failed = @js.parse(jsx_session_render(handle, "<div>two</div>"))
  assert_false(failed.get("success").cast())
  assert_eq(failed.get("revision").cast(), 1)
  assert_eq(failed.get("error").get("code").to_str(), "DryRunError")
  assert_eq(session_test_nested_texts("session-root-a"), "initial")

  let repaired = @js.parse(jsx_session_render(handle, "<div>two</div>"))
  assert_true(repaired.get("success").cast())
  assert_eq(repaired.get("revision").cast(), 2)
  assert_eq(session_test_nested_texts("session-root-a"), "two")
  jsx_session_dispose(handle)
}
