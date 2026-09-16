///|
/// Better Auth owns authentication. This adapter owns HTTP admission and wire
/// encoding; the document store owns storage and revision/receipt semantics.
pub fn document_request(
  request : @http.Request,
  db : @d1.Database,
  owner : String,
  origin : String,
) -> @js_async.Promise[@http.Response] {
  @js_async.Promise::from_async(() => handle_request(request, db, owner, origin))
}

///|
fn error_response(code : String, status : Int) -> @http.Response raise {
  @http.Response::json({ "error": code.to_json() }, status~)
}

///|
async fn handle_request(
  request : @http.Request,
  db : @d1.Database,
  owner : String,
  origin : String,
) -> @http.Response {
  if request.header("X-Loomark-Account") != Some(owner) {
    return error_response("account_changed", 409)
  }
  let path = request.path()
  let verb = request.verb()
  if path == "/api/documents" && verb == "GET" {
    let after = request.query("after")
    if after is Some(cursor) && !@store.valid_identity(cursor) {
      return error_response("invalid_cursor", 400)
    }
    let page = @store.list(db, owner, after)
    let next = match page.next {
      Some(id) => id.to_json()
      None => Json::null()
    }
    return @http.Response::json({
      "documents": page.documents.map(metadata_json).to_json(),
      "next": next,
    })
  }
  guard path.strip_prefix("/api/documents/") is Some(id) &&
    @store.valid_identity(id.to_owned()) else {
    return error_response("not_found", 404)
  }
  let id = id.to_owned()
  if verb == "GET" {
    return match @store.open(db, owner, id) {
      Some(document) => @http.Response::json(document_json(document))
      None => error_response("not_found", 404)
    }
  }
  if verb != "PUT" && verb != "DELETE" {
    return error_response("method_not_allowed", 405)
  }
  if request.header("Origin") != Some(origin) {
    return error_response("origin_not_allowed", 403)
  }
  let content_type = request.header("Content-Type").unwrap_or("")
  if content_type.split(";").next().unwrap_or("").trim() != "application/json" {
    return error_response("json_required", 415)
  }
  let text = request.read_text(max_bytes=MAX_REQUEST_BYTES) catch {
    @http.BodyError::TooLarge =>
      return error_response("document_too_large", 413)
    _ => return error_response("invalid_request", 400)
  }
  let body = @json.parse(text) catch {
    _ => return error_response("invalid_request", 400)
  }
  guard decode_mutation(body, deleting=verb == "DELETE") is Some(mutation) else {
    return error_response("invalid_request", 400)
  }
  if mutation.text is Some(text) && @utf8.encode(text).length() > MAX_TEXT_BYTES {
    return error_response("document_too_large", 413)
  }
  match @store.commit(db, owner, id, mutation) {
    Saved(revision~) =>
      @http.Response::json({
        "id": id.to_json(),
        "operationId": mutation.operation_id.to_json(),
        "revision": revision.to_json(),
      })
    Conflict => error_response("revision_conflict", 409)
    OperationReused => error_response("operation_id_reused", 422)
  }
}
