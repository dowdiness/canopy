///|
test "EditModeState roundtrip" {
  let state : @ephemeral.EditModeState = { node_id: "node-42", }
  let ephemeral = state.to_ephemeral()
  @debug.debug_inspect(
    @ephemeral.EditModeState::from_ephemeral(ephemeral),
    content=(
      #|Some({ node_id: "node-42" })
    ),
  )
}

///|
test "EditModeState from_ephemeral rejects non-Map" {
  @debug.debug_inspect(
    @ephemeral.EditModeState::from_ephemeral(@ephemeral.EphemeralValue::Null),
    content="None",
  )
}

///|
test "DragState roundtrip with target" {
  let state : @ephemeral.DragState = {
    source_id: "src",
    target: Some(("tgt", Before)),
  }
  let result = @ephemeral.DragState::from_ephemeral(state.to_ephemeral())
  @debug.debug_inspect(
    result,
    content=(
      #|Some({ source_id: "src", target: Some(("tgt", Before)) })
    ),
  )
}

///|
test "DragState roundtrip without target" {
  let state : @ephemeral.DragState = { source_id: "src", target: None, }
  let result = @ephemeral.DragState::from_ephemeral(state.to_ephemeral())
  @debug.debug_inspect(
    result,
    content=(
      #|Some({ source_id: "src", target: None })
    ),
  )
}

///|
test "PeerPresence roundtrip" {
  let p : @ephemeral.PeerPresence = {
    peer_id: "alice",
    display_name: "Alice",
    color: "#ff0000",
    status: Active,
  }
  let result = @ephemeral.PeerPresence::from_ephemeral(p.to_ephemeral())
  @debug.debug_inspect(
    result,
    content=(
      #|Some(
      #|  {
      #|    peer_id: "alice",
      #|    display_name: "Alice",
      #|    color: "#ff0000",
      #|    status: Active,
      #|  },
      #|)
    ),
  )
}

///|
test "PeerPresence idle status roundtrip" {
  let p : @ephemeral.PeerPresence = {
    peer_id: "bob",
    display_name: "Bob",
    color: "#0000ff",
    status: Idle,
  }
  let result = @ephemeral.PeerPresence::from_ephemeral(p.to_ephemeral())
  match result {
    Some(presence) => inspect(presence.status, content="Idle")
    None => fail("expected Some")
  }
}
