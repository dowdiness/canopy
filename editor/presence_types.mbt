///|
pub(all) struct EditModeState {
  node_id : String
} derive(Show, Eq)

///|
pub(all) enum DragPosition {
  Before
  After
  Inside
} derive(Show, Eq)

///|
pub(all) struct DragState {
  source_id : String
  target : (String, DragPosition)?
} derive(Show, Eq)

///|
pub(all) enum PresenceStatus {
  Active
  Idle
} derive(Show, Eq)

///|
pub(all) struct PeerPresence {
  peer_id : String
  display_name : String
  color : String
  status : PresenceStatus
} derive(Show, Eq)

///|
pub fn EditModeState::to_ephemeral(self : EditModeState) -> EphemeralValue {
  let map : Map[String, EphemeralValue] = {}
  map["node_id"] = EphemeralValue::String(self.node_id)
  EphemeralValue::Map(map)
}

///|
pub fn EditModeState::from_ephemeral(value : EphemeralValue) -> EditModeState? {
  match value {
    EphemeralValue::Map(map) =>
      match map.get("node_id") {
        Some(EphemeralValue::String(id)) => Some({ node_id: id })
        _ => None
      }
    _ => None
  }
}

///|
fn drag_position_to_string(pos : DragPosition) -> String {
  match pos {
    Before => "before"
    After => "after"
    Inside => "inside"
  }
}

///|
fn drag_position_from_string(s : String) -> DragPosition? {
  match s {
    "before" => Some(Before)
    "after" => Some(After)
    "inside" => Some(Inside)
    _ => None
  }
}

///|
pub fn DragState::to_ephemeral(self : DragState) -> EphemeralValue {
  let map : Map[String, EphemeralValue] = {}
  map["source_id"] = EphemeralValue::String(self.source_id)
  match self.target {
    Some((target_id, position)) => {
      map["target_id"] = EphemeralValue::String(target_id)
      map["position"] = EphemeralValue::String(
        drag_position_to_string(position),
      )
    }
    None => ()
  }
  EphemeralValue::Map(map)
}

///|
pub fn DragState::from_ephemeral(value : EphemeralValue) -> DragState? {
  match value {
    EphemeralValue::Map(map) =>
      match map.get("source_id") {
        Some(EphemeralValue::String(source_id)) => {
          let target = match (map.get("target_id"), map.get("position")) {
            (
              Some(EphemeralValue::String(tid)),
              Some(EphemeralValue::String(pos)),
            ) =>
              match drag_position_from_string(pos) {
                Some(dp) => Some((tid, dp))
                None => None
              }
            _ => None
          }
          Some({ source_id, target })
        }
        _ => None
      }
    _ => None
  }
}

///|
fn presence_status_to_string(status : PresenceStatus) -> String {
  match status {
    Active => "active"
    Idle => "idle"
  }
}

///|
fn presence_status_from_string(s : String) -> PresenceStatus {
  match s {
    "idle" => Idle
    _ => Active // default to Active for forward-compatibility
  }
}

///|
pub fn PeerPresence::to_ephemeral(self : PeerPresence) -> EphemeralValue {
  let map : Map[String, EphemeralValue] = {}
  map["peer_id"] = EphemeralValue::String(self.peer_id)
  map["display_name"] = EphemeralValue::String(self.display_name)
  map["color"] = EphemeralValue::String(self.color)
  map["status"] = EphemeralValue::String(presence_status_to_string(self.status))
  EphemeralValue::Map(map)
}

///|
pub fn PeerPresence::from_ephemeral(value : EphemeralValue) -> PeerPresence? {
  match value {
    EphemeralValue::Map(map) => {
      let peer_id = match map.get("peer_id") {
        Some(EphemeralValue::String(s)) => s
        _ => return None
      }
      let display_name = match map.get("display_name") {
        Some(EphemeralValue::String(s)) => s
        _ => return None
      }
      let color = match map.get("color") {
        Some(EphemeralValue::String(s)) => s
        _ => return None
      }
      let status = match map.get("status") {
        Some(EphemeralValue::String(s)) => presence_status_from_string(s)
        _ => Active
      }
      Some({ peer_id, display_name, color, status })
    }
    _ => None
  }
}
