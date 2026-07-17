///| Whitebox tests for the V1 JSX FFI session contract.

///|
extern "js" fn install_session_test_document() -> Unit =
  #|() => {
  #|  const state = { failAppend: false, nextNodeId: 1 };
  #|  const makeNode = (tag, text = "") => {
  #|    const node = {
  #|      tag,
  #|      textContent: text,
  #|      testId: state.nextNodeId++,
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
extern "js" fn session_test_has_own_key(value : @js.Any, key : String) -> Bool =
  #|(value, key) => Object.prototype.hasOwnProperty.call(value, key)

///|
extern "js" fn session_test_root_child_count(root_id : String) -> Int =
  #|(rootId) => document.getElementById(rootId).children.length

///|
extern "js" fn session_test_root_child_identity(root_id : String) -> Int =
  #|(rootId) => document.getElementById(rootId).children[0]?.testId ?? 0

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
extern "js" fn session_test_nested_attribute(
  root_id : String,
  index : Int,
  name : String,
) -> String =
  #|(rootId, index, name) => document.getElementById(rootId).children[0]?.children[index]?.attrs[name] ?? ""

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
  assert_true(session_test_has_own_key(json, "error"))
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
fn session_test_text_candidate(
  values : Array[String],
) -> @cognition.GenerativeUiCandidate {
  let capabilities = @cognition.GenerativeUiHostCapabilities::GenerativeUiHostCapabilities(
    bindings=[],
    filter_operators=[],
    aggregations=[],
  )
  let raw = @cognition.GenerativeUiRawNode::Component(
    name="stack",
    attributes=[],
    children=values.map(value => {
      @cognition.GenerativeUiRawNode::Component(
        name="text",
        attributes=[
          @cognition.GenerativeUiRawAttribute::GenerativeUiRawAttribute(
            name="value",
            value~,
          ),
        ],
        children=[],
      )
    }),
  )
  match @cognition.GenerativeUiCandidate::validate(raw~, capabilities~) {
    Ok(candidate) => candidate
    Err(_) => abort("text candidate fixture must validate")
  }
}

///|
fn session_test_validating_lifecycle(
  base_revision : @cognition.GenerativeUiRevision,
) -> (@cognition.GenerativeUiLifecycle, @cognition.GenerativeUiGenerationId) {
  let lifecycle = @cognition.GenerativeUiLifecycle::GenerativeUiLifecycle()
  let generation_id = match
    lifecycle.dispatch(@cognition.GenerativeUiEvent::Start(base_revision~)) {
    @cognition.GenerativeUiTransition::Started(generation_id~) => generation_id
    _ => abort("lifecycle fixture must start")
  }
  let finalized = lifecycle.dispatch(
    @cognition.GenerativeUiEvent::Input(
      @cognition.GenerativeUiInput::finalize(
        generation_id~,
        base_revision~,
        sequence=0,
      ),
    ),
  )
  guard finalized is @cognition.GenerativeUiTransition::Finalized else {
    abort("lifecycle fixture must finalize")
  }
  (lifecycle, generation_id)
}

///|
fn session_test_empty_capabilities_json() -> String {
  "{\"bindings\":[],\"filter_operators\":[],\"aggregations\":[]}"
}

///|
fn session_test_replay_result(
  handle : Int,
  base_revision : Int,
  candidate : String,
  capabilities : String,
) -> @js.Any {
  @js.parse(
    jsx_session_replay_candidate_json(
      handle, base_revision, candidate, capabilities,
    ),
  )
}

///|
fn session_test_expected_candidate_ast() -> @jsx_ast.JsxNode {
  @jsx_ast.JsxNode::Root(children=[
    @jsx_ast.JsxNode::Element(
      tag="div",
      attrs=[
        @jsx_ast.JsxAttr::JsxAttr(
          name="data-genui-kind",
          value=@jsx_ast.JsxAttrValue::StringLit("stack"),
        ),
      ],
      children=[
        @jsx_ast.JsxNode::Text("Orders"),
        @jsx_ast.JsxNode::Element(
          tag="div",
          attrs=[
            @jsx_ast.JsxAttr::JsxAttr(
              name="data-genui-kind",
              value=@jsx_ast.JsxAttrValue::StringLit("table"),
            ),
            @jsx_ast.JsxAttr::JsxAttr(
              name="data-genui-binding",
              value=@jsx_ast.JsxAttrValue::StringLit("orders"),
            ),
            @jsx_ast.JsxAttr::JsxAttr(
              name="data-genui-selection",
              value=@jsx_ast.JsxAttrValue::StringLit("id"),
            ),
          ],
          children=[
            @jsx_ast.JsxNode::Element(
              tag="div",
              attrs=[
                @jsx_ast.JsxAttr::JsxAttr(
                  name="data-genui-kind",
                  value=@jsx_ast.JsxAttrValue::StringLit("column"),
                ),
                @jsx_ast.JsxAttr::JsxAttr(
                  name="data-genui-field",
                  value=@jsx_ast.JsxAttrValue::StringLit("name"),
                ),
                @jsx_ast.JsxAttr::JsxAttr(
                  name="data-genui-label",
                  value=@jsx_ast.JsxAttrValue::StringLit("Name"),
                ),
              ],
              children=[],
            ),
            @jsx_ast.JsxNode::Element(
              tag="div",
              attrs=[
                @jsx_ast.JsxAttr::JsxAttr(
                  name="data-genui-kind",
                  value=@jsx_ast.JsxAttrValue::StringLit("filter"),
                ),
                @jsx_ast.JsxAttr::JsxAttr(
                  name="data-genui-field",
                  value=@jsx_ast.JsxAttrValue::StringLit("name"),
                ),
                @jsx_ast.JsxAttr::JsxAttr(
                  name="data-genui-operator",
                  value=@jsx_ast.JsxAttrValue::StringLit("contains"),
                ),
              ],
              children=[],
            ),
            @jsx_ast.JsxNode::Element(
              tag="div",
              attrs=[
                @jsx_ast.JsxAttr::JsxAttr(
                  name="data-genui-kind",
                  value=@jsx_ast.JsxAttrValue::StringLit("summary"),
                ),
                @jsx_ast.JsxAttr::JsxAttr(
                  name="data-genui-field",
                  value=@jsx_ast.JsxAttrValue::StringLit("amount"),
                ),
                @jsx_ast.JsxAttr::JsxAttr(
                  name="data-genui-aggregation",
                  value=@jsx_ast.JsxAttrValue::StringLit("count"),
                ),
              ],
              children=[],
            ),
          ],
        ),
      ],
    ),
  ])
}

///|
fn session_test_projection_is_paired(
  node : @canopy_core.ProjNode[@jsx_ast.JsxNode],
) -> Bool {
  match node.kind {
    @jsx_ast.JsxNode::Root(children~) =>
      children == node.children.map(child => child.kind) &&
      node.children.all(session_test_projection_is_paired)
    @jsx_ast.JsxNode::Element(children~, ..) =>
      children == node.children.map(child => child.kind) &&
      node.children.all(session_test_projection_is_paired)
    @jsx_ast.JsxNode::Fragment(children~) =>
      children == node.children.map(child => child.kind) &&
      node.children.all(session_test_projection_is_paired)
    @jsx_ast.JsxNode::Text(_)
    | @jsx_ast.JsxNode::ExprSpan(..)
    | @jsx_ast.JsxNode::Error(_) => node.children.is_empty()
  }
}

///|
test "candidate projection keeps host metadata declarative and non-duplicated" {
  let projection = candidate_to_projection(session_test_candidate())
  assert_true(projection_ids_are_valid(projection))
  assert_true(projection.kind == session_test_expected_candidate_ast())
  assert_true(session_test_projection_is_paired(projection))
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
  let session = session_registry.get(handle).unwrap()
  assert_eq(session.committed_source, "<div>initial</div>")
  assert_true(session.baseline.mounted_origin == Candidate)
  let candidate_root_identity = session_test_root_child_identity(
    "session-root-a",
  )

  let source = @js.parse(jsx_session_render(handle, "<div>source</div>"))
  assert_true(source.get("success").cast())
  assert_eq(source.get("revision").cast(), 3)
  assert_true(
    session_test_root_child_identity("session-root-a") !=
    candidate_root_identity,
  )
  assert_true(session.baseline.mounted_origin == Source)
  assert_eq(session.committed_source, "<div>source</div>")
  assert_eq(session_test_nested_texts("session-root-a"), "source")
  jsx_session_dispose(handle)
}

///|
test "candidate replacement preserves shifted sibling order" {
  install_session_test_document()
  let created = @js.parse(
    jsx_session_new("<div>initial</div>", "session-root-a"),
  )
  let handle = session_test_handle(created)
  let first = @js.parse(
    jsx_session_commit_candidate(
      handle,
      @cognition.GenerativeUiRevision::GenerativeUiRevision(1),
      session_test_text_candidate(["a", "b"]),
    ),
  )
  assert_true(first.get("success").cast())
  assert_eq(first.get("revision").cast(), 2)
  assert_eq(session_test_nested_texts("session-root-a"), "a|b")
  let first_root_identity = session_test_root_child_identity("session-root-a")

  let shifted = @js.parse(
    jsx_session_commit_candidate(
      handle,
      @cognition.GenerativeUiRevision::GenerativeUiRevision(2),
      session_test_text_candidate(["x", "a", "b"]),
    ),
  )
  assert_true(shifted.get("success").cast())
  assert_eq(shifted.get("revision").cast(), 3)
  assert_eq(shifted.get("mounted_ids").get("length").cast(), 4)
  assert_eq(session_test_nested_texts("session-root-a"), "x|a|b")
  assert_true(
    session_test_root_child_identity("session-root-a") != first_root_identity,
  )
  assert_eq(session_test_root_child_count("session-root-a"), 1)
  jsx_session_dispose(handle)
}

///|
test "candidate metadata reaches DOM with exact entity-like values" {
  install_session_test_document()
  let created = @js.parse(
    jsx_session_new("<div>initial</div>", "session-root-a"),
  )
  let handle = session_test_handle(created)
  let metadata = "&amp;lt; &amp;amp; \"quoted\" 雪"
  let capabilities = @cognition.GenerativeUiHostCapabilities::GenerativeUiHostCapabilities(
    bindings=[
      @cognition.GenerativeUiBindingCapabilities::GenerativeUiBindingCapabilities(
        name="orders",
        fields=["name"],
        selection_keys=[],
      ),
    ],
    filter_operators=[],
    aggregations=[],
  )
  let raw = @cognition.GenerativeUiRawNode::Component(
    name="table",
    attributes=[
      @cognition.GenerativeUiRawAttribute::GenerativeUiRawAttribute(
        name="data",
        value="orders",
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
            value=metadata,
          ),
        ],
        children=[],
      ),
    ],
  )
  let candidate = match
    @cognition.GenerativeUiCandidate::validate(raw~, capabilities~) {
    Ok(value) => value
    Err(_) => abort("metadata candidate fixture must validate")
  }
  let committed = @js.parse(
    jsx_session_commit_candidate(
      handle,
      @cognition.GenerativeUiRevision::GenerativeUiRevision(1),
      candidate,
    ),
  )
  assert_true(committed.get("success").cast())
  assert_eq(
    session_test_root_attribute("session-root-a", "data-genui-binding"),
    "orders",
  )
  assert_eq(
    session_test_nested_attribute("session-root-a", 0, "data-genui-label"),
    metadata,
  )
  jsx_session_dispose(handle)
}

///|
test "exhausted revision rejects source before parser or DOM work" {
  install_session_test_document()
  let created = @js.parse(
    jsx_session_new("<div>initial</div>", "session-root-a"),
  )
  let handle = session_test_handle(created)
  let session = session_registry.get(handle).unwrap()
  session.baseline = SessionBaseline(
    mounted_origin=Source,
    dirty=false,
    revision=MAX_SESSION_REVISION,
  )

  let rejected = @js.parse(jsx_session_render(handle, "<div>uncommitted</div>"))
  assert_false(rejected.get("success").cast())
  assert_eq(rejected.get("revision").cast(), MAX_SESSION_REVISION)
  assert_eq(rejected.get("error").get("code").to_str(), "RevisionExhausted")
  assert_eq(session.committed_source, "<div>initial</div>")
  assert_eq(session_test_nested_texts("session-root-a"), "initial")
  jsx_session_dispose(handle)
}

///|
test "source projection failure after candidate restores and recovers" {
  install_session_test_document()
  let created = @js.parse(
    jsx_session_new("<div>initial</div>", "session-root-a"),
  )
  let handle = session_test_handle(created)
  let candidate = @js.parse(
    jsx_session_commit_candidate(
      handle,
      @cognition.GenerativeUiRevision::GenerativeUiRevision(1),
      session_test_text_candidate(["candidate"]),
    ),
  )
  assert_true(candidate.get("success").cast())
  let candidate_root_identity = session_test_root_child_identity(
    "session-root-a",
  )
  let session = session_registry.get(handle).unwrap()
  let candidate_mounted_ids = session.mounted_ids.copy()

  let failed = @js.parse(
    render_jsx_session_with_projection_read(
      session,
      "<div>uncommitted</div>",
      true,
      projection_read_override=Failed,
    ),
  )
  assert_false(failed.get("success").cast())
  assert_eq(failed.get("revision").cast(), 2)
  assert_eq(failed.get("error").get("code").to_str(), "ProjectionError")
  assert_true(session.mounted_ids == candidate_mounted_ids)
  assert_true(session.baseline.mounted_origin == Candidate)
  assert_false(session.baseline.dirty)
  assert_eq(session.committed_source, "<div>initial</div>")
  assert_eq(session_test_nested_texts("session-root-a"), "candidate")
  assert_eq(
    session_test_root_child_identity("session-root-a"),
    candidate_root_identity,
  )
  match read_source_projection(session) {
    Available(projection) =>
      assert_true(projection_texts(projection) == ["initial"])
    _ => abort("restored source projection must be available")
  }

  let recovered = @js.parse(jsx_session_render(handle, "<div>recovered</div>"))
  assert_true(recovered.get("success").cast())
  assert_eq(recovered.get("revision").cast(), 3)
  assert_true(session.baseline.mounted_origin == Source)
  assert_false(session.baseline.dirty)
  assert_eq(session.committed_source, "<div>recovered</div>")
  assert_eq(session_test_nested_texts("session-root-a"), "recovered")
  assert_true(
    session_test_root_child_identity("session-root-a") !=
    candidate_root_identity,
  )
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
test "candidate projection preserves JSX syntax in text" {
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
  let projection = candidate_to_projection(candidate)
  assert_true(projection_texts(projection) == ["unsafe <tag>"])
  assert_true(projection_ids_are_valid(projection))
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

///|
test "replay candidate adapter validates and commits through the JSX session" {
  install_session_test_document()
  let created = @js.parse(
    jsx_session_new("<div>initial</div>", "session-root-a"),
  )
  let handle = session_test_handle(created)
  let candidate_prefix = "{\"type\":\"component\",\"name\":\"stack\",\"attributes\":[],\"children\":["
  let candidate_suffix = "{\"type\":\"component\",\"name\":\"text\",\"attributes\":[{\"name\":\"value\",\"value\":\"Orders\"}],\"children\":[]}]}"
  let capabilities = "{\"bindings\":[],\"filter_operators\":[],\"aggregations\":[]}"
  let result = @js.parse(
    jsx_session_replay_candidate_json(
      handle,
      1,
      candidate_prefix + "\u{0000}" + candidate_suffix,
      capabilities,
    ),
  )
  assert_true(result.get("success").cast())
  assert_eq(result.get("revision").cast(), 2)
  assert_eq(
    session_test_root_attribute("session-root-a", "data-genui-kind"),
    "stack",
  )
  jsx_session_dispose(handle)
}

///|
test "replay decode and validation errors keep precedence and payloads" {
  install_session_test_document()
  let created = @js.parse(
    jsx_session_new("<div>initial</div>", "session-root-a"),
  )
  let handle = session_test_handle(created)
  let committed_ids = created.get("result").get("mounted_ids")
  let invalid_capabilities = "{\"bindings\":\"nope\",\"filter_operators\":[],\"aggregations\":[]}"

  let malformed_candidate = session_test_replay_result(
    handle, 1, "{\"type\":\"component\",\"name\":\"stack\",\"attributes\":[],\"children\":[{\"type\":\"text\"}]}",
    invalid_capabilities,
  )
  assert_false(malformed_candidate.get("success").cast())
  assert_eq(
    malformed_candidate.get("error").get("code").to_str(),
    "CandidateDecodeError",
  )
  assert_eq(
    malformed_candidate.get("error").get("message").to_str(),
    "text node value is missing or invalid",
  )
  assert_eq(malformed_candidate.get("revision").cast(), 1)
  assert_eq(
    malformed_candidate.get("mounted_ids").stringify(),
    committed_ids.stringify(),
  )

  let invalid_capability_result = session_test_replay_result(
    handle, 1, "{\"type\":\"raw_html\",\"value\":\"<b>unsafe</b>\"}", invalid_capabilities,
  )
  assert_false(invalid_capability_result.get("success").cast())
  assert_eq(
    invalid_capability_result.get("error").get("code").to_str(),
    "CapabilityDecodeError",
  )
  assert_eq(
    invalid_capability_result.get("error").get("message").to_str(),
    "capability bindings are missing or invalid",
  )
  assert_eq(invalid_capability_result.get("revision").cast(), 1)
  assert_eq(
    invalid_capability_result.get("mounted_ids").stringify(),
    committed_ids.stringify(),
  )
  assert_eq(
    invalid_capability_result.get("diagnostics").get("length").cast(),
    0,
  )
  assert_eq(session_test_nested_texts("session-root-a"), "initial")
  jsx_session_dispose(handle)
}

///|
test "replay semantic validation rejects unsafe nodes before dry run" {
  install_session_test_document()
  let created = @js.parse(
    jsx_session_new("<div>initial</div>", "session-root-a"),
  )
  let handle = session_test_handle(created)
  let committed_ids = created.get("result").get("mounted_ids")
  let capabilities = session_test_empty_capabilities_json()
  let cases = [
    (
      "{\"type\":\"raw_html\",\"value\":\"<b>unsafe</b>\"}", "root: raw HTML is not allowed",
    ),
    (
      "{\"type\":\"expression\",\"value\":\"danger\"}", "root: expressions are not allowed",
    ),
    (
      "{\"type\":\"component\",\"name\":\"stack\",\"attributes\":[],\"children\":[{\"type\":\"component\",\"name\":\"table\",\"attributes\":[{\"name\":\"data\",\"value\":\"orders\"}],\"children\":[]}]}",
      "root.children[0]: data binding is not available",
    ),
  ]
  for item in cases {
    let (candidate, diagnostic) = item
    let result = session_test_replay_result(handle, 1, candidate, capabilities)
    assert_false(result.get("success").cast())
    assert_eq(
      result.get("error").get("code").to_str(),
      "CandidateValidationError",
    )
    assert_eq(result.get("error").get("message").to_str(), "candidate rejected")
    assert_eq(result.get("diagnostics").at(0).to_str(), diagnostic)
    assert_eq(result.get("revision").cast(), 1)
    assert_eq(result.get("mounted_ids").stringify(), committed_ids.stringify())
    assert_eq(session_test_nested_texts("session-root-a"), "initial")
  }
  jsx_session_dispose(handle)
}

///|
test "validated replay transaction accepts an opaque candidate without JSON decode" {
  install_session_test_document()
  let created = @js.parse(
    jsx_session_new("<div>initial</div>", "session-root-a"),
  )
  let handle = session_test_handle(created)
  let session = session_registry.get(handle).unwrap()
  let revision = @cognition.GenerativeUiRevision::GenerativeUiRevision(1)
  let (lifecycle, generation_id) = session_test_validating_lifecycle(revision)
  let result = @js.parse(
    commit_validated_candidate_transaction(
      session,
      handle,
      revision,
      lifecycle,
      generation_id,
      session_test_text_candidate(["safe"]),
    ),
  )
  assert_true(result.get("success").cast())
  assert_eq(result.get("revision").cast(), 2)
  assert_eq(session_test_nested_texts("session-root-a"), "safe")
  assert_true(lifecycle.phase() == @cognition.GenerativeUiPhase::Committed)
  assert_true(
    lifecycle.committed_revision() ==
    Some(@cognition.GenerativeUiRevision::GenerativeUiRevision(2)),
  )
  jsx_session_dispose(handle)
}

///|
test "validated replay transaction ignores corrupted prior dry-run state" {
  install_session_test_document()
  let created = @js.parse(
    jsx_session_new("<div>initial</div>", "session-root-a"),
  )
  let handle = session_test_handle(created)
  let session = session_registry.get(handle).unwrap()
  session.dry_run_model = @jsx_proj.DryRunModel::empty()
  let revision = @cognition.GenerativeUiRevision::GenerativeUiRevision(1)
  let (lifecycle, generation_id) = session_test_validating_lifecycle(revision)
  let result = @js.parse(
    commit_validated_candidate_transaction(
      session,
      handle,
      revision,
      lifecycle,
      generation_id,
      session_test_text_candidate(["candidate"]),
    ),
  )
  assert_true(result.get("success").cast())
  assert_eq(result.get("revision").cast(), 2)
  assert_eq(session_test_nested_texts("session-root-a"), "candidate")
  assert_true(
    result.get("mounted_ids").get("length").cast() ==
    session_registry.get(handle).unwrap().mounted_ids.length(),
  )
  assert_true(lifecycle.phase() == @cognition.GenerativeUiPhase::Committed)
  jsx_session_dispose(handle)
}

///|
test "validated replay transaction preserves stale fields" {
  install_session_test_document()
  let stale_created = @js.parse(
    jsx_session_new("<div>initial</div>", "session-root-a"),
  )
  let stale_handle = session_test_handle(stale_created)
  let stale_session = session_registry.get(stale_handle).unwrap()
  let committed_ids = stale_created.get("result").get("mounted_ids")
  let stale_revision = @cognition.GenerativeUiRevision::GenerativeUiRevision(0)
  let (stale_lifecycle, stale_generation_id) = session_test_validating_lifecycle(
    stale_revision,
  )
  let stale_result = @js.parse(
    commit_validated_candidate_transaction(
      stale_session,
      stale_handle,
      stale_revision,
      stale_lifecycle,
      stale_generation_id,
      session_test_text_candidate(["stale"]),
    ),
  )
  assert_false(stale_result.get("success").cast())
  assert_eq(stale_result.get("revision").cast(), 1)
  assert_eq(
    stale_result.get("mounted_ids").stringify(),
    committed_ids.stringify(),
  )
  assert_eq(
    stale_result.get("error").get("code").to_str(),
    "BaseRevisionMismatch",
  )
  assert_eq(
    stale_result.get("error").get("message").to_str(),
    "candidate base revision is stale",
  )
  assert_true(stale_lifecycle.phase() == @cognition.GenerativeUiPhase::Rejected)
  assert_eq(session_test_nested_texts("session-root-a"), "initial")
  jsx_session_dispose(stale_handle)
}

///|
test "replay candidate adapter rejects a stale session revision before commit" {
  install_session_test_document()
  let created = @js.parse(
    jsx_session_new("<div>initial</div>", "session-root-a"),
  )
  let handle = session_test_handle(created)
  let committed_ids = created.get("result").get("mounted_ids")
  let candidate = "{\"type\":\"component\",\"name\":\"stack\",\"attributes\":[],\"children\":[{\"type\":\"component\",\"name\":\"text\",\"attributes\":[{\"name\":\"value\",\"value\":\"Orders\"}],\"children\":[]}]}"
  let capabilities = "{\"bindings\":[],\"filter_operators\":[],\"aggregations\":[]}"
  let result = @js.parse(
    jsx_session_replay_candidate_json(handle, 0, candidate, capabilities),
  )
  assert_false(result.get("success").cast())
  assert_eq(result.get("error").get("code").to_str(), "BaseRevisionMismatch")
  assert_eq(result.get("revision").cast(), 1)
  assert_eq(result.get("mounted_ids").stringify(), committed_ids.stringify())
  assert_eq(session_test_nested_texts("session-root-a"), "initial")
  jsx_session_dispose(handle)
}

///|
test "replay candidate adapter commits JSX-significant text exactly" {
  install_session_test_document()
  let created = @js.parse(
    jsx_session_new("<div>initial</div>", "session-root-a"),
  )
  let handle = session_test_handle(created)
  let candidate = "{\"type\":\"component\",\"name\":\"stack\",\"attributes\":[],\"children\":[{\"type\":\"component\",\"name\":\"text\",\"attributes\":[{\"name\":\"value\",\"value\":\"unsafe <tag>\"}],\"children\":[]}]}"
  let capabilities = "{\"bindings\":[],\"filter_operators\":[],\"aggregations\":[]}"
  let result = @js.parse(
    jsx_session_replay_candidate_json(handle, 1, candidate, capabilities),
  )
  assert_true(result.get("success").cast())
  assert_eq(result.get("revision").cast(), 2)
  assert_eq(session_test_nested_texts("session-root-a"), "unsafe <tag>")
  jsx_session_dispose(handle)
}

///|
test "replay candidate adapter rejects excessive empty chunks before splitting" {
  install_session_test_document()
  let created = @js.parse(
    jsx_session_new("<div>initial</div>", "session-root-a"),
  )
  let handle = session_test_handle(created)
  let excessive_chunks = String::repeat(
    "\u{0000}",
    @cognition.GENERATIVE_UI_MAX_CHUNKS,
  )
  let capabilities = "{\"bindings\":[],\"filter_operators\":[],\"aggregations\":[]}"
  let result = @js.parse(
    jsx_session_replay_candidate_json(handle, 1, excessive_chunks, capabilities),
  )
  assert_false(result.get("success").cast())
  assert_eq(result.get("error").get("code").to_str(), "InputRejected")
  assert_eq(result.get("revision").cast(), 1)
  assert_eq(session_test_nested_texts("session-root-a"), "initial")
  jsx_session_dispose(handle)
}

///|
test "replay candidate adapter decodes typed JSON errors without committing" {
  install_session_test_document()
  let created = @js.parse(
    jsx_session_new("<div>initial</div>", "session-root-a"),
  )
  let handle = session_test_handle(created)
  let committed_ids = created.get("result").get("mounted_ids")
  let malformed_candidate = "{\"type\":\"component\",\"name\":\"stack\",\"attributes\":[],\"children\":[{\"type\":\"text\"}]}"
  let capabilities = "{\"bindings\":[],\"filter_operators\":[],\"aggregations\":[]}"
  let result = @js.parse(
    jsx_session_replay_candidate_json(
      handle, 1, malformed_candidate, capabilities,
    ),
  )
  assert_false(result.get("success").cast())
  assert_eq(result.get("error").get("code").to_str(), "CandidateDecodeError")
  assert_eq(result.get("revision").cast(), 1)
  assert_eq(result.get("mounted_ids").stringify(), committed_ids.stringify())
  assert_eq(session_test_nested_texts("session-root-a"), "initial")
  jsx_session_dispose(handle)
}

///|
test "replay candidate adapter rejects too-deep JSON before typed recursion" {
  install_session_test_document()
  let created = @js.parse(
    jsx_session_new("<div>initial</div>", "session-root-a"),
  )
  let handle = session_test_handle(created)
  let depth = @cognition.GENERATIVE_UI_MAX_DEPTH + 1
  let prefix = String::repeat(
    "{\"type\":\"component\",\"name\":\"stack\",\"attributes\":[],\"children\":[",
    depth,
  )
  let suffix = String::repeat("]}", depth)
  let candidate = prefix + "{\"type\":\"text\",\"value\":\"leaf\"}" + suffix
  let capabilities = "{\"bindings\":[],\"filter_operators\":[],\"aggregations\":[]}"
  let result = @js.parse(
    jsx_session_replay_candidate_json(handle, 1, candidate, capabilities),
  )
  assert_false(result.get("success").cast())
  assert_eq(result.get("error").get("code").to_str(), "CandidateDecodeError")
  assert_eq(result.get("revision").cast(), 1)
  assert_eq(session_test_nested_texts("session-root-a"), "initial")
  jsx_session_dispose(handle)
}

///|
test "replay candidate adapter rejects children attached to a leaf" {
  install_session_test_document()
  let created = @js.parse(
    jsx_session_new("<div>initial</div>", "session-root-a"),
  )
  let handle = session_test_handle(created)
  let depth = @cognition.GENERATIVE_UI_MAX_DEPTH + 1
  let prefix = String::repeat(
    "{\"type\":\"component\",\"name\":\"stack\",\"attributes\":[],\"children\":[",
    depth,
  )
  let suffix = String::repeat("]}", depth)
  let nested_children = prefix +
    "{\"type\":\"text\",\"value\":\"nested\"}" +
    suffix
  let candidate = "{\"type\":\"text\",\"value\":\"leaf\",\"children\":[" +
    nested_children +
    "]}"
  let capabilities = "{\"bindings\":[],\"filter_operators\":[],\"aggregations\":[]}"
  let result = @js.parse(
    jsx_session_replay_candidate_json(handle, 1, candidate, capabilities),
  )
  assert_false(result.get("success").cast())
  assert_eq(result.get("error").get("code").to_str(), "CandidateDecodeError")
  assert_eq(result.get("revision").cast(), 1)
  assert_eq(session_test_nested_texts("session-root-a"), "initial")
  jsx_session_dispose(handle)
}

///|
test "replay candidate adapter treats optional JSON null as absent" {
  install_session_test_document()
  let created = @js.parse(
    jsx_session_new("<div>initial</div>", "session-root-a"),
  )
  let handle = session_test_handle(created)
  let candidate = "{\"type\":\"component\",\"name\":\"stack\",\"attributes\":[],\"children\":[{\"type\":\"text\",\"value\":\"leaf\",\"name\":null,\"attributes\":null,\"children\":null}]}"
  let capabilities = "{\"bindings\":[],\"filter_operators\":[],\"aggregations\":[]}"
  let result = @js.parse(
    jsx_session_replay_candidate_json(handle, 1, candidate, capabilities),
  )
  assert_true(result.get("success").cast())
  assert_eq(result.get("revision").cast(), 2)
  assert_eq(session_test_nested_texts("session-root-a"), "leaf")
  jsx_session_dispose(handle)
}

///|
test "replay candidate adapter bounds leaf attributes" {
  install_session_test_document()
  let created = @js.parse(
    jsx_session_new("<div>initial</div>", "session-root-a"),
  )
  let handle = session_test_handle(created)
  let attribute = "{\"name\":\"field\",\"value\":\"x\"}"
  let attributes = String::repeat(
      attribute + ",",
      @cognition.GENERATIVE_UI_MAX_ATTRIBUTES,
    ) +
    attribute
  let candidate = "{\"type\":\"text\",\"value\":\"leaf\",\"attributes\":[" +
    attributes +
    "]}"
  let capabilities = "{\"bindings\":[],\"filter_operators\":[],\"aggregations\":[]}"
  let result = @js.parse(
    jsx_session_replay_candidate_json(handle, 1, candidate, capabilities),
  )
  assert_false(result.get("success").cast())
  assert_eq(result.get("error").get("code").to_str(), "CandidateDecodeError")
  assert_eq(result.get("revision").cast(), 1)
  assert_eq(session_test_nested_texts("session-root-a"), "initial")
  jsx_session_dispose(handle)
}

///|
test "replay candidate adapter bounds capabilities JSON before decoding" {
  install_session_test_document()
  let created = @js.parse(
    jsx_session_new("<div>initial</div>", "session-root-a"),
  )
  let handle = session_test_handle(created)
  let padding = String::repeat("x", GENUI_MAX_CAPABILITIES_LENGTH + 1)
  let capabilities = "{\"bindings\":[],\"filter_operators\":[],\"aggregations\":[],\"padding\":\"" +
    padding +
    "\"}"
  let candidate = "{\"type\":\"component\",\"name\":\"stack\",\"attributes\":[],\"children\":[]}"
  let result = @js.parse(
    jsx_session_replay_candidate_json(handle, 1, candidate, capabilities),
  )
  assert_false(result.get("success").cast())
  assert_eq(result.get("error").get("code").to_str(), "CapabilityDecodeError")
  assert_eq(result.get("revision").cast(), 1)
  assert_eq(
    session_test_root_attribute("session-root-a", "data-genui-kind"),
    "",
  )
  jsx_session_dispose(handle)
}

///|
test "replay candidate adapter rejects invalid and stale sessions before decoding" {
  install_session_test_document()
  let invalid = @js.parse(
    jsx_session_replay_candidate_json(987654, 1, "not-json", "not-json"),
  )
  assert_false(invalid.get("success").cast())
  assert_eq(invalid.get("error").get("code").to_str(), "InvalidSession")
  assert_eq(invalid.get("revision").cast(), 0)

  let created = @js.parse(
    jsx_session_new("<div>initial</div>", "session-root-a"),
  )
  let handle = session_test_handle(created)
  let stale = @js.parse(
    jsx_session_replay_candidate_json(handle, 0, "not-json", "not-json"),
  )
  assert_false(stale.get("success").cast())
  assert_eq(stale.get("error").get("code").to_str(), "BaseRevisionMismatch")
  assert_eq(stale.get("revision").cast(), 1)
  assert_eq(session_test_nested_texts("session-root-a"), "initial")
  jsx_session_dispose(handle)
}

///|
test "replay candidate adapter bounds capability arrays and strings" {
  install_session_test_document()
  let created = @js.parse(
    jsx_session_new("<div>initial</div>", "session-root-a"),
  )
  let handle = session_test_handle(created)
  let candidate = "{\"type\":\"component\",\"name\":\"stack\",\"attributes\":[],\"children\":[]}"
  let binding = "{\"name\":\"orders\",\"fields\":[],\"selection_keys\":[]}"
  let oversized_bindings = String::repeat(
      binding + ",",
      GENUI_MAX_CAPABILITY_BINDINGS,
    ) +
    binding
  let fields = String::repeat("\"field\",", GENUI_MAX_CAPABILITY_FIELDS) +
    "\"field\""
  let binding_with_oversized_fields = "{\"name\":\"orders\",\"fields\":[" +
    fields +
    "],\"selection_keys\":[]}"
  let selection_keys = String::repeat(
      "\"id\",",
      GENUI_MAX_CAPABILITY_SELECTION_KEYS,
    ) +
    "\"id\""
  let binding_with_oversized_selection_keys = "{\"name\":\"orders\",\"fields\":[],\"selection_keys\":[" +
    selection_keys +
    "]}"
  let operators = String::repeat(
      "\"contains\",",
      GENUI_MAX_CAPABILITY_OPERATORS,
    ) +
    "\"contains\""
  let aggregations = String::repeat(
      "\"sum\",",
      GENUI_MAX_CAPABILITY_AGGREGATIONS,
    ) +
    "\"sum\""
  let long_name = String::repeat(
    "x",
    @cognition.GENERATIVE_UI_MAX_STRING_LENGTH + 1,
  )
  let binding_with_long_name = "{\"name\":\"" +
    long_name +
    "\",\"fields\":[],\"selection_keys\":[]}"
  let capability_cases = [
    "{\"bindings\":[" +
    oversized_bindings +
    "],\"filter_operators\":[],\"aggregations\":[]}",
    "{\"bindings\":[" +
    binding_with_oversized_fields +
    "],\"filter_operators\":[],\"aggregations\":[]}",
    "{\"bindings\":[" +
    binding_with_oversized_selection_keys +
    "],\"filter_operators\":[],\"aggregations\":[]}",
    "{\"bindings\":[],\"filter_operators\":[" +
    operators +
    "],\"aggregations\":[]}",
    "{\"bindings\":[],\"filter_operators\":[],\"aggregations\":[" +
    aggregations +
    "]}",
    "{\"bindings\":[" +
    binding_with_long_name +
    "],\"filter_operators\":[],\"aggregations\":[]}",
  ]
  for capabilities in capability_cases {
    let result = @js.parse(
      jsx_session_replay_candidate_json(handle, 1, candidate, capabilities),
    )
    assert_false(result.get("success").cast())
    assert_eq(result.get("error").get("code").to_str(), "CapabilityDecodeError")
    assert_eq(result.get("revision").cast(), 1)
  }
  assert_eq(
    session_test_root_attribute("session-root-a", "data-genui-kind"),
    "",
  )
  jsx_session_dispose(handle)
}
