///|
fn PreviewEngine::worker_render_blocks(
  self : PreviewEngine,
  blocks : ArrayView[Json],
) -> Result[(@rabbita.Html, AcceptedMarkdownRender), PreviewFailure] {
  let previous_blocks = self.accepted_render.map_or([], state => {
    state.remote_blocks
  })
  let previous_keys = self.accepted_render.map_or([], state => state.lazy_keys)
  let resolved : Array[RemoteNode] = []
  let seen : Set[Int] = Set([])
  let keys : Array[Int] = []
  let rendered : Array[@rabbita.Html] = []
  let valid = blocks.all(entry => {
    match entry {
      Json::Object(fields) =>
        match (fields.get("reuse"), fields.get("node")) {
          (Some(Json::Number(index_value, ..)), None) => {
            let index = index_value.to_int()
            if index_value != index.to_double() ||
              index < 0 ||
              index >= previous_blocks.length() ||
              index >= previous_keys.length() ||
              !seen.add_and_check(index) {
              false
            } else {
              let node = previous_blocks[index]
              resolved.push(node)
              keys.push(previous_keys[index])
              rendered.push(
                @html.lazy(previous_keys[index], () => render_remote_node(node)),
              )
              true
            }
          }
          (None, Some(node_json)) => {
            let node = decode_node(node_json) catch { _ => return false }
            let key = self.fresh_lazy_key()
            resolved.push(node)
            keys.push(key)
            rendered.push(@html.lazy(key, () => render_remote_node(node)))
            true
          }
          _ => false
        }
      _ => false
    }
  })
  guard valid else { return Err(Unusable) }
  Ok(
    (
      @html.fragment(rendered),
      { previous: None, lazy_keys: keys, remote_blocks: resolved },
    ),
  )
}

///|
fn PreviewEngine::worker_output(
  self : PreviewEngine,
  input : Input,
  request_sequence : Int,
  text : String,
) -> Result[PreviewOutput, PreviewFailure] {
  let json = @json.parse(text) catch { _ => return Err(Unusable) }
  if worker_field(json, "type") != Some(Json::string("preview")) {
    self.break_parser()
    return Err(Unusable)
  }
  let generation = match worker_int(json, "generation") {
    Some(value) => value
    _ => return Err(Unusable)
  }
  let sequence = match worker_int(json, "sequence") {
    Some(value) => value
    None => return Err(Unusable)
  }
  guard generation == input.generation && sequence == request_sequence else {
    return Err(OutOfSync)
  }
  let blocks = match worker_field(json, "blocks") {
    Some(Json::Array(value)) => value
    _ => return Err(Unusable)
  }
  let (html, render) = match self.worker_render_blocks(blocks[:]) {
    Ok(value) => value
    Err(failure) => return Err(failure)
  }
  let acceptance = {
    domain: self.acceptance_domain,
    sequence: self.next_acceptance_sequence,
  }
  self.next_acceptance_sequence += 1
  self.pending_render = Some({
    acceptance,
    owner_generation: self.owner_generation,
    render,
  })
  Ok({ html, empty: blocks.is_empty(), wire_blocks: [], acceptance })
}
