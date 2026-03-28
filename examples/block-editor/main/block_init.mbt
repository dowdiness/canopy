///|
let docs : Map[Int, BlockDoc] = Map::new()

///|
let replica_ids : Map[Int, String] = Map::new()

///|
let next_handle : Ref[Int] = { val: 1 }

///|
pub fn create_editor(replica_id : String) -> Int {
  let handle = next_handle.val
  next_handle.val = handle + 1
  docs[handle] = BlockDoc::new(replica_id)
  replica_ids[handle] = replica_id
  handle
}

///|
pub fn destroy_editor(handle : Int) -> Unit {
  docs.remove(handle)
  replica_ids.remove(handle)
}

///|
fn get_replica_id(handle : Int) -> String {
  match replica_ids.get(handle) {
    Some(id) => id
    None => "unknown"
  }
}

///|
/// Parse "agent:counter" string into a TreeNodeId.
/// Splits on last ':' so agent IDs without ':' are safe.
fn parse_block_id(s : String) -> @tree.TreeNodeId {
  let mut last_colon = -1
  for i = 0; i < s.length(); i = i + 1 {
    if s[i] == ':' {
      last_colon = i
    }
  }
  if last_colon < 0 {
    return @tree.root_id
  }
  let agent = s[0:last_colon].to_string()
  let counter_str = s[last_colon + 1:].to_string()
  let mut counter = 0
  let mut neg = false
  let mut start = 0
  if counter_str.length() > 0 && counter_str[0] == '-' {
    neg = true
    start = 1
  }
  for i = start; i < counter_str.length(); i = i + 1 {
    let d = counter_str[i].to_int() - 48
    counter = counter * 10 + d
  }
  if neg {
    counter = -counter
  }
  @tree.tree_node_id_new(agent, counter)
}

///|
pub fn get_render_state(handle : Int) -> String {
  match docs.get(handle) {
    Some(_) => "{\"blocks\":[]}" // placeholder — Task 2 will implement fully
    None => "{\"blocks\":[]}"
  }
}
