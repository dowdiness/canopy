///|
/// Call Gemini to fix typos. Empty array = no corrections needed (valid).
/// Raises LlmError only on HTTP/API/parse failures.
pub async fn fix_typos(
  config : GeminiConfig,
  text : String,
) -> Array[EditAction] raise LlmError {
  let url = build_gemini_url(config)
  let headers = build_gemini_headers(config)
  let body = build_gemini_body(
    config,
    system_prompt=typo_correction_system_prompt,
    user_text=text,
  )
  let response = js_fetch(url, "POST", headers, body).wait() catch {
    err => raise LlmError(err.to_string())
  }
  let content = extract_gemini_text(response)
  parse_edit_actions(content)
}

///|
/// Call Gemini to apply a natural language edit instruction. Empty array = no changes.
/// Raises LlmError only on HTTP/API/parse failures.
pub async fn edit_text(
  config : GeminiConfig,
  text : String,
  instruction : String,
) -> Array[EditAction] raise LlmError {
  let url = build_gemini_url(config)
  let headers = build_gemini_headers(config)
  let user_msg = format_edit_user_message(text, instruction)
  let body = build_gemini_body(
    config,
    system_prompt=structured_edit_system_prompt,
    user_text=user_msg,
  )
  let response = js_fetch(url, "POST", headers, body).wait() catch {
    err => raise LlmError(err.to_string())
  }
  let content = extract_gemini_text(response)
  parse_edit_actions(content)
}
