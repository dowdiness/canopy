///|
fn binding_starts_with_fn(source_text : String, start : Int) -> Bool {
  start + 2 <= source_text.length() &&
  source_text[start] == 'f' &&
  source_text[start + 1] == 'n' &&
  (
    start + 2 == source_text.length() ||
    !is_identifier_code(source_text[start + 2])
  )
}

///|
priv enum BindingRewriteKind {
  ValueBinding
  FnBinding
}

///|
/// Source-owned metadata for binding rewrites.
///
/// Lambda projection intentionally stores function definitions as desugared
/// Lam spines, so parameter type annotations and `fn` block shape do not live
/// in `def.1.kind`. Binding-level edits that duplicate, rename, or inline a
/// source binding must go through this bounded source metadata layer instead
/// of reprinting the projected Term. If the source spans cannot be recovered,
/// reject the edit rather than falling back to a lossy `@ast.print_term` rewrite.
priv struct BindingRewriteSource {
  def : (String, ProjNode[@ast.Term], Int, NodeId)
  binding_start : Int
  binding_end : Int
  kind : BindingRewriteKind
}

///|
fn binding_name_range(
  source_text : String,
  source_map : SourceMap,
  def : (String, ProjNode[@ast.Term], Int, NodeId),
  binding_start : Int,
  binding_end : Int,
) -> Result[(Int, Int), String] {
  match source_map.get_token_span(def.3, @lambda_proj.LET_DEF_NAME_ROLE) {
    Some(r) => Ok((r.start, r.end))
    None =>
      tight_name_range(
        source_text,
        @loomcore.Range::new(binding_start, binding_end),
        def.0,
      )
  }
}

///|
fn binding_rewrite_source(
  source_text : String,
  source_map : SourceMap,
  def : (String, ProjNode[@ast.Term], Int, NodeId),
) -> Result[BindingRewriteSource, String] {
  let (binding_start, binding_end) = match
    get_binding_text_range(source_text, source_map, def) {
    Ok(r) => r
    Err(e) => return Err(e)
  }
  let binding_kind_start = match
    first_non_space_in_range(
      source_text,
      @loomcore.Range::new(binding_start, binding_end),
    ) {
    Some(pos) => pos
    None => binding_start
  }
  let kind = if binding_starts_with_fn(source_text, binding_kind_start) {
    FnBinding
  } else {
    ValueBinding
  }
  Ok({ def, binding_start, binding_end, kind })
}

///|
fn BindingRewriteSource::renamed_text(
  self : BindingRewriteSource,
  source_text : String,
  source_map : SourceMap,
  new_name : String,
) -> Result[String, String] {
  let (name_start, name_end) = match
    binding_name_range(
      source_text,
      source_map,
      self.def,
      self.binding_start,
      self.binding_end,
    ) {
    Ok(r) => r
    Err(e) => return Err(e)
  }
  Ok(
    source_text[self.binding_start:name_start].to_owned() +
    new_name +
    source_text[name_end:self.binding_end].to_owned(),
  )
}

///|
fn trimmed_source_text(source_text : String, range : @loomcore.Range) -> String {
  let start = match first_non_space_in_range(source_text, range) {
    Some(pos) => pos
    None => range.start
  }
  // Mutable end walks backward over trivia without allocating an intermediate slice.
  let mut end = range.end
  // Stateful backward scan is bounded to the source range and stops at content.
  while end > start && is_space_code(source_text[end - 1]) {
    end = end - 1
  }
  source_text[start:end].to_owned()
}

///|
fn find_char_in_range(
  source_text : String,
  needle : UInt16,
  start : Int,
  end : Int,
) -> Int? {
  for pos in start..<end {
    if source_text[pos] == needle {
      return Some(pos)
    }
  }
  None
}

///|
fn range_has_non_space(source_text : String, start : Int, end : Int) -> Bool {
  for pos in start..<end {
    if !is_space_code(source_text[pos]) {
      return true
    }
  }
  false
}

///|
fn matching_right_paren(
  source_text : String,
  open_pos : Int,
  end : Int,
) -> Result[Int, String] {
  // Tiny source scanner state machine: depth tracks nested parens in types.
  let mut depth = 0
  for pos in open_pos..<end {
    if source_text[pos] == '(' {
      depth = depth + 1
    } else if source_text[pos] == ')' {
      depth = depth - 1
      if depth == 0 {
        return Ok(pos)
      }
    }
  }
  Err("Cannot inline fn binding: parameter list end not found")
}

///|
fn fn_binding_inline_text(
  source_text : String,
  binding_start : Int,
  binding_end : Int,
) -> Result[String, String] {
  let param_start = match
    find_char_in_range(source_text, '(', binding_start, binding_end) {
    Some(pos) => pos
    None => return Err("Cannot inline fn binding: parameter list not found")
  }
  let param_end = match
    matching_right_paren(source_text, param_start, binding_end) {
    Ok(pos) => pos + 1
    Err(e) => return Err(e)
  }
  let body_start = match
    first_non_space_in_range(
      source_text,
      @loomcore.Range::new(param_end, binding_end),
    ) {
    Some(pos) => pos
    None => return Err("Cannot inline fn binding: body not found")
  }
  if source_text[body_start] != '{' {
    return Err("Cannot inline fn binding: expected block body")
  }
  let params = source_text[param_start:param_end].to_owned()
  let body = trimmed_source_text(
    source_text,
    @loomcore.Range::new(body_start, binding_end),
  )
  if range_has_non_space(source_text, param_start + 1, param_end - 1) {
    Ok("(" + params + " => " + body + ")")
  } else {
    Ok(body)
  }
}

///|
fn BindingRewriteSource::inline_text(
  self : BindingRewriteSource,
  source_text : String,
  source_map : SourceMap,
) -> Result[String, String] {
  match self.kind {
    FnBinding =>
      fn_binding_inline_text(source_text, self.binding_start, self.binding_end)
    ValueBinding =>
      match source_map.get_range(self.def.1.id()) {
        Some(r) => Ok(trimmed_source_text(source_text, r))
        None => Err("Cannot inline binding: init source range not found")
      }
  }
}

///|
fn binding_inline_text(
  source_text : String,
  source_map : SourceMap,
  def : (String, ProjNode[@ast.Term], Int, NodeId),
) -> Result[String, String] {
  match binding_rewrite_source(source_text, source_map, def) {
    Ok(source) => source.inline_text(source_text, source_map)
    Err(e) => Err(e)
  }
}
