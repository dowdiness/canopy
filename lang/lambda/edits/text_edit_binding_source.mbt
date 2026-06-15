///|
priv enum BindingRewriteKind {
  ValueBinding
  FnBinding(
    param_list~ : @loomcore.Range,
    body~ : @loomcore.Range,
    has_params~ : Bool
  )
}

///|
/// Source-owned metadata for binding rewrites.
///
/// Lambda projection intentionally stores function definitions as desugared
/// Lam spines, so parameter type annotations and `fn` block shape do not live
/// in `def.init.kind`. Binding-level edits that duplicate, rename, or inline a
/// source binding must go through this bounded source metadata layer instead
/// of reprinting the projected Term. If the source spans cannot be recovered,
/// reject the edit rather than falling back to a lossy `@ast.print_term` rewrite.
priv struct BindingRewriteSource {
  def : EditModuleBinding
  binding_start : Int
  binding_end : Int
  kind : BindingRewriteKind
}

///|
fn binding_name_range(
  source_text : String,
  source_map : SourceMap,
  def : EditModuleBinding,
  binding_start : Int,
  binding_end : Int,
) -> Result[(Int, Int), String] {
  match
    source_map.get_token_span(def.binding_id, @lambda_proj.LET_DEF_NAME_ROLE) {
    Some(r) => Ok((r.start, r.end))
    None =>
      tight_name_range(
        source_text,
        @loomcore.Range::new(binding_start, binding_end),
        def.name,
      )
  }
}

///|
fn binding_structured_role_range(
  source_map : SourceMap,
  def : EditModuleBinding,
  role : String,
  binding_start : Int,
  binding_end : Int,
  label : String,
) -> Result[@loomcore.Range, String] {
  match source_map.get_token_span(def.binding_id, role) {
    Some(range) =>
      if binding_start <= range.start &&
        range.start <= range.end &&
        range.end <= binding_end {
        Ok(range)
      } else {
        Err("Cannot rewrite fn binding: " + label + " range out of binding")
      }
    None => Err("Cannot rewrite fn binding: " + label + " range not found")
  }
}

///|
fn binding_has_fn_params(
  source_map : SourceMap,
  def : EditModuleBinding,
) -> Bool {
  source_map.get_token_span(
    def.binding_id,
    @lambda_proj.FN_BINDING_PARAM_NAME_ROLE,
  )
  is Some(_)
}

///|
fn binding_has_synthetic_fn_params(def : EditModuleBinding) -> Bool {
  def.init.kind is @ast.Term::Lam(_, _)
}

///|
/// Detects the desugared-Lam shape that only `fn` bindings produce: the outer
/// Lam starts at the binding boundary instead of at a value initializer. This
/// is only a rejection guard for missing structured roles, not a source scanner.
fn binding_requires_fn_metadata(def : EditModuleBinding) -> Bool {
  binding_has_synthetic_fn_params(def) &&
  def.binding_id != def.init.id() &&
  def.init.start == def.start
}

///|
fn binding_rewrite_source(
  source_text : String,
  source_map : SourceMap,
  def : EditModuleBinding,
) -> Result[BindingRewriteSource, String] {
  let (binding_start, binding_end) = match
    get_binding_text_range(source_text, source_map, def) {
    Ok(r) => r
    Err(e) => return Err(e)
  }
  let kind = match
    source_map.get_token_span(
      def.binding_id,
      @lambda_proj.FN_BINDING_KEYWORD_ROLE,
    ) {
    Some(_) => {
      let param_list = match
        binding_structured_role_range(
          source_map,
          def,
          @lambda_proj.FN_BINDING_PARAM_LIST_ROLE,
          binding_start,
          binding_end,
          "parameter list",
        ) {
        Ok(range) => range
        Err(e) => return Err(e)
      }
      let body = match
        binding_structured_role_range(
          source_map,
          def,
          @lambda_proj.FN_BINDING_BODY_ROLE,
          binding_start,
          binding_end,
          "body",
        ) {
        Ok(range) => range
        Err(e) => return Err(e)
      }
      FnBinding(
        param_list~,
        body~,
        has_params=binding_has_fn_params(source_map, def),
      )
    }
    None =>
      if binding_requires_fn_metadata(def) {
        return Err("Cannot rewrite fn binding: keyword range not found")
      } else {
        ValueBinding
      }
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
fn fn_binding_inline_text(
  source_text : String,
  param_list : @loomcore.Range,
  body_range : @loomcore.Range,
  has_params : Bool,
) -> Result[String, String] {
  let params = source_text[param_list.start:param_list.end].to_owned()
  let body = trimmed_source_text(source_text, body_range)
  if has_params {
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
    FnBinding(param_list~, body~, has_params~) =>
      fn_binding_inline_text(source_text, param_list, body, has_params)
    ValueBinding =>
      match source_map.get_range(self.def.init.id()) {
        Some(r) => Ok(trimmed_source_text(source_text, r))
        None => Err("Cannot inline binding: init source range not found")
      }
  }
}

///|
fn binding_inline_text(
  source_text : String,
  source_map : SourceMap,
  def : EditModuleBinding,
) -> Result[String, String] {
  match binding_rewrite_source(source_text, source_map, def) {
    Ok(source) => source.inline_text(source_text, source_map)
    Err(e) => Err(e)
  }
}
