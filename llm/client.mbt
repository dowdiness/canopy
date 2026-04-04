///|
let content_type_json : String = "{\"Content-Type\":\"application/json\"}"

///|
pub async fn fix_typos(
  config : GeminiConfig,
  text : String,
) -> Array[EditAction] raise LlmError {
  let url = build_gemini_url(config)
  let body = build_gemini_body(
    config,
    system_prompt=typo_correction_system_prompt,
    user_text=text,
  )
  let response = js_fetch(url, "POST", content_type_json, body).wait() catch {
    err => raise LlmError(err.to_string())
  }
  let content = extract_gemini_text(response)
  let actions = parse_edit_actions(content)
  if actions.is_empty() {
    raise LlmError("No edit actions parsed from Gemini response")
  }
  actions
}

///|
pub async fn edit_text(
  config : GeminiConfig,
  text : String,
  instruction : String,
) -> Array[EditAction] raise LlmError {
  let url = build_gemini_url(config)
  let user_msg = format_edit_user_message(text, instruction)
  let body = build_gemini_body(
    config,
    system_prompt=structured_edit_system_prompt,
    user_text=user_msg,
  )
  let response = js_fetch(url, "POST", content_type_json, body).wait() catch {
    err => raise LlmError(err.to_string())
  }
  let content = extract_gemini_text(response)
  let actions = parse_edit_actions(content)
  if actions.is_empty() {
    raise LlmError("No edit actions parsed from Gemini response")
  }
  actions
}
