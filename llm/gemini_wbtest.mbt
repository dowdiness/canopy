///|
test "build_gemini_url has no api key" {
  let cfg = GeminiConfig::new(api_key="test-key-123")
  let url = build_gemini_url(cfg)
  // API key must NOT appear in URL — it goes in x-goog-api-key header
  inspect(
    url,
    content="https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent",
  )
}

///|
test "build_gemini_url with custom model" {
  let cfg = GeminiConfig::new(api_key="k", model="gemini-2.0-flash")
  let url = build_gemini_url(cfg)
  inspect(
    url,
    content="https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent",
  )
}

///|
test "build_gemini_headers contains api key" {
  let cfg = GeminiConfig::new(api_key="test-key-123")
  let headers = build_gemini_headers(cfg)
  assert_true(headers.contains("x-goog-api-key"))
  assert_true(headers.contains("test-key-123"))
}

///|
test "build_gemini_body contains system instruction" {
  let cfg = GeminiConfig::new(api_key="k")
  let body = build_gemini_body(
    cfg,
    system_prompt="You are helpful.",
    user_text="Hello",
  )
  let json = @json.parse(body) catch { _ => fail("expected valid JSON") }
  guard json is Object(obj) else { fail("expected object") }
  guard obj.get("systemInstruction") is Some(Object(si)) else {
    fail("missing systemInstruction")
  }
  guard si.get("parts") is Some(Array(parts)) else { fail("missing parts") }
  guard parts[0] is Object(part) else { fail("missing part") }
  guard part.get("text") is Some(String(text)) else { fail("missing text") }
  inspect(text, content="You are helpful.")
}

///|
test "build_gemini_body contains user text" {
  let cfg = GeminiConfig::new(api_key="k")
  let body = build_gemini_body(cfg, system_prompt="sys", user_text="Fix this")
  let json = @json.parse(body) catch { _ => fail("expected valid JSON") }
  guard json is Object(obj) else { fail("expected object") }
  guard obj.get("contents") is Some(Array(contents)) else {
    fail("missing contents")
  }
  guard contents[0] is Object(content) else { fail("missing content") }
  guard content.get("parts") is Some(Array(parts)) else {
    fail("missing parts")
  }
  guard parts[0] is Object(part) else { fail("missing part") }
  guard part.get("text") is Some(String(text)) else { fail("missing text") }
  inspect(text, content="Fix this")
}

///|
test "build_gemini_body has JSON response mime type" {
  let cfg = GeminiConfig::new(api_key="k")
  let body = build_gemini_body(cfg, system_prompt="sys", user_text="test")
  let json = @json.parse(body) catch { _ => fail("expected valid JSON") }
  guard json is Object(obj) else { fail("expected object") }
  guard obj.get("generationConfig") is Some(Object(gc)) else {
    fail("missing generationConfig")
  }
  guard gc.get("responseMimeType") is Some(String(mime)) else {
    fail("missing responseMimeType")
  }
  inspect(mime, content="application/json")
}

///|
test "extract_gemini_text from response JSON" {
  let response =
    #|{"candidates":[{"content":{"parts":[{"text":"{\"fixed\":\"hello\"}"}]}}]}
  let text = extract_gemini_text(response) catch {
    _ => fail("expected Gemini text")
  }
  inspect(text, content="{\"fixed\":\"hello\"}")
}

///|
test "extract_gemini_text empty candidates raises error" {
  let response =
    #|{"candidates":[]}
  let result : Result[String, LlmError] = Ok(extract_gemini_text(response)) catch {
    err => Err(err)
  }
  assert_true(result is Err(_))
}

///|
test "extract_gemini_text surfaces Gemini API error" {
  let response =
    #|{"error":{"message":"API key not valid","code":400}}
  let result : Result[String, LlmError] = Ok(extract_gemini_text(response)) catch {
    err => Err(err)
  }
  inspect(
    result,
    content="Err(LlmError(\"Gemini API error: API key not valid\"))",
  )
}
