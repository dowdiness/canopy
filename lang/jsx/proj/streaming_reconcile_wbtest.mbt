///| Task 2.4 — streaming-reconciliation existence-proof test.
///
/// Simulates an LLM streaming JSX token-by-token by feeding the parser
/// monotonically growing prefixes of a fixed fixture and asserting that
/// NodeIds already assigned to fully-tag-named ancestor elements do not
/// change as later siblings/descendants are appended. This is the actual
/// generative-UI value proposition from this plan's "Why" section — not
/// generic coverage.

///|
let streaming_fixture : String = "<div><h1>{title}</h1><p>hello world</p></div>"

///|
/// 6 monotonically growing prefixes of the fixture; indices 0 and 1 both
/// cut mid-token (mid-tag-name), per Task 1.1 Step 2 cases 3/4 — LLM
/// token streams don't align with JSX token boundaries.
let streaming_prefixes : Array[String] = [
  "<di", // mid-tag-name (outer element)
   "<div><h1", // mid-tag-name (inner element; outer tag now complete)
   "<div><h1>", "<div><h1>{titl", // mid-expression
   "<div><h1>{title}</h1><p>hello", // mid-text
   streaming_fixture, // full string
]

///|
test "streaming: element identity stable from first complete-tag-name appearance" {
  let parser = @loom.new_parser(streaming_prefixes[0], @jsx.jsx_grammar)
  let (proj_memo, _, _) = build_jsx_projection_memos(parser)

  // Prefix 0 ("<di"): the outer element's tag is truncated mid-word — a
  // transient Element(tag="di") that must NOT share identity with the
  // eventual Element(tag="div") once the tag name completes (Element's
  // same_kind is tag-sensitive by design — one identity reset at
  // streaming tag completion).
  let root0 = proj_memo.read_or_abort().unwrap()
  let di_id = root0.children[0].id()

  // Prefix 1 ("<div><h1"): the outer element's tag is now complete
  // ("div") and never changes again for the rest of the stream — this is
  // the recording point per the plan's Task 2.4 Step 3 recording-point
  // clarification, not prefix 0.
  parser.set_source(streaming_prefixes[1])
  let root1 = proj_memo.read_or_abort().unwrap()
  let div = root1.children[0]
  let div_id = div.id()
  inspect(div.kind.kind_tag(), content="Element")
  // Companion assertion (plan's optional note): the one-time reset is
  // real — "<di"'s id must differ from "<div"'s.
  inspect(di_id == div_id, content="false")

  // The inner element's tag ("h1") is also already complete at this same
  // prefix — it cannot grow into anything else before the fixture's own
  // `>` arrives — so it is recorded here too.
  let h1 = div.children[0]
  let h1_id = h1.id()
  inspect(h1.kind.kind_tag(), content="Element")

  // Remaining prefixes: both IDs stay stable, and div's children stay
  // non-empty throughout (Task 1.1 Step 2 case 2's hard requirement — an
  // unclosed element still exposes its already-parsed children).
  for i in 2..<streaming_prefixes.length() {
    parser.set_source(streaming_prefixes[i])
    let root = proj_memo.read_or_abort().unwrap()
    let div_now = root.children[0]
    inspect(div_now.id() == div_id, content="true")
    inspect(div_now.children.length() > 0, content="true")
    let h1_now = div_now.children[0]
    inspect(h1_now.id() == h1_id, content="true")
  }
}

///|
/// Design A's "Growing opaque ExprSpan identity" — required test 1 of 2:
/// stability across an unclosed prefix growing into a closed one.
test "streaming: ExprSpan identity stable across unclosed-to-closed growth" {
  let prefixes : Array[String] = ["<h1>{titl", "<h1>{title", "<h1>{title}"]
  let parser = @loom.new_parser(prefixes[0], @jsx.jsx_grammar)
  let (proj_memo, _, _) = build_jsx_projection_memos(parser)
  let root0 = proj_memo.read_or_abort().unwrap()
  let expr0 = root0.children[0].children[0]
  inspect(expr0.kind.kind_tag(), content="ExprSpan")
  let expr_id = expr0.id()
  for i in 1..<prefixes.length() {
    parser.set_source(prefixes[i])
    let root = proj_memo.read_or_abort().unwrap()
    let expr = root.children[0].children[0]
    inspect(expr.kind.kind_tag(), content="ExprSpan")
    inspect(expr.id() == expr_id, content="true")
  }
}

///|
/// Design A's "Growing opaque ExprSpan identity" — required test 2 of 2:
/// stability across content mutation while the span stays closed at
/// every step (a distinct claim from the unclosed-to-closed case above —
/// both are CST re-parses of a re-tagged-ExprSpan node, but this one
/// never passes through an unclosed intermediate state).
test "streaming: ExprSpan identity stable across closed-content growth" {
  let prefixes : Array[String] = ["<h1>{a}", "<h1>{ab}", "<h1>{abc}"]
  let parser = @loom.new_parser(prefixes[0], @jsx.jsx_grammar)
  let (proj_memo, _, _) = build_jsx_projection_memos(parser)
  let root0 = proj_memo.read_or_abort().unwrap()
  let expr_id = root0.children[0].children[0].id()
  for i in 1..<prefixes.length() {
    parser.set_source(prefixes[i])
    let root = proj_memo.read_or_abort().unwrap()
    let expr = root.children[0].children[0]
    inspect(expr.id() == expr_id, content="true")
  }
}
