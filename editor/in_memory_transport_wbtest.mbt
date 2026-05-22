///|
test "InMemoryTransport: two peers exchange messages" {
  let room = InMemoryRoom::new()
  let t_a = InMemoryTransport::new("alice", room)
  let t_b = InMemoryTransport::new("bob", room)
  let received : Array[Int] = []
  t_b.on_receive(fn(data) { received.push(data.length()) })
  let buf = @buffer.new()
  buf.write_string("hello")
  t_a.send(buf.to_bytes())
  inspect(received.length(), content="1")
}

///|
test "InMemoryTransport: sender does not receive own message" {
  let room = InMemoryRoom::new()
  let t_a = InMemoryTransport::new("alice", room)
  let received : Array[Int] = []
  t_a.on_receive(fn(data) { received.push(data.length()) })
  let buf = @buffer.new()
  buf.write_string("hello")
  t_a.send(buf.to_bytes())
  inspect(received.length(), content="0")
}

///|
test "InMemoryTransport: three peers broadcast" {
  let room = InMemoryRoom::new()
  let t_a = InMemoryTransport::new("alice", room)
  let t_b = InMemoryTransport::new("bob", room)
  let t_c = InMemoryTransport::new("carol", room)
  let b_msgs : Array[Int] = []
  let c_msgs : Array[Int] = []
  t_b.on_receive(fn(data) { b_msgs.push(data.length()) })
  t_c.on_receive(fn(data) { c_msgs.push(data.length()) })
  let buf = @buffer.new()
  buf.write_string("from-alice")
  t_a.send(buf.to_bytes())
  inspect(b_msgs.length(), content="1")
  inspect(c_msgs.length(), content="1")
}

///|
test "InMemoryTransport: close unregisters peer" {
  let room = InMemoryRoom::new()
  let t_a = InMemoryTransport::new("alice", room)
  let t_b = InMemoryTransport::new("bob", room)
  let a_received : Array[Int] = []
  t_a.on_receive(fn(data) { a_received.push(data.length()) })
  t_a.close()
  // Bob sends after alice closed — alice should not receive
  let buf = @buffer.new()
  buf.write_string("after-close")
  t_b.send(buf.to_bytes())
  inspect(a_received.length(), content="0")
}

///|
test "InMemoryTransport: protocol message roundtrip" {
  let room = InMemoryRoom::new()
  let t_a = InMemoryTransport::new("alice", room)
  let t_b = InMemoryTransport::new("bob", room)
  let received_msgs : Array[SyncMessage] = []
  t_b.on_receive(fn(data) {
    match decode_message(data) {
      Some(msg) => received_msgs.push(msg)
      None => ()
    }
  })
  t_a.send(encode_message(PeerJoined("alice")))
  inspect(received_msgs.length(), content="1")
  inspect(received_msgs[0], content="PeerJoined(\"alice\")")
}
