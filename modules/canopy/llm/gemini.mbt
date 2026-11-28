///|
let gemini_base_url : String = "https://generativelanguage.googleapis.com/v1beta/models/"

///|
fn text_part(text : String) -> Json {
  Json::object({ "text": Json(text) })
}

///|
/// URL without API key — key goes in x-goog-api-key header instead of query
/// param to avoid leaking into browser history, logs, and referrer headers.
fn build_gemini_url(config : GeminiConfig) -> String {
  gemini_base_url + config.model + ":generateContent"
}

///|
fn build_gemini_headers(config : GeminiConfig) -> String {
  Json::object({
    "Content-Type": Json("application/json"),
    "x-goog-api-key": Json(config.api_key),
  }).stringify()
}

///|
fn build_gemini_body(
  config : GeminiConfig,
  system_prompt~ : String,
  user_text~ : String,
) -> String {
  let body : Map[String, Json] = Map([])
  body["contents"] = Json([
    Json::object({ "role": Json("user"), "parts": Json([text_part(user_text)]) }),
  ])
  body["systemInstruction"] = Json::object({
    "parts": Json([text_part(system_prompt)]),
  })
  body["generationConfig"] = Json::object({
    "temperature": Json(config.temperature),
    "maxOutputTokens": Json(config.max_output_tokens),
    "responseMimeType": Json("application/json"),
  })
  Json::object(body).stringify()
}

///|
fn extract_gemini_text(response_json : String) -> String raise LlmError {
  let json = @json.parse(response_json) catch {
    _ => raise LlmError("Failed to parse Gemini response as JSON")
  }
  guard json is Object(obj) else {
    raise LlmError("Gemini response is not a JSON object")
  }
  if obj.get("error") is Some(Object(err)) {
    let msg = match err.get("message") {
      Some(String(message)) => message
      _ => "unknown error"
    }
    raise LlmError("Gemini API error: " + msg)
  }
  guard obj.get("candidates") is Some(Array([Object(candidate), ..])) else {
    raise LlmError("Gemini response has no candidates")
  }
  guard candidate.get("content") is Some(Object(content)) else {
    raise LlmError("Gemini candidate has no content")
  }
  guard content.get("parts") is Some(Array([Object(part), ..])) else {
    raise LlmError("Gemini content has no parts")
  }
  guard part.get("text") is Some(String(text)) else {
    raise LlmError("Gemini part has no text")
  }
  text
}
