///|
let gemini_base_url : String = "https://generativelanguage.googleapis.com/v1beta/models/"

///|
fn text_part(text : String) -> Json {
  Json::object({ "text": text.to_json() })
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
    "Content-Type": "application/json".to_json(),
    "x-goog-api-key": config.api_key.to_json(),
  }).stringify()
}

///|
fn build_gemini_body(
  config : GeminiConfig,
  system_prompt~ : String,
  user_text~ : String,
) -> String {
  let body : Map[String, Json] = {}
  body["contents"] = [
    Json::object({
      "role": "user".to_json(),
      "parts": [text_part(user_text)].to_json(),
    }),
  ].to_json()
  body["systemInstruction"] = Json::object({
    "parts": [text_part(system_prompt)].to_json(),
  })
  body["generationConfig"] = Json::object({
    "temperature": config.temperature.to_json(),
    "maxOutputTokens": config.max_output_tokens.to_json(),
    "responseMimeType": "application/json".to_json(),
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
