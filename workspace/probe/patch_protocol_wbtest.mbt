// Workspace patch-protocol probe — P0a gate #2.
//
// Tests whether `UserIntent::StructuralEdit { op, params: Map[String, String] }`
// (protocol/user_intent.mbt:11-23) can faithfully round-trip a
// representative set of Lambda `TreeEditOp` variants.
//
// Recipe (docs/research/2026-05-22-spec-aware-workspace.md Appendix B P0a #2):
//   Rename, ExtractToLet, CommitEdit, Drop, WrapInBop, InsertChild
//
// Codex review 2026-05-23 swap (load-bearing):
//   - dropped CommitEdit (already has its own UserIntent variant —
//     testing it through StructuralEdit is non-load-bearing)
//   - swapped in WrapInLambda — also exercises missing/default param
//     semantics (lang/lambda/companion/tree_edit_json.mbt:98-107).
//
// Decision exit (per the report's Appendix B P0a #2):
//   (i)  widen `params` to Map[String, Json] — small protocol change
//   (ii) per-language typed patch type — more invasive
//
// Per-variant procedure (representability test, not a claim about any
// currently-deployed `UserIntent → TreeEditOp` decoder):
//   1. construct the typed TreeEditOp value (source of truth)
//   2. inline-encode it into UserIntent::StructuralEdit { op, params: Map[String, String] },
//      writing each non-string param's stringification rule explicitly
//   3. JSON-round-trip the UserIntent (proves the wire format survives)
//   4. inline-decode back into a TreeEditOp; show-string-compare to source
//
// Classification verdict (filled in by tests):
//   FIT-CLEAN       — every param is natively a String; no codec needed
//   FIT-TOKENIZED   — at least one Int/enum needs ad-hoc stringification
//                     (per the existing decoder vocabulary at
//                     lang/lambda/companion/tree_edit_json.mbt:27-64)
//   NEEDS-WIDENING  — at least one param is a structured value that
//                     cannot fit a String field without smuggling JSON

///|
fn show_op(op : @lambda_edits.TreeEditOp) -> String {
  @debug.to_string(op)
}

///|
fn show_intent(intent : @protocol.UserIntent) -> String {
  @debug.to_string(intent)
}

///|
/// Render a NodeId as its integer-string form (e.g. NodeId(7) → "7") via
/// the existing ToJson impl at core/types.mbt:30-33. Avoids cross-package
/// tuple-struct destructuring (which is restricted — CLAUDE.md / Reuse
/// Existing Types). Same form `parse_nodeid` consumes below.
fn nodeid_str(id : @core.NodeId) -> String {
  id.to_json().stringify()
}

///|
fn parse_nodeid(s : String) -> @core.NodeId {
  @core.NodeId::from_int(@string.parse_int(s) catch { _ => 0 })
}

///|
// ============================================================
// Section A — FIT-CLEAN: every param is natively a String.
// Expected: 3/3 variants survive Map[String, String] without any codec.
// ============================================================

///|
/// A1 Rename — both params are natively strings.
test "A1 Rename — FIT-CLEAN" {
  let source : @lambda_edits.TreeEditOp = Rename(
    node_id=@core.NodeId::from_int(7),
    new_name="foo",
  )

  // Encoding rule: node_id → wire.node_id; new_name → params["new_name"].
  let params : Map[String, String] = { "new_name": "foo" }
  let wire = @protocol.UserIntent::StructuralEdit(
    node_id=@core.NodeId::from_int(7),
    op="Rename",
    params~,
  )

  // Wire round-trip (the UserIntent JSON survives encode→decode).
  let decoded_wire : @protocol.UserIntent = @json.from_json(wire.to_json())
  assert_eq(show_intent(decoded_wire), show_intent(wire))

  // Decode back to TreeEditOp (inline — no production decoder exists yet).
  let restored : @lambda_edits.TreeEditOp = match decoded_wire {
    StructuralEdit(node_id~, op~, params~) => {
      assert_eq(op, "Rename")
      let new_name = params.get("new_name").unwrap_or("")
      Rename(node_id~, new_name~)
    }
    _ => abort("not a StructuralEdit")
  }
  assert_eq(show_op(restored), show_op(source))
}

///|
/// A2 ExtractToLet — both params are natively strings.
test "A2 ExtractToLet — FIT-CLEAN" {
  let source : @lambda_edits.TreeEditOp = ExtractToLet(
    node_id=@core.NodeId::from_int(3),
    var_name="tmp",
  )
  let params : Map[String, String] = { "var_name": "tmp" }
  let wire = @protocol.UserIntent::StructuralEdit(
    node_id=@core.NodeId::from_int(3),
    op="ExtractToLet",
    params~,
  )
  let decoded_wire : @protocol.UserIntent = @json.from_json(wire.to_json())
  let restored : @lambda_edits.TreeEditOp = match decoded_wire {
    StructuralEdit(node_id~, op~, params~) => {
      assert_eq(op, "ExtractToLet")
      let var_name = params.get("var_name").unwrap_or("")
      ExtractToLet(node_id~, var_name~)
    }
    _ => abort("not a StructuralEdit")
  }
  assert_eq(show_op(restored), show_op(source))
}

///|
/// A3 WrapInLambda — also exercises missing-param semantics: the existing
/// decoder at lang/lambda/companion/tree_edit_json.mbt:98-107 supplies
/// `"x"` when `var_name` is absent. A consumer of UserIntent::StructuralEdit
/// would need to mirror that policy.
test "A3 WrapInLambda — FIT-CLEAN (with default-on-missing)" {
  let source : @lambda_edits.TreeEditOp = WrapInLambda(
    node_id=@core.NodeId::from_int(11),
    var_name="x",
  )

  // Encoding with an explicit var_name.
  let params_explicit : Map[String, String] = { "var_name": "x" }
  let wire_explicit = @protocol.UserIntent::StructuralEdit(
    node_id=@core.NodeId::from_int(11),
    op="WrapInLambda",
    params=params_explicit,
  )
  let decoded_explicit : @protocol.UserIntent = @json.from_json(
    wire_explicit.to_json(),
  )
  let restored_explicit : @lambda_edits.TreeEditOp = match decoded_explicit {
    StructuralEdit(node_id~, op~, params~) => {
      assert_eq(op, "WrapInLambda")
      let var_name = params.get("var_name").unwrap_or("x")
      WrapInLambda(node_id~, var_name~)
    }
    _ => abort("not a StructuralEdit")
  }
  assert_eq(show_op(restored_explicit), show_op(source))

  // Missing-key case: decoder default `"x"` matches the existing decoder.
  let params_empty : Map[String, String] = {}
  let wire_empty = @protocol.UserIntent::StructuralEdit(
    node_id=@core.NodeId::from_int(11),
    op="WrapInLambda",
    params=params_empty,
  )
  let decoded_empty : @protocol.UserIntent = @json.from_json(
    wire_empty.to_json(),
  )
  let restored_empty : @lambda_edits.TreeEditOp = match decoded_empty {
    StructuralEdit(node_id~, op=_, params~) => {
      let var_name = params.get("var_name").unwrap_or("x")
      WrapInLambda(node_id~, var_name~)
    }
    _ => abort("not a StructuralEdit")
  }
  assert_eq(show_op(restored_empty), show_op(source))
}

///|
// ============================================================
// Section B — FIT-TOKENIZED: non-string params, representable via the
// string-tag vocabulary already established in
// lang/lambda/companion/tree_edit_json.mbt:27-64.
// Expected: works, but every param needs its own ad-hoc codec.
// ============================================================

///|
/// B1 WrapInBop — Bop must be tokenized as "Plus" | "Minus"
/// (parse_bop_string at lang/lambda/companion/tree_edit_json.mbt:29-33).
test "B1 WrapInBop — FIT-TOKENIZED (Bop tag)" {
  let source : @lambda_edits.TreeEditOp = WrapInBop(
    node_id=@core.NodeId::from_int(5),
    op=@ast.Bop::Plus,
  )

  // Encoding rule: Bop → "Plus" | "Minus" tag string.
  let bop_tag = match source {
    WrapInBop(op=bop, ..) =>
      match bop {
        Plus => "Plus"
        Minus => "Minus"
      }
    _ => abort("not WrapInBop")
  }
  let params : Map[String, String] = { "op": bop_tag }
  let wire = @protocol.UserIntent::StructuralEdit(
    node_id=@core.NodeId::from_int(5),
    op="WrapInBop",
    params~,
  )

  let decoded_wire : @protocol.UserIntent = @json.from_json(wire.to_json())
  let restored : @lambda_edits.TreeEditOp = match decoded_wire {
    StructuralEdit(node_id~, op~, params~) => {
      assert_eq(op, "WrapInBop")
      let bop = match params.get("op") {
        Some("Plus") => @ast.Bop::Plus
        Some("Minus") => @ast.Bop::Minus
        _ => abort("bad bop tag")
      }
      WrapInBop(node_id~, op=bop)
    }
    _ => abort("not a StructuralEdit")
  }
  assert_eq(show_op(restored), show_op(source))
}

///|
/// B2 Drop — two NodeIds + a DropPosition tag.
///
/// Encoding rule for the spare StructuralEdit.node_id field: by convention,
/// `node_id = source`. `target` lives in params as a stringified int.
/// `position` is tokenized "Before" | "After" | "Inside"
/// (require_drop_position at lang/lambda/companion/tree_edit_json.mbt:55-63).
///
/// The rule is necessary because UserIntent::StructuralEdit carries a single
/// `node_id` (protocol/user_intent.mbt:13-17) but Drop intrinsically refers
/// to two nodes (lang/lambda/edits/tree_lens.mbt:24).
test "B2 Drop — FIT-TOKENIZED (Int + Enum tags + duplicated node_id)" {
  let source : @lambda_edits.TreeEditOp = Drop(
    source=@core.NodeId::from_int(8),
    target=@core.NodeId::from_int(12),
    position=@core.DropPosition::Before,
  )

  // Encoding (the spare node_id slot duplicates source; everything else in params).
  let (src, tgt, pos_tag) = match source {
    Drop(source~, target~, position~) => {
      let pos = match position {
        Before => "Before"
        After => "After"
        Inside => "Inside"
      }
      (source, target, pos)
    }
    _ => abort("not Drop")
  }
  let params : Map[String, String] = {
    "target": nodeid_str(tgt),
    "position": pos_tag,
  }
  let wire = @protocol.UserIntent::StructuralEdit(
    node_id=src,
    op="Drop",
    params~,
  )

  let decoded_wire : @protocol.UserIntent = @json.from_json(wire.to_json())
  let restored : @lambda_edits.TreeEditOp = match decoded_wire {
    StructuralEdit(node_id~, op~, params~) => {
      assert_eq(op, "Drop")
      let target = parse_nodeid(params.get("target").unwrap_or("0"))
      let position = match params.get("position") {
        Some("Before") => @core.DropPosition::Before
        Some("After") => @core.DropPosition::After
        Some("Inside") => @core.DropPosition::Inside
        _ => abort("bad position tag")
      }
      Drop(source=node_id, target~, position~)
    }
    _ => abort("not a StructuralEdit")
  }
  assert_eq(show_op(restored), show_op(source))
}

///|
// ============================================================
// Section C — NEEDS-WIDENING: param value is a structured (recursive) type
// that cannot fit a single String field without smuggling JSON-in-a-string.
// ============================================================

///|
/// C1 InsertChild — `kind: @ast.Term` is a recursive enum
/// (loom/examples/lambda/src/ast/ast.mbt:17-41). The only way to fit it
/// into a `Map[String, String]` value is to embed
/// `term.to_json().stringify()` — turning the protocol invariant
/// "params values are strings" into "params values are strings,
/// except sometimes they're JSON-in-strings".
///
/// This test demonstrates:
///   1. the JSON-in-string encoding "works" — the wire roundtrips
///      without the protocol noticing
///   2. recovering the Term would require both: a JSON re-parse AND a
///      FromJson impl for @ast.Term (currently absent — Term derives
///      only Eq, ToJson, Debug at loom/examples/lambda/src/ast/ast.mbt:41)
test "C1 InsertChild — NEEDS-WIDENING (Term as JSON-in-string)" {
  let kind : @ast.Term = App(Var("f"), Int(1))
  let _source : @lambda_edits.TreeEditOp = InsertChild(
    parent=@core.NodeId::from_int(2),
    index=3,
    kind~,
  )

  // The only way to fit Term into Map[String, String]:
  let kind_as_json_string = kind.to_json().stringify()
  let params : Map[String, String] = {
    "index": "3",
    "kind": kind_as_json_string, // <-- JSON value smuggled through a String field
  }
  let wire = @protocol.UserIntent::StructuralEdit(
    node_id=@core.NodeId::from_int(2),
    op="InsertChild",
    params~,
  )

  // Wire roundtrip — the protocol cannot tell `kind` is JSON.
  let decoded_wire : @protocol.UserIntent = @json.from_json(wire.to_json())
  assert_eq(show_intent(decoded_wire), show_intent(wire))

  // The `kind` value comes out as a JSON-bearing String.
  let kind_back : String = match decoded_wire {
    StructuralEdit(params~, ..) => params.get("kind").unwrap_or("")
    _ => abort("not a StructuralEdit")
  }
  // Sanity: the recovered string is the same JSON we put in.
  assert_eq(kind_back, kind_as_json_string)

  // To turn that string back into an @ast.Term, the consumer would need:
  //   let term_json = @json.parse(kind_back)
  //   let term : @ast.Term = @json.from_json(term_json)  // step 2 does NOT compile today: @ast.Term derives only
  // (Eq, ToJson, Debug), not FromJson. The "round-trip" is therefore
  // one-way for InsertChild under Map[String, String].
  //
  // Verdict: NEEDS-WIDENING. The Map[String, String] shape cannot carry
  // structured payloads without violating the protocol's own invariant.

  // Document the failure-mode observable: `kind_as_json_string` is a
  // multi-character JSON-shaped string, not a primitive label.
  assert_true(kind_as_json_string.length() > 4)
  assert_true(kind_as_json_string.contains("App"))
}

///|
// ============================================================
// Section D — Negative control: the Map[String, String] constraint is
// real today, not a vibes-level concern.
// ============================================================

///|
/// D Decoder rejects a UserIntent JSON whose `params` contains a
/// non-string value. Enforced by protocol/user_intent.mbt:129-137.
test "D Negative control: non-string params value is rejected" {
  // params.index is a JSON number, not a string.
  let body =
    #|{"type":"StructuralEdit","node_id":1,"op":"Foo","params":{"index":42}}
  let json = @json.parse(body)
  let result : Result[@protocol.UserIntent, _] = Ok(@json.from_json(json)) catch {
    e => Err(e)
  }
  assert_true(result is Err(_))
}
