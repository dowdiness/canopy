///|
test "EditModeState roundtrip" {
  let state : EditModeState = { node_id: "node-42" }
  let ephemeral = state.to_ephemeral()
  inspect(
    EditModeState::from_ephemeral(ephemeral),
    content="Some({node_id: \"node-42\"})",
  )
}

///|
test "EditModeState from_ephemeral rejects non-Map" {
  inspect(EditModeState::from_ephemeral(EphemeralValue::Null), content="None")
}

///|
test "DragState roundtrip with target" {
  let state : DragState = { source_id: "src", target: Some(("tgt", Before)) }
  let result = DragState::from_ephemeral(state.to_ephemeral())
  inspect(
    result,
    content="Some({source_id: \"src\", target: Some((\"tgt\", Before))})",
  )
}

///|
test "DragState roundtrip without target" {
  let state : DragState = { source_id: "src", target: None }
  let result = DragState::from_ephemeral(state.to_ephemeral())
  inspect(result, content="Some({source_id: \"src\", target: None})")
}

///|
test "PeerPresence roundtrip" {
  let p : PeerPresence = {
    peer_id: "alice",
    display_name: "Alice",
    color: "#ff0000",
    status: Active,
  }
  let result = PeerPresence::from_ephemeral(p.to_ephemeral())
  inspect(
    result,
    content="Some({peer_id: \"alice\", display_name: \"Alice\", color: \"#ff0000\", status: Active})",
  )
}

///|
test "PeerPresence idle status roundtrip" {
  let p : PeerPresence = {
    peer_id: "bob",
    display_name: "Bob",
    color: "#0000ff",
    status: Idle,
  }
  let result = PeerPresence::from_ephemeral(p.to_ephemeral())
  match result {
    Some(presence) => inspect(presence.status, content="Idle")
    None => fail("expected Some")
  }
}
