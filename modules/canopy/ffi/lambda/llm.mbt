///|
fn result_to_json(
  result : Result[Array[@llm.EditAction], @llm.LlmError],
) -> String {
  match result {
    Ok(actions) =>
      Json::object({ "ok": Json(true), "actions": Json(actions) }).stringify()
    Err(err) =>
      Json::object({ "ok": Json(false), "error": Json(err.to_string()) }).stringify()
  }
}

///|
pub fn canopy_llm_fix_typos(
  text : String,
  api_key : String,
) -> @js_async.Promise[String] {
  let config = @llm.GeminiConfig(api_key~)
  @js_async.Promise::from_async(async fn() {
    let result : Result[Array[@llm.EditAction], @llm.LlmError] = Ok(
      @llm.fix_typos(config, text),
    ) catch {
      err => Err(err)
    }
    result_to_json(result)
  })
}

///|
pub fn canopy_llm_edit(
  text : String,
  instruction : String,
  api_key : String,
) -> @js_async.Promise[String] {
  let config = @llm.GeminiConfig(api_key~)
  @js_async.Promise::from_async(async fn() {
    let result : Result[Array[@llm.EditAction], @llm.LlmError] = Ok(
      @llm.edit_text(config, text, instruction),
    ) catch {
      err => Err(err)
    }
    result_to_json(result)
  })
}
