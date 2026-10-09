///|
priv struct Packet {
  id : String
  payload : String
  version : String
  created_at : Double
}

///|
priv struct JournalRow {
  packet : Packet
  cursor : Double
}

///|
priv struct TextChange {
  start : Double
  deleted : Double
  inserted : String
} derive(Eq)

///|
priv struct Changes {
  items : Array[TextChange]
  approximate : Bool
}

///|
priv enum Input {
  ReplaceAll(String)
  Change(TextChange)
} derive(Eq)

///|
priv enum Action {
  Edit(Input, String)
  History(Bool)
}

///|
priv struct EditCommand {
  id : String
  sequence : Double
  before : String
  action : Action
  created_at : Double
}

///|
priv struct SaveFault {
  abort : Bool
  hold : Double
  before_commit : Double
  crash_after_commit : Bool
}

///|
priv enum Command {
  Open(String, String?, Array[Packet])
  Edit(EditCommand)
  Save(Packet, SaveFault)
  Pull(Double)
  Project(Double)
  Inspect
  Durable
  Inject(String)
  TestReplay
  TestApplyChanges
  Invalid(String)
}

///|
priv struct Request {
  epoch : Double
  id : Double
  document : String
  delay : Double
  command : Command
}

///|
priv enum QueuedRequest {
  Valid(Request)
  InvalidEnvelope
}

///|
priv struct Info {
  text : String
  version : String
  count : Int
  pending : Int
  can_undo : Bool
  can_redo : Bool
}

///|
priv struct EditResult {
  info : Info
  packet : Packet?
  changes : Changes
}

///|
priv struct AcceptedCommand {
  command : EditCommand
  result : EditResult
}

///|
priv struct Offer {
  token : Double
  payloads : Array[String]
  info : Info
}

///|
fn same_intent(a : EditCommand, b : EditCommand) -> Bool {
  if a.id != b.id || a.before != b.before {
    return false
  }
  match (a.action, b.action) {
    (Edit(a, _), Edit(b, _)) => a == b
    (History(a), History(b)) => a == b
    _ => false
  }
}

///|
fn decode_change(value : @js.Value) -> TextChange raise {
  {
    start: field_double(value, "start"),
    deleted: field_double(value, "deleted"),
    inserted: field_string(value, "inserted"),
  }
}

///|
fn decode_packet(value : @js.Value) -> Packet raise {
  {
    id: field_string(value, "id"),
    payload: field_string(value, "payload"),
    version: field_string(value, "version"),
    created_at: field_double(value, "createdAt"),
  }
}

///|
fn decode_rows(value : @js.Value) -> Array[JournalRow] raise {
  let rows : Array[JournalRow] = []
  for row in native_array(value) {
    rows.push({
      packet: decode_packet(row),
      cursor: field_double(row, "cursor"),
    })
  }
  rows
}

///|
fn decode_command(raw : @js.Value) -> Command raise {
  let kind = field_string(raw, "type")
  match kind {
    "open" => {
      let basis = js_field(raw, "basisVersion")
      let basis = if basis.is_null() || basis.is_undefined() {
        None
      } else {
        let version = checked_string(basis)
        if version == "" {
          None
        } else {
          Some(version)
        }
      }
      let packets = js_field(raw, "packets")
      let retained : Array[Packet] = []
      if !packets.is_null() && !packets.is_undefined() {
        for packet in native_array(packets) {
          retained.push(decode_packet(packet))
        }
      }
      Open(field_string(raw, "seed"), basis, retained)
    }
    "edit" | "history" => {
      let sequence = js_field(raw, "commandSeq")
      if !js_is_safe_integer(sequence) || checked_double(sequence) < 1.0 {
        raise Failure("Invalid command sequence")
      }
      let action = if kind == "history" {
        History(optional_bool(raw, "redo"))
      } else {
        let value = js_field(raw, "input")
        let input = if optional_bool(value, "full") {
          ReplaceAll(field_string(value, "inserted"))
        } else {
          Change(decode_change(value))
        }
        Edit(input, field_string(raw, "after"))
      }
      Edit({
        id: field_string(raw, "command"),
        sequence: checked_double(sequence),
        before: field_string(raw, "before"),
        action,
        created_at: field_double(raw, "createdAt"),
      })
    }
    "save" => {
      let fault = js_field(raw, "fault")
      Save(decode_packet(js_field(raw, "packet")), {
        abort: optional_bool(fault, "abort"),
        hold: optional_double(fault, "hold"),
        before_commit: optional_double(fault, "beforeCommit"),
        crash_after_commit: optional_bool(fault, "crashAfterCommit"),
      })
    }
    "pull" => Pull(field_double(raw, "revision"))
    "project" => Project(field_double(raw, "token"))
    "inspect" => Inspect
    "durable" => Durable
    "inject" => Inject(field_string(raw, "payload"))
    "test-replay" => TestReplay
    "test-apply-changes" => TestApplyChanges
    _ => Invalid("Unknown Worker request")
  }
}

///|
fn Packet::to_wire(self : Packet) -> @js.Value {
  object([
    ("id", as_value(self.id)),
    ("payload", as_value(self.payload)),
    ("version", as_value(self.version)),
    ("createdAt", as_value(self.created_at)),
  ])
}

///|
fn Info::to_wire(self : Info) -> @js.Value {
  object([
    ("ok", as_value(true)),
    ("text", as_value(self.text)),
    ("version", as_value(self.version)),
    ("count", as_value(self.count)),
    ("pending", as_value(self.pending)),
    ("canUndo", as_value(self.can_undo)),
    ("canRedo", as_value(self.can_redo)),
  ])
}

///|
fn Changes::to_wire(self : Changes) -> @js.Value {
  let values = @js.JsArray::new()
  for change in self.items {
    values.push(
      object([
        ("start", as_value(change.start)),
        ("deleted", as_value(change.deleted)),
        ("inserted", as_value(change.inserted)),
      ]),
    )
  }
  let result = @js.Value::cast_from(values)
  if self.approximate {
    result.set_with_string("approximate", true)
  }
  result
}

///|
fn EditResult::to_wire(self : EditResult) -> @js.Value {
  object([
    ("info", self.info.to_wire()),
    (
      "packet",
      match self.packet {
        Some(packet) => packet.to_wire()
        None => js_null()
      },
    ),
    ("changes", self.changes.to_wire()),
  ])
}
