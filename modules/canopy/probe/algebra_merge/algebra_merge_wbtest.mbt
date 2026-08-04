///|
let algebra_merge_test_source : @loomcore.SourceId = @loomcore.SourceId(
  "canopy-test:algebra-merge",
)

///|
/// Base document shared by both replicas before they diverge.
///
/// Offsets referenced by the operations below (`fn send(msg, kind) { msg + kind }`):
///
/// ```text
///   0         1         2         3
///   0123456789012345678901234567890123
///   fn send(msg, kind) { msg + kind }
///           ^^^  ^^^^     ^^^   ^^^^
///           8-11 13-17    21-24 27-31
/// ```
const BASE : String =
  #|fn send(msg, kind) { msg + kind }
  #|send 1 2

///|
/// The result a *semantic* merge of Rename and MoveParam must produce.
const INTENDED_RENAME_X_MOVE : String =
  #|fn send(kind, message) { message + kind }
  #|send 1 2

///|
/// The result a semantic merge of the two disjoint renames must produce.
const INTENDED_RENAME_X_RENAME : String =
  #|fn send(message, level) { message + level }
  #|send 1 2

///|
/// Two replicas sharing `BASE` with a common causal history.
fn make_replicas() -> (@text.TextState, @text.TextState) raise {
  let alice = @text.TextState::new("alice")
  let bob = @text.TextState::new("bob")
  alice.insert(@text.Pos::at(0), BASE)
  let _ = bob.sync().apply(alice.sync().export_all())
  (alice, bob)
}

///|
/// `Rename(msg -> message)`: the declaration site plus every use site.
/// Applied right-to-left so the earlier offsets stay valid.
fn op_rename_msg(doc : @text.TextState) -> Unit raise {
  doc.replace_range(@text.Range::from_ints(21, 24), "message")
  doc.replace_range(@text.Range::from_ints(8, 11), "message")
}

///|
/// `Rename(kind -> level)`: the disjoint-region control.
fn op_rename_kind(doc : @text.TextState) -> Unit raise {
  doc.replace_range(@text.Range::from_ints(27, 31), "level")
  doc.replace_range(@text.Range::from_ints(13, 17), "level")
}

///|
/// `MoveParam(msg, +1)` lowered as a single region rewrite — what a
/// naive structural editor emits when it re-prints the parameter list.
fn op_move_param_as_rewrite(doc : @text.TextState) -> Unit raise {
  doc.replace_range(@text.Range::from_ints(8, 17), "kind, msg")
}

///|
/// `MoveParam(msg, +1)` lowered as an actual move: cut `msg, `, paste `, msg`
/// after `kind`. Same resulting text, different operation shape.
fn op_move_param_as_cut_paste(doc : @text.TextState) -> Unit raise {
  doc.delete_range(@text.Range::from_ints(8, 13))
  doc.insert(@text.Pos::at(12), ", msg")
}

///|
/// Exchange every operation between the replicas. `alice_first` only controls
/// the order in which each side *applies* the other's message.
fn merge(
  alice : @text.TextState,
  bob : @text.TextState,
  alice_first~ : Bool,
) -> Unit raise {
  let from_alice = alice.sync().export_all()
  let from_bob = bob.sync().export_all()
  if alice_first {
    let _ = bob.sync().apply(from_alice)
    let _ = alice.sync().apply(from_bob)
  } else {
    let _ = alice.sync().apply(from_bob)
    let _ = bob.sync().apply(from_alice)
  }
}

///|
/// Number of unbound variable references, or `None` if the text no longer
/// parses. This is the semantic judge: a merge can converge and still leave
/// the program referring to a binder that no longer exists.
fn free_vars(source : String) -> String {
  let term = @lambda.parse(algebra_merge_test_source, source) catch {
    _ => return "does not parse"
  }
  let (_, resolution) = @lambda.resolve(term)
  let free = resolution.vars
    .values()
    .filter(status => status is @lambda.VarStatus::Free)
    .count()
  free.to_string()
}

///|
/// Run one scenario in both merge orders and report a single verdict string.
fn run_scenario(
  op_alice : (@text.TextState) -> Unit raise,
  op_bob : (@text.TextState) -> Unit raise,
  intended : String,
) -> String raise {
  let orders = [true, false]
  let results = orders.map(alice_first => {
    let (alice, bob) = make_replicas()
    op_alice(alice)
    op_bob(bob)
    merge(alice, bob, alice_first~)
    (alice.text(), bob.text())
  })
  let (a0, b0) = results[0]
  let (a1, b1) = results[1]
  let converged = a0 == b0 && a1 == b1
  let order_independent = a0 == a1
  let merged = a0
  let verdict =
    $|converged (both replicas agree): \{converged}
    $|order-independent: \{order_independent}
    $|merged text:
    $|\{merged}
    $|matches intended semantic merge: \{merged == intended}
    $|intended text:
    $|\{intended}
    $|free variables after merge: \{free_vars(merged)}
    $|free variables in intended: \{free_vars(intended)}
  verdict
}

///|
/// CONTROL — two renames over disjoint regions. If the harness cannot merge
/// even this, any failure in the real scenario says nothing about the paper's
/// claim.
test "control: disjoint renames merge to the intended program" {
  let report = run_scenario(
    op_rename_msg,
    op_rename_kind,
    INTENDED_RENAME_X_RENAME,
  )
  inspect(
    report,
    content=(
      #|converged (both replicas agree): true
      #|order-independent: true
      #|merged text:
      #|fn send(message, level) { message + level }
      #|send 1 2
      #|matches intended semantic merge: true
      #|intended text:
      #|fn send(message, level) { message + level }
      #|send 1 2
      #|free variables after merge: 0
      #|free variables in intended: 0
    ),
  )
}

///|
/// SCENARIO A — Fig. 3, with MoveParam lowered as a region rewrite.
test "rename x move-param (region rewrite lowering)" {
  let report = run_scenario(
    op_rename_msg,
    op_move_param_as_rewrite,
    INTENDED_RENAME_X_MOVE,
  )
  inspect(
    report,
    content=(
      #|converged (both replicas agree): true
      #|order-independent: true
      #|merged text:
      #|fn send(messagekind, msg) { message + kind }
      #|send 1 2
      #|matches intended semantic merge: false
      #|intended text:
      #|fn send(kind, message) { message + kind }
      #|send 1 2
      #|free variables after merge: 2
      #|free variables in intended: 0
    ),
  )
}

///|
/// SCENARIO B — same semantic pair, MoveParam lowered as cut/paste. Included
/// because a failure under one lowering only is a property of the lowering,
/// not of the text CRDT.
test "rename x move-param (cut/paste lowering)" {
  let report = run_scenario(
    op_rename_msg,
    op_move_param_as_cut_paste,
    INTENDED_RENAME_X_MOVE,
  )
  inspect(
    report,
    content=(
      #|converged (both replicas agree): true
      #|order-independent: true
      #|merged text:
      #|fn send(messagekind, msg) { message + kind }
      #|send 1 2
      #|matches intended semantic merge: false
      #|intended text:
      #|fn send(kind, message) { message + kind }
      #|send 1 2
      #|free variables after merge: 2
      #|free variables in intended: 0
    ),
  )
}
