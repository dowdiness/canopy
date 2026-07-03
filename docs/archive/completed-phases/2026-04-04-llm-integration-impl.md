# LLM Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Integrate Gemini LLM API calls into the canopy web app for AI-powered typo correction and structured text editing.

**Architecture:** MoonBit `llm/` package handles prompt construction, JSON parsing, and response→EditAction conversion. Browser `fetch()` called via `extern "js" fn` returning `@js_async.Promise[String]`. FFI exports use `Promise::from_async()` to return JS Promises to TypeScript. Minimal memo editor UI in `examples/web/`.

**Tech Stack:** MoonBit (JS target), `moonbitlang/async` (js_async), Gemini REST API, Vite, TypeScript

**Design spec:** [docs/plans/2026-04-04-llm-integration-design.md](2026-04-04-llm-integration-design.md)

---

## File Map

| File | Responsibility |
|------|---------------|
| `llm/moon.pkg` | Package config: imports `moonbitlang/async/js_async`, `moonbitlang/core/json` |
| `llm/types.mbt` | `EditAction`, `Role`, `Message`, `GeminiConfig` types |
| `llm/fetch_ffi.mbt` | `extern "js" fn js_fetch()` returning `@js_async.Promise[String]` |
| `llm/gemini.mbt` | Gemini request builder (URL + JSON body) and response text extractor |
| `llm/prompt.mbt` | System prompts for typo correction and structured edits |
| `llm/parse.mbt` | JSON response string → `Array[EditAction]` parser |
| `llm/types_test.mbt` | Tests for EditAction JSON round-trip and parsing |
| `llm/parse_test.mbt` | Tests for Gemini response parsing |
| `ffi/canopy_llm.mbt` | FFI exports: `canopy_llm_fix_typos`, `canopy_llm_edit` |
| `examples/web/memo.html` | Memo editor HTML page |
| `examples/web/src/memo-editor.ts` | TypeScript: textarea, toolbar, API key input, fetch glue |

---

### Task 0: Async FFI compile spike

Prove that `moonbitlang/async/js_async` works with our JS target before building on it.

**Files:**
- Modify: `moon.mod.json`
- Create: `llm/moon.pkg`
- Create: `llm/spike.mbt` (temporary, deleted after verification)

- [ ] **Step 1: Add `moonbitlang/async` dependency to `moon.mod.json`**

```json
"deps": {
    "moonbitlang/quickcheck": "0.11.2",
    "moonbitlang/async": "0.16.8",
    "dowdiness/event-graph-walker": {
```

- [ ] **Step 2: Install**

Run:
```bash
moon update && moon install
```

- [ ] **Step 3: Create minimal `llm/moon.pkg`**

```
import {
  "moonbitlang/async/js_async" @js_async,
  "moonbitlang/core/json",
}

options(
  targets: {
    "spike.mbt": ["js"],
    "fetch_ffi.mbt": ["js"],
  },
)
```

- [ ] **Step 4: Create compile spike `llm/spike.mbt`**

```moonbit
///|
/// Minimal compile check: extern "js" fn returning Promise[String],
/// async fn awaiting it, and Promise::from_async exporting it.
extern "js" fn spike_fetch() -> @js_async.Promise[String] =
  #| () => Promise.resolve("ok")

///|
async fn spike_await() -> String {
  spike_fetch().wait()
}

///|
pub fn spike_export() -> @js_async.Promise[String] {
  @js_async.Promise::from_async(spike_await)
}
```

- [ ] **Step 5: Compile for JS target**

Run:
```bash
moon check && moon build --target js
```
Expected: No errors. This proves `Promise[X]`, `.wait()`, and `Promise::from_async()` all work with our JS target.

- [ ] **Step 6: Delete spike file**

```bash
rm llm/spike.mbt
```

Remove the `"spike.mbt": ["js"],` line from `llm/moon.pkg`.

- [ ] **Step 7: Commit**

```bash
git add moon.mod.json llm/moon.pkg
git commit -m "chore: add moonbitlang/async dependency, verify js_async compile spike"
```

---

### Task 1: Core types with manual ToJson

**Files:**
- Create: `llm/types.mbt`
- Create: `llm/types_test.mbt`

`moon.pkg` was already created in Task 0.

- [ ] **Step 1: Write the types test (TDD)**

Create `llm/types_test.mbt`:

```moonbit
///|
test "EditAction::FixTypos show" {
  let action : @llm.EditAction = FixTypos(original="teh", fixed="the")
  inspect!(action, content="FixTypos(original=\"teh\", fixed=\"the\")")
}

///|
test "EditAction::Replace show" {
  let action : @llm.EditAction = Replace(line=3, old="hello", new="world")
  inspect!(action, content="Replace(line=3, old=\"hello\", new=\"world\")")
}

///|
test "EditAction::Insert show" {
  let action : @llm.EditAction = Insert(line=5, text="new line")
  inspect!(action, content="Insert(line=5, text=\"new line\")")
}

///|
test "EditAction::Delete show" {
  let action : @llm.EditAction = Delete(line=2)
  inspect!(action, content="Delete(line=2)")
}

///|
test "EditAction equality" {
  let a : @llm.EditAction = FixTypos(original="teh", fixed="the")
  let b : @llm.EditAction = FixTypos(original="teh", fixed="the")
  let c : @llm.EditAction = FixTypos(original="teh", fixed="thee")
  assert_eq!(a, b)
  assert_not_eq!(a, c)
}

///|
test "Role show" {
  inspect!(@llm.Role::System, content="System")
  inspect!(@llm.Role::User, content="User")
  inspect!(@llm.Role::Assistant, content="Assistant")
}

///|
test "Message construction" {
  let msg = @llm.Message(role=User, content="hello")
  inspect!(msg.role, content="User")
  inspect!(msg.content, content="hello")
}

///|
test "GeminiConfig defaults" {
  let cfg = @llm.GeminiConfig(api_key="test-key")
  inspect!(cfg.model, content="gemini-2.5-flash")
  inspect!(cfg.max_output_tokens, content="1024")
}

///|
test "EditAction::FixTypos to_json uses object format" {
  let action : @llm.EditAction = FixTypos(original="teh", fixed="the")
  let json = action.to_json().stringify()
  // Must use object-based wire format, not derive-based array format
  assert_true!(json.contains("\"action\""))
  assert_true!(json.contains("\"fix_typos\""))
}

///|
test "EditAction::Replace to_json" {
  let action : @llm.EditAction = Replace(line=3, old="hello", new="world")
  let json = action.to_json().stringify()
  assert_true!(json.contains("\"action\""))
  assert_true!(json.contains("\"replace\""))
  assert_true!(json.contains("\"line\""))
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
moon test -p dowdiness/canopy/llm
```
Expected: FAIL — `@llm` package types don't exist yet.

- [ ] **Step 3: Create `llm/types.mbt`**

```moonbit
///|
pub(all) enum EditAction {
  Replace(line~ : Int, old~ : String, new~ : String)
  Insert(line~ : Int, text~ : String)
  Delete(line~ : Int)
  FixTypos(original~ : String, fixed~ : String)
} derive(Show, Eq)

///|
/// Manual ToJson: uses the same object-based format as the Gemini API response.
/// This ensures one JSON schema flows end-to-end (Gemini → MoonBit → TypeScript).
pub impl ToJson for EditAction with to_json(self) -> Json {
  match self {
    FixTypos(original~, fixed~) =>
      Json::object({
        "action": "fix_typos".to_json(),
        "original": original.to_json(),
        "fixed": fixed.to_json(),
      })
    Replace(line~, old~, new~) =>
      Json::object({
        "action": "replace".to_json(),
        "line": line.to_json(),
        "old": old.to_json(),
        "new": new.to_json(),
      })
    Insert(line~, text~) =>
      Json::object({
        "action": "insert".to_json(),
        "line": line.to_json(),
        "text": text.to_json(),
      })
    Delete(line~) =>
      Json::object({
        "action": "delete".to_json(),
        "line": line.to_json(),
      })
  }
}

///|
pub(all) enum Role {
  System
  User
  Assistant
} derive(Show, Eq)

///|
pub(all) struct Message {
  role : Role
  content : String

  fn new(role~ : Role, content~ : String) -> Message
} derive(Show, Eq)

///|
pub fn Message::new(role~ : Role, content~ : String) -> Message {
  { role, content }
}

///|
pub(all) struct GeminiConfig {
  api_key : String
  model : String
  temperature : Double
  max_output_tokens : Int

  fn new(
    api_key~ : String,
    model~ : String = "gemini-2.5-flash",
    temperature~ : Double = 0.2,
    max_output_tokens~ : Int = 1024,
  ) -> GeminiConfig
} derive(Show)

///|
/// Error type for LLM operations (HTTP errors, parse errors, API errors).
pub suberror LlmError {
  LlmError(String)
} derive(Show)

///|
pub fn GeminiConfig::new(
  api_key~ : String,
  model~ : String = "gemini-2.5-flash",
  temperature~ : Double = 0.2,
  max_output_tokens~ : Int = 1024,
) -> GeminiConfig {
  { api_key, model, temperature, max_output_tokens }
}
```

Note: Custom constructors are declared inside the struct body (`fn new(...)`) per codebase convention. This enables `Message(role=User, content="hello")` and `GeminiConfig(api_key="k")` construction syntax.

- [ ] **Step 5: Create stub `llm/fetch_ffi.mbt`**

This file is JS-target-only (configured in `moon.pkg`). Create it empty for now so the package compiles:

```moonbit
// fetch FFI — JS target only. Implementation in Task 3.
```

- [ ] **Step 6: Run tests**

Run:
```bash
moon check && moon test -p dowdiness/canopy/llm
```
Expected: All 7 tests pass. Run `moon test --update` if snapshot content needs updating, then verify with `moon test`.

- [ ] **Step 7: Format and commit**

```bash
moon info && moon fmt
git add llm/
git commit -m "feat(llm): add core types — EditAction, Role, Message, GeminiConfig"
```

---

### Task 2: Implement fetch FFI

**Files:**
- Modify: `llm/fetch_ffi.mbt`

- [ ] **Step 1: Implement js_fetch**

Replace the stub in `llm/fetch_ffi.mbt`:

```moonbit
///|
/// Call browser `fetch()` and return the response body as text.
/// Rejects the promise with an error message if HTTP status is not ok (2xx).
/// `headers_json` is a JSON object string, e.g. `{"Content-Type": "application/json"}`.
extern "js" fn js_fetch(
  url : String,
  method : String,
  headers_json : String,
  body : String,
) -> @js_async.Promise[String] =
  #| (url, method, headersJson, body) => {
  #|   return fetch(url, {
  #|     method,
  #|     headers: JSON.parse(headersJson),
  #|     body: body || undefined,
  #|   }).then(async r => {
  #|     const text = await r.text();
  #|     if (!r.ok) throw new Error(`HTTP ${r.status}: ${text.slice(0, 200)}`);
  #|     return text;
  #|   })
  #| }
```

Note: No `pub` — only called from `client.mbt` within the same package. HTTP errors now reject the Promise, which surfaces as a `JsError` in MoonBit via `Promise::wait()`.

- [ ] **Step 2: Verify it compiles**

Run:
```bash
moon check
```
Expected: No errors.

- [ ] **Step 3: Commit**

```bash
moon info && moon fmt
git add llm/fetch_ffi.mbt
git commit -m "feat(llm): add fetch FFI for browser HTTP calls"
```

---

### Task 3: Implement Gemini request builder

**Files:**
- Create: `llm/gemini.mbt`
- Create: `llm/gemini_wbtest.mbt`

- [ ] **Step 1: Write the test**

Create `llm/gemini_wbtest.mbt`:

```moonbit
///|
test "build_gemini_url" {
  let cfg = GeminiConfig::new(api_key="test-key-123")
  let url = build_gemini_url(cfg)
  inspect!(
    url,
    content="https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=test-key-123",
  )
}

///|
test "build_gemini_url with custom model" {
  let cfg = GeminiConfig::new(api_key="k", model="gemini-2.0-flash")
  let url = build_gemini_url(cfg)
  inspect!(
    url,
    content="https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=k",
  )
}

///|
test "build_gemini_body contains system instruction" {
  let cfg = GeminiConfig::new(api_key="k")
  let body = build_gemini_body(cfg, system_prompt="You are helpful.", user_text="Hello")
  let json = @json.parse!(body)
  // Check systemInstruction exists
  guard json is Object(obj) else { fail!("expected object") }
  guard obj.get("systemInstruction") is Some(Object(si)) else {
    fail!("missing systemInstruction")
  }
  guard si.get("parts") is Some(Array(parts)) else { fail!("missing parts") }
  guard parts[0] is Object(part) else { fail!("missing part") }
  guard part.get("text") is Some(String(text)) else { fail!("missing text") }
  inspect!(text, content="You are helpful.")
}

///|
test "build_gemini_body contains user text" {
  let cfg = GeminiConfig::new(api_key="k")
  let body = build_gemini_body(cfg, system_prompt="sys", user_text="Fix this")
  let json = @json.parse!(body)
  guard json is Object(obj) else { fail!("expected object") }
  guard obj.get("contents") is Some(Array(contents)) else {
    fail!("missing contents")
  }
  guard contents[0] is Object(content) else { fail!("missing content") }
  guard content.get("parts") is Some(Array(parts)) else {
    fail!("missing parts")
  }
  guard parts[0] is Object(part) else { fail!("missing part") }
  guard part.get("text") is Some(String(text)) else { fail!("missing text") }
  inspect!(text, content="Fix this")
}

///|
test "build_gemini_body has JSON response mime type" {
  let cfg = GeminiConfig::new(api_key="k")
  let body = build_gemini_body(cfg, system_prompt="sys", user_text="test")
  let json = @json.parse!(body)
  guard json is Object(obj) else { fail!("expected object") }
  guard obj.get("generationConfig") is Some(Object(gc)) else {
    fail!("missing generationConfig")
  }
  guard gc.get("responseMimeType") is Some(String(mime)) else {
    fail!("missing responseMimeType")
  }
  inspect!(mime, content="application/json")
}

///|
test "extract_gemini_text from response JSON" {
  let response =
    #|{"candidates":[{"content":{"parts":[{"text":"{\"fixed\":\"hello\"}"}]}}]}
  let text = extract_gemini_text!(response)
  inspect!(text, content="{\"fixed\":\"hello\"}")
}

///|
test "extract_gemini_text empty candidates raises error" {
  let response =
    #|{"candidates":[]}
  let result = try? extract_gemini_text(response)
  assert_true!(result.is_err())
}

///|
test "extract_gemini_text surfaces Gemini API error" {
  let response =
    #|{"error":{"message":"API key not valid","code":400}}
  let result = try? extract_gemini_text(response)
  inspect!(result, content="Err(LlmError(\"Gemini API error: API key not valid\"))")
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
moon test -p dowdiness/canopy/llm
```
Expected: FAIL — functions not defined.

- [ ] **Step 3: Implement `llm/gemini.mbt`**

```moonbit
///|
let gemini_base_url : String = "https://generativelanguage.googleapis.com/v1beta/models/"

///|
/// Build helper: wrap a value in `{"text": value}`.
fn text_part(text : String) -> Json {
  Json::object({"text": text.to_json()})
}

///|
fn build_gemini_url(config : GeminiConfig) -> String {
  gemini_base_url + config.model + ":generateContent?key=" + config.api_key
}

///|
fn build_gemini_body(
  config : GeminiConfig,
  system_prompt~ : String,
  user_text~ : String,
) -> String {
  let body : Map[String, Json] = {}
  body["contents"] = [
    Json::object({"role": "user".to_json(), "parts": [text_part(user_text)].to_json()}),
  ].to_json()
  body["systemInstruction"] = Json::object(
    {"parts": [text_part(system_prompt)].to_json()},
  )
  body["generationConfig"] = Json::object({
    "temperature": config.temperature.to_json(),
    "maxOutputTokens": config.max_output_tokens.to_json(),
    "responseMimeType": "application/json".to_json(),
  })
  Json::object(body).stringify()
}

///|
/// Extract the text content from a Gemini generateContent response JSON string.
/// Returns an error with the Gemini error message if the response indicates failure.
fn extract_gemini_text(response_json : String) -> String!LlmError {
  let json = try {
    @json.parse!(response_json)
  } catch {
    _ => raise LlmError("Failed to parse Gemini response as JSON")
  }
  guard json is Object(obj) else {
    raise LlmError("Gemini response is not a JSON object")
  }
  // Check for Gemini error response
  if obj.get("error") is Some(Object(err)) {
    let msg = match err.get("message") {
      Some(String(m)) => m
      _ => "unknown error"
    }
    raise LlmError("Gemini API error: " + msg)
  }
  // Navigate: candidates[0].content.parts[0].text
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
```

Notes:
- `build_gemini_url`, `build_gemini_body`, `extract_gemini_text` are package-private (no `pub`) — only called from `client.mbt`
- `text_part` helper eliminates duplicate Map construction
- `Map` literal syntax `{"key": value}` instead of `let m = {}; m["key"] = value`
- Pattern matching `[Object(candidate), ..]` instead of `length() > 0` + index access

- [ ] **Step 4: Run tests**

Run:
```bash
moon check && moon test -p dowdiness/canopy/llm
```
Expected: All tests pass. Use `moon test --update` if snapshot content needs updating.

- [ ] **Step 5: Format and commit**

```bash
moon info && moon fmt
git add llm/gemini.mbt llm/gemini_wbtest.mbt
git commit -m "feat(llm): Gemini request builder and response text extractor"
```

---

### Task 4: Implement EditAction JSON parsing

**Files:**
- Create: `llm/parse.mbt`
- Create: `llm/parse_test.mbt`

- [ ] **Step 1: Write the tests**

Create `llm/parse_test.mbt`:

```moonbit
///|
test "parse_fix_typos" {
  let json_str =
    #|{"original": "teh quikc", "fixed": "the quick"}
  let actions = @llm.parse_edit_actions(json_str)
  inspect!(actions.length(), content="1")
  inspect!(
    actions[0],
    content="FixTypos(original=\"teh quikc\", fixed=\"the quick\")",
  )
}

///|
test "parse_replace action" {
  let json_str =
    #|[{"action": "replace", "line": 3, "old": "hello", "new": "world"}]
  let actions = @llm.parse_edit_actions(json_str)
  inspect!(actions.length(), content="1")
  inspect!(
    actions[0],
    content="Replace(line=3, old=\"hello\", new=\"world\")",
  )
}

///|
test "parse_insert action" {
  let json_str =
    #|[{"action": "insert", "line": 5, "text": "new line here"}]
  let actions = @llm.parse_edit_actions(json_str)
  inspect!(actions.length(), content="1")
  inspect!(
    actions[0],
    content="Insert(line=5, text=\"new line here\")",
  )
}

///|
test "parse_delete action" {
  let json_str =
    #|[{"action": "delete", "line": 2}]
  let actions = @llm.parse_edit_actions(json_str)
  inspect!(actions.length(), content="1")
  inspect!(actions[0], content="Delete(line=2)")
}

///|
test "parse_multiple actions" {
  let json_str =
    #|[{"action": "replace", "line": 1, "old": "a", "new": "b"}, {"action": "delete", "line": 3}]
  let actions = @llm.parse_edit_actions(json_str)
  inspect!(actions.length(), content="2")
}

///|
test "parse_empty array" {
  let json_str =
    #|[]
  let actions = @llm.parse_edit_actions(json_str)
  inspect!(actions.length(), content="0")
}

///|
test "parse_malformed json" {
  let json_str = "not json at all"
  let actions = @llm.parse_edit_actions(json_str)
  inspect!(actions.length(), content="0")
}

///|
test "parse_fix_typos with action field" {
  let json_str =
    #|{"action": "fix_typos", "original": "teh", "fixed": "the"}
  let actions = @llm.parse_edit_actions(json_str)
  inspect!(actions.length(), content="1")
  inspect!(
    actions[0],
    content="FixTypos(original=\"teh\", fixed=\"the\")",
  )
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
moon test -p dowdiness/canopy/llm
```
Expected: FAIL — `parse_edit_actions` not defined.

- [ ] **Step 3: Implement `llm/parse.mbt`**

```moonbit
///|
/// Parse a JSON string into an array of EditActions.
///
/// Accepts two formats:
/// 1. Single object with "original" + "fixed" fields → FixTypos
/// 2. JSON array of action objects with "action", "line", etc. fields
///
/// Returns empty array on parse failure or malformed input.
pub fn parse_edit_actions(json_str : String) -> Array[EditAction] {
  let json = try { @json.parse!(json_str) } catch { _ => return [] }
  match json {
    Object(obj) => parse_single_action(obj).to_array()
    Array(arr) => arr.filter_map(fn(item) {
      guard item is Object(obj) else { return None }
      parse_single_action(obj)
    })
    _ => []
  }
}

///|
fn parse_single_action(obj : Map[String, Json]) -> EditAction? {
  // Shorthand: object with "original" + "fixed" → FixTypos
  match (obj.get("original"), obj.get("fixed")) {
    (Some(String(original)), Some(String(fixed))) =>
      return Some(FixTypos(original~, fixed~))
    _ => ()
  }
  // Action-based format
  guard obj.get("action") is Some(String(action_type)) else { return None }
  match action_type {
    "fix_typos" =>
      match (obj.get("original"), obj.get("fixed")) {
        (Some(String(original)), Some(String(fixed))) =>
          Some(FixTypos(original~, fixed~))
        _ => None
      }
    "replace" =>
      match (obj.get("line"), obj.get("old"), obj.get("new")) {
        (Some(Number(line)), Some(String(old)), Some(String(new_text))) =>
          Some(Replace(line=line.to_int(), old~, new=new_text))
        _ => None
      }
    "insert" =>
      match (obj.get("line"), obj.get("text")) {
        (Some(Number(line)), Some(String(text))) =>
          Some(Insert(line=line.to_int(), text~))
        _ => None
      }
    "delete" =>
      match obj.get("line") {
        Some(Number(line)) => Some(Delete(line=line.to_int()))
        _ => None
      }
    _ => None
  }
}
```

Notes:
- `parse_single_action` returns `EditAction?` instead of `Array[EditAction]` — cleaner Option semantics
- Tuple pattern matching `(obj.get("line"), obj.get("old"), obj.get("new"))` instead of sequential `guard` chains
- `filter_map` instead of manual loop with `push`

- [ ] **Step 4: Run tests**

Run:
```bash
moon check && moon test -p dowdiness/canopy/llm
```
Expected: All tests pass. Use `moon test --update` if snapshot content needs updating.

- [ ] **Step 5: Format and commit**

```bash
moon info && moon fmt
git add llm/parse.mbt llm/parse_test.mbt
git commit -m "feat(llm): EditAction JSON parser — supports fix_typos, replace, insert, delete"
```

---

### Task 5: Implement prompt templates

**Files:**
- Create: `llm/prompt.mbt`
- Create: `llm/prompt_wbtest.mbt`

- [ ] **Step 1: Write the tests**

Create `llm/prompt_wbtest.mbt`:

```moonbit
///|
test "typo_correction_system_prompt is non-empty" {
  let prompt = typo_correction_system_prompt
  assert_true!(prompt.length() > 0)
  assert_true!(prompt.contains("JSON"))
}

///|
test "structured_edit_system_prompt is non-empty" {
  let prompt = structured_edit_system_prompt
  assert_true!(prompt.length() > 0)
  assert_true!(prompt.contains("replace"))
}

///|
test "format_edit_user_message includes text and instruction" {
  let msg = format_edit_user_message("line1\nline2\nline3", "Fix line 2")
  assert_true!(msg.contains("line1"))
  assert_true!(msg.contains("line2"))
  assert_true!(msg.contains("Fix line 2"))
  // Should have line numbers
  assert_true!(msg.contains("1:"))
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
moon test -p dowdiness/canopy/llm
```
Expected: FAIL — functions not defined.

- [ ] **Step 3: Implement `llm/prompt.mbt`**

```moonbit
///|
let typo_correction_system_prompt : String =
  #|You are a Japanese/English text proofreader.
  #|Fix typos, misspellings, and grammatical errors in the given text.
  #|Respond ONLY with a JSON object in this exact format:
  #|{"original": "<original text>", "fixed": "<corrected text>"}
  #|Do not explain. Do not add any text outside the JSON.

///|
let structured_edit_system_prompt : String =
  #|You are an editor assistant. The user will provide text content and an editing instruction.
  #|Respond ONLY with a JSON array of edit operations. Each operation is one of:
  #|- {"action": "replace", "line": <1-based line number>, "old": "<text to find on that line>", "new": "<replacement text>"}
  #|- {"action": "insert", "line": <1-based line number>, "text": "<text to insert after this line>"}
  #|- {"action": "delete", "line": <1-based line number>}
  #|If no changes are needed, return an empty array: []
  #|Do not explain. Do not add any text outside the JSON array.

///|
/// Format user text with line numbers for the structured edit prompt.
pub fn format_edit_user_message(text : String, instruction : String) -> String {
  let buf = StringBuilder::new()
  buf..write_string("=== TEXT ===\n")
  let lines = split_lines(text)
  for i, line in lines {
    buf..write_string((i + 1).to_string())..write_string(": ")..write_string(line)..write_string(
      "\n",
    )
  }
  buf..write_string("=== INSTRUCTION ===\n")..write_string(instruction)
  buf.to_string()
}

///|
fn split_lines(text : String) -> Array[String] {
  let result : Array[String] = []
  let buf = StringBuilder::new()
  for ch in text {
    match ch {
      '\n' => {
        result.push(buf.to_string())
        buf.reset()
      }
      _ => buf.write_char(ch)
    }
  }
  // Always push last segment (even if empty, to guarantee at least one line)
  let last = buf.to_string()
  if not(last.is_empty()) || result.is_empty() {
    result.push(last)
  }
  result
}
```

Notes:
- Prompts are package-private (no `pub`) — only used from `client.mbt`
- `..` chaining on StringBuilder for fluent writes
- `result.is_empty()` instead of `result.length() == 0`
- `match ch { '\n' => ... }` instead of `if ch == '\n'`

- [ ] **Step 4: Run tests**

Run:
```bash
moon check && moon test -p dowdiness/canopy/llm
```
Expected: All tests pass. Use `moon test --update` if snapshot content needs updating.

- [ ] **Step 5: Format and commit**

```bash
moon info && moon fmt
git add llm/prompt.mbt llm/prompt_wbtest.mbt
git commit -m "feat(llm): prompt templates for typo correction and structured edits"
```

---

### Task 6: Implement async LLM call functions

**Files:**
- Create: `llm/client.mbt`

These are the async functions that compose fetch FFI + Gemini builder + parser into end-to-end calls.

- [ ] **Step 1: Implement `llm/client.mbt`**

```moonbit
///|
let content_type_json : String = "{\"Content-Type\":\"application/json\"}"

///|
/// Call Gemini API to fix typos in the given text.
/// Returns an array of EditAction, or raises LlmError on failure.
/// JsError from fetch (HTTP errors) is caught and re-raised as LlmError.
pub async fn fix_typos(
  config : GeminiConfig,
  text : String,
) -> Array[EditAction]!LlmError {
  let url = build_gemini_url(config)
  let body = build_gemini_body(
    config,
    system_prompt=typo_correction_system_prompt,
    user_text=text,
  )
  let response = try {
    js_fetch(url, "POST", content_type_json, body).wait()
  } catch {
    err => raise LlmError(err.to_string())
  }
  let content = extract_gemini_text!(response)
  let actions = parse_edit_actions(content)
  if actions.is_empty() {
    raise LlmError("No edit actions parsed from Gemini response")
  }
  actions
}

///|
/// Call Gemini API to apply a natural language edit instruction to the given text.
/// Returns an array of EditAction, or raises LlmError on failure.
pub async fn edit_text(
  config : GeminiConfig,
  text : String,
  instruction : String,
) -> Array[EditAction]!LlmError {
  let url = build_gemini_url(config)
  let user_msg = format_edit_user_message(text, instruction)
  let body = build_gemini_body(
    config,
    system_prompt=structured_edit_system_prompt,
    user_text=user_msg,
  )
  let response = try {
    js_fetch(url, "POST", content_type_json, body).wait()
  } catch {
    err => raise LlmError(err.to_string())
  }
  let content = extract_gemini_text!(response)
  parse_edit_actions(content)
}
```

- [ ] **Step 2: Verify it compiles**

Run:
```bash
moon check
```
Expected: No errors. We can't unit test async functions that call `js_fetch` without a browser, but the types must check out.

- [ ] **Step 3: Format and commit**

```bash
moon info && moon fmt
git add llm/client.mbt
git commit -m "feat(llm): async fix_typos and edit_text functions"
```

---

### Task 7: Add FFI exports

**Files:**
- Create: `ffi/canopy_llm.mbt`
- Modify: `ffi/moon.pkg` (add import)
- Modify: `ffi/moon.pkg` (add exports)

- [ ] **Step 1: Update `ffi/moon.pkg` imports**

Add `dowdiness/canopy/llm` and `moonbitlang/async/js_async` to the import list:

```
import {
  "dowdiness/canopy/editor",
  "dowdiness/canopy/core" @core,
  "dowdiness/canopy/lang/json/edits" @json_edits,
  "dowdiness/canopy/relay",
  "dowdiness/canopy/llm" @llm,
  "dowdiness/json" @djson,
  "dowdiness/lambda/ast" @ast,
  "dowdiness/event-graph-walker/text",
  "moonbitlang/async/js_async" @js_async,
  "moonbitlang/core/buffer",
  "moonbitlang/core/json",
  "moonbitlang/core/string",
}
```

- [ ] **Step 2: Add export names to `ffi/moon.pkg`**

Add these to the `"exports"` array in the `link.js` section:

```
"canopy_llm_fix_typos",
"canopy_llm_edit",
```

- [ ] **Step 3: Create `ffi/canopy_llm.mbt`**

```moonbit
///|
/// Wrap result as JSON: {"ok": true, "actions": [...]} or {"ok": false, "error": "..."}
fn result_to_json(
  result : Array[@llm.EditAction]!@llm.LlmError,
) -> String {
  match result {
    Ok(actions) =>
      Json::object({
        "ok": true.to_json(),
        "actions": actions.to_json(),
      }).stringify()
    Err(err) =>
      Json::object({
        "ok": false.to_json(),
        "error": err.to_string().to_json(),
      }).stringify()
  }
}

///|
/// Fix typos in the given text using Gemini API.
/// Returns a Promise that resolves to JSON: {"ok": true, "actions": [...]} or {"ok": false, "error": "..."}
///
/// Called from TypeScript:
///   const result = JSON.parse(await crdt.canopy_llm_fix_typos(text, apiKey));
///   if (result.ok) { /* use result.actions */ } else { /* show result.error */ }
pub fn canopy_llm_fix_typos(text : String, api_key : String) -> @js_async.Promise[String] {
  let config = @llm.GeminiConfig(api_key~)
  @js_async.Promise::from_async(() => {
    result_to_json(try? @llm.fix_typos(config, text))
  })
}

///|
/// Apply a natural language edit instruction to the given text using Gemini API.
/// Returns a Promise that resolves to JSON: {"ok": true, "actions": [...]} or {"ok": false, "error": "..."}
pub fn canopy_llm_edit(
  text : String,
  instruction : String,
  api_key : String,
) -> @js_async.Promise[String] {
  let config = @llm.GeminiConfig(api_key~)
  @js_async.Promise::from_async(() => {
    result_to_json(try? @llm.edit_text(config, text, instruction))
  })
}
```

- [ ] **Step 4: Verify it compiles and builds**

Run:
```bash
moon check && moon build --target js
```
Expected: No errors. The JS build produces `_build/js/release/build/ffi/ffi.js` with the new exports.

- [ ] **Step 5: Format and commit**

```bash
moon info && moon fmt
git add ffi/canopy_llm.mbt ffi/moon.pkg
git commit -m "feat(ffi): export canopy_llm_fix_typos and canopy_llm_edit"
```

---

### Task 8: Create memo editor HTML page

**Files:**
- Create: `examples/web/memo.html`
- Modify: `examples/web/vite.config.ts` (add entry point)

- [ ] **Step 1: Create `examples/web/memo.html`**

```html
<!DOCTYPE html>
<html lang="ja">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Canopy Memo — AI Editor</title>
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }

    body {
      font-family: 'Inter', 'Helvetica Neue', sans-serif;
      background: #1a1a2e;
      color: #e0e0e0;
      padding: 24px;
    }

    .container {
      max-width: 720px;
      margin: 0 auto;
    }

    h1 {
      color: #8250df;
      font-size: 20px;
      margin-bottom: 6px;
    }

    .subtitle {
      color: #666;
      font-size: 13px;
      margin-bottom: 20px;
    }

    .config-section {
      background: #16213e;
      border: 1px solid #2a2a4a;
      border-radius: 6px;
      padding: 12px 16px;
      margin-bottom: 16px;
      display: flex;
      gap: 8px;
      align-items: center;
    }

    .config-section label {
      color: #888;
      font-size: 12px;
      white-space: nowrap;
    }

    .config-section input {
      flex: 1;
      background: #1a1a2e;
      border: 1px solid #2a2a4a;
      border-radius: 4px;
      color: #e0e0e0;
      padding: 6px 10px;
      font-family: 'JetBrains Mono', monospace;
      font-size: 12px;
    }

    .editor-area {
      background: #16213e;
      border: 1px solid #2a2a4a;
      border-radius: 6px;
      padding: 16px;
      margin-bottom: 16px;
    }

    #memo {
      width: 100%;
      min-height: 200px;
      background: #1a1a2e;
      border: 1px solid #2a2a4a;
      border-radius: 4px;
      color: #e0e0e0;
      padding: 12px;
      font-family: 'JetBrains Mono', monospace;
      font-size: 14px;
      line-height: 1.6;
      resize: vertical;
    }

    #memo:focus { outline: 1px solid #8250df; }

    .toolbar {
      display: flex;
      gap: 8px;
      margin-top: 12px;
      flex-wrap: wrap;
      align-items: center;
    }

    .btn {
      padding: 8px 16px;
      border: none;
      border-radius: 4px;
      cursor: pointer;
      font-family: inherit;
      font-size: 13px;
      transition: background 0.15s;
    }

    .btn:disabled {
      opacity: 0.4;
      cursor: not-allowed;
    }

    .btn-primary {
      background: #8250df;
      color: white;
    }

    .btn-primary:hover:not(:disabled) { background: #9a6fe8; }

    .btn-secondary {
      background: #2a2a4a;
      color: #ccc;
    }

    .btn-secondary:hover:not(:disabled) { background: #3a3a5a; }

    .instruction-row {
      display: flex;
      gap: 8px;
      margin-top: 8px;
    }

    #instruction {
      flex: 1;
      background: #1a1a2e;
      border: 1px solid #2a2a4a;
      border-radius: 4px;
      color: #e0e0e0;
      padding: 6px 10px;
      font-family: inherit;
      font-size: 13px;
    }

    #instruction:focus { outline: 1px solid #8250df; }

    .status-bar {
      font-size: 12px;
      color: #666;
      margin-top: 8px;
      min-height: 18px;
    }

    .status-bar.error { color: #ff5370; }
    .status-bar.success { color: #c3e88d; }

    .diff-section {
      background: #16213e;
      border: 1px solid #2a2a4a;
      border-radius: 6px;
      padding: 16px;
      display: none;
    }

    .diff-section.visible { display: block; }

    .diff-section h2 {
      color: #8250df;
      font-size: 14px;
      margin-bottom: 12px;
    }

    .diff-content {
      display: grid;
      grid-template-columns: 1fr 1fr;
      gap: 12px;
    }

    .diff-pane h3 {
      color: #888;
      font-size: 11px;
      text-transform: uppercase;
      margin-bottom: 6px;
    }

    .diff-pane pre {
      background: #1a1a2e;
      border: 1px solid #2a2a4a;
      border-radius: 4px;
      padding: 10px;
      font-family: 'JetBrains Mono', monospace;
      font-size: 13px;
      line-height: 1.5;
      white-space: pre-wrap;
      word-wrap: break-word;
      max-height: 300px;
      overflow-y: auto;
    }

    .diff-actions {
      margin-top: 12px;
      display: flex;
      gap: 8px;
    }

    @media (max-width: 640px) {
      body { padding: 12px; }
      .diff-content { grid-template-columns: 1fr; }
      .config-section { flex-direction: column; align-items: stretch; }
    }
  </style>
</head>
<body>
  <div class="container">
    <h1>Canopy Memo</h1>
    <p class="subtitle">AI-powered text editor — typo correction &amp; structured edits</p>

    <div class="config-section">
      <label for="api-key">Gemini API Key:</label>
      <input type="password" id="api-key" placeholder="Enter your API key (stored in memory only)">
    </div>

    <div class="editor-area">
      <textarea id="memo" placeholder="Type or paste your text here..."></textarea>

      <div class="toolbar">
        <button id="fix-typos-btn" class="btn btn-primary">Fix Typos</button>
      </div>

      <div class="instruction-row">
        <input type="text" id="instruction" placeholder="Edit instruction (e.g. 3行目をもっと丁寧にして)">
        <button id="edit-btn" class="btn btn-secondary">Edit</button>
      </div>

      <div class="status-bar" id="status"></div>
    </div>

    <div class="diff-section" id="diff-section">
      <h2>Suggested Changes</h2>
      <div class="diff-content">
        <div class="diff-pane">
          <h3>Original</h3>
          <pre id="diff-original"></pre>
        </div>
        <div class="diff-pane">
          <h3>Corrected</h3>
          <pre id="diff-fixed"></pre>
        </div>
      </div>
      <div class="diff-actions">
        <button id="accept-btn" class="btn btn-primary">Accept</button>
        <button id="reject-btn" class="btn btn-secondary">Reject</button>
      </div>
    </div>
  </div>

  <script type="module" src="/src/memo-editor.ts"></script>
</body>
</html>
```

- [ ] **Step 2: Add memo entry point to Vite config**

In `examples/web/vite.config.ts`, add `memo` to `rollupOptions.input`:

```typescript
    rollupOptions: {
      input: {
        main: 'index.html',
        json: 'json.html',
        memo: 'memo.html',
      },
    },
```

- [ ] **Step 3: Verify Vite config is valid**

Run:
```bash
cd examples/web && npx vite build --mode development 2>&1 | head -5
```
Expected: Build starts without config errors (may fail on missing TS file, which is fine — we create it next task).

- [ ] **Step 4: Commit**

```bash
git add examples/web/memo.html examples/web/vite.config.ts
git commit -m "feat(web): add memo editor HTML page"
```

---

### Task 9: Create TypeScript memo editor

**Files:**
- Create: `examples/web/src/memo-editor.ts`

- [ ] **Step 1: Create `examples/web/src/memo-editor.ts`**

```typescript
import * as crdt from '@moonbit/crdt';

// --- DOM elements ---
const memoEl = document.getElementById('memo') as HTMLTextAreaElement;
const apiKeyEl = document.getElementById('api-key') as HTMLInputElement;
const fixTyposBtn = document.getElementById('fix-typos-btn') as HTMLButtonElement;
const editBtn = document.getElementById('edit-btn') as HTMLButtonElement;
const instructionEl = document.getElementById('instruction') as HTMLInputElement;
const statusEl = document.getElementById('status') as HTMLDivElement;
const diffSection = document.getElementById('diff-section') as HTMLDivElement;
const diffOriginal = document.getElementById('diff-original') as HTMLPreElement;
const diffFixed = document.getElementById('diff-fixed') as HTMLPreElement;
const acceptBtn = document.getElementById('accept-btn') as HTMLButtonElement;
const rejectBtn = document.getElementById('reject-btn') as HTMLButtonElement;

// --- State ---
let pendingText: string | null = null;
let lastRequestTime = 0;
const RATE_LIMIT_MS = 5000;
const MAX_INPUT_LENGTH = 5000;

// --- Helpers ---
function setStatus(msg: string, type: '' | 'error' | 'success' = '') {
  statusEl.textContent = msg;
  statusEl.className = `status-bar ${type}`;
}

function setLoading(loading: boolean) {
  fixTyposBtn.disabled = loading;
  editBtn.disabled = loading;
  if (loading) setStatus('Calling Gemini API...');
}

function getApiKey(): string | null {
  const key = apiKeyEl.value.trim();
  if (!key) {
    setStatus('Please enter your Gemini API key.', 'error');
    apiKeyEl.focus();
    return null;
  }
  return key;
}

function checkRateLimit(): boolean {
  const now = Date.now();
  if (now - lastRequestTime < RATE_LIMIT_MS) {
    const wait = Math.ceil((RATE_LIMIT_MS - (now - lastRequestTime)) / 1000);
    setStatus(`Rate limited. Wait ${wait}s.`, 'error');
    return false;
  }
  lastRequestTime = now;
  return true;
}

function getText(): string | null {
  const text = memoEl.value;
  if (!text.trim()) {
    setStatus('Nothing to process — textarea is empty.', 'error');
    return null;
  }
  if (text.length > MAX_INPUT_LENGTH) {
    setStatus(`Text too long (${text.length}/${MAX_INPUT_LENGTH} chars).`, 'error');
    return null;
  }
  return text;
}

function showDiff(original: string, fixed: string) {
  diffOriginal.textContent = original;
  diffFixed.textContent = fixed;
  pendingText = fixed;
  diffSection.classList.add('visible');
}

function hideDiff() {
  diffSection.classList.remove('visible');
  pendingText = null;
}

// --- LLM result handling ---
// MoonBit FFI returns: {"ok": true, "actions": [...]} or {"ok": false, "error": "..."}
interface LlmResult {
  ok: boolean;
  actions?: EditAction[];
  error?: string;
}

// Object-based wire format (matches manual ToJson in MoonBit):
// {"action": "fix_typos", "original": "...", "fixed": "..."}
// {"action": "replace", "line": 3, "old": "...", "new": "..."}
// {"action": "insert", "line": 5, "text": "..."}
// {"action": "delete", "line": 2}
interface EditAction {
  action: string;
  original?: string;
  fixed?: string;
  line?: number;
  old?: string;
  new?: string;
  text?: string;
}

function parseLlmResult(jsonStr: string): LlmResult {
  try {
    return JSON.parse(jsonStr) as LlmResult;
  } catch {
    return { ok: false, error: 'Failed to parse response' };
  }
}

function applyActions(text: string, actions: EditAction[]): { result: string; warnings: string[] } {
  const warnings: string[] = [];
  for (const action of actions) {
    if (action.action === 'fix_typos' && action.fixed) {
      return { result: action.fixed, warnings };
    }
  }
  // Line-based edits: apply in reverse line order to preserve line numbers
  const lines = text.split('\n');
  const lineEdits = actions
    .filter(a => a.action !== 'fix_typos' && a.line !== undefined)
    .sort((a, b) => (b.line ?? 0) - (a.line ?? 0));
  for (const action of lineEdits) {
    const idx = (action.line ?? 0) - 1;
    if (action.action === 'replace') {
      if (idx < 0 || idx >= lines.length) {
        warnings.push(`Line ${action.line} out of range (1-${lines.length})`);
        continue;
      }
      if (action.old && !lines[idx].includes(action.old)) {
        warnings.push(`Line ${action.line}: "${action.old}" not found`);
        continue;
      }
      lines[idx] = lines[idx].replace(action.old!, action.new ?? '');
    } else if (action.action === 'insert') {
      const insertIdx = action.line ?? 0;
      if (insertIdx < 0 || insertIdx > lines.length) {
        warnings.push(`Insert line ${action.line} out of range`);
        continue;
      }
      lines.splice(insertIdx, 0, action.text ?? '');
    } else if (action.action === 'delete') {
      if (idx < 0 || idx >= lines.length) {
        warnings.push(`Delete line ${action.line} out of range`);
        continue;
      }
      lines.splice(idx, 1);
    }
  }
  return { result: lines.join('\n'), warnings };
}

// --- Shared request handler ---
async function callLlm(
  fetchFn: () => Promise<string>,
  originalText: string,
) {
  setLoading(true);
  try {
    const resultJson: string = await fetchFn();
    const result = parseLlmResult(resultJson);
    if (!result.ok) {
      setStatus(`Error: ${result.error}`, 'error');
      return;
    }
    if (!result.actions || result.actions.length === 0) {
      setStatus('No changes suggested.', 'success');
      return;
    }
    const { result: fixed, warnings } = applyActions(originalText, result.actions);
    if (fixed === originalText) {
      setStatus('No changes detected.', 'success');
    } else {
      showDiff(originalText, fixed);
      const msg = warnings.length > 0
        ? `Review changes. Warnings: ${warnings.join('; ')}`
        : 'Review the suggested changes below.';
      setStatus(msg, warnings.length > 0 ? 'error' : 'success');
    }
  } catch (err) {
    setStatus(`Unexpected error: ${err instanceof Error ? err.message : err}`, 'error');
  } finally {
    setLoading(false);
  }
}

// --- Event handlers ---
fixTyposBtn.addEventListener('click', async () => {
  const apiKey = getApiKey();
  if (!apiKey) return;
  const text = getText();
  if (!text) return;
  if (!checkRateLimit()) return;
  await callLlm(() => (crdt as any).canopy_llm_fix_typos(text, apiKey), text);
});

editBtn.addEventListener('click', async () => {
  const apiKey = getApiKey();
  if (!apiKey) return;
  const text = getText();
  if (!text) return;
  const instruction = instructionEl.value.trim();
  if (!instruction) {
    setStatus('Please enter an edit instruction.', 'error');
    instructionEl.focus();
    return;
  }
  if (!checkRateLimit()) return;
  await callLlm(() => (crdt as any).canopy_llm_edit(text, instruction, apiKey), text);
});

acceptBtn.addEventListener('click', () => {
  if (pendingText !== null) {
    memoEl.value = pendingText;
    setStatus('Changes applied.', 'success');
  }
  hideDiff();
});

rejectBtn.addEventListener('click', () => {
  setStatus('Changes rejected.');
  hideDiff();
});

// --- Init ---
setStatus('Ready. Enter your API key and start typing.');
```

- [ ] **Step 2: Build the full web app**

Run:
```bash
cd /home/antisatori/ghq/github.com/dowdiness/canopy && moon build --target js && cd examples/web && npx vite build 2>&1 | tail -10
```
Expected: Build succeeds. All three entry points (main, json, memo) are bundled.

- [ ] **Step 3: Commit**

```bash
git add examples/web/src/memo-editor.ts
git commit -m "feat(web): memo editor TypeScript — API key input, fix typos, structured edits, diff view"
```

---

### Task 10: End-to-end smoke test

This task verifies the full pipeline works in a browser.

**Files:** None (manual verification)

- [ ] **Step 1: Build MoonBit**

Run:
```bash
cd /home/antisatori/ghq/github.com/dowdiness/canopy && moon build --target js
```
Expected: Build succeeds.

- [ ] **Step 2: Start dev server**

Run:
```bash
cd examples/web && npm run dev
```
Expected: Vite dev server starts at `http://localhost:5173/`.

- [ ] **Step 3: Open memo editor**

Open `http://localhost:5173/memo.html` in a browser.

Verify:
- Page loads with title "Canopy Memo"
- Textarea is visible and editable
- API key input field is visible
- "Fix Typos" button is present
- Instruction input and "Edit" button are present

- [ ] **Step 4: Test typo correction (requires API key)**

1. Enter a Gemini API key
2. Type `これは以上な文章です。誤字があるかもしれまsん。` in the textarea
3. Click "Fix Typos"
4. Verify: diff view appears showing original vs corrected text
5. Click "Accept" to apply the fix

- [ ] **Step 5: Test structured edit (requires API key)**

1. Type a 3-line memo in the textarea
2. Enter instruction: `2行目をもっと丁寧にして`
3. Click "Edit"
4. Verify: diff view appears with the edit suggestion

- [ ] **Step 6: Verify defensive measures**

1. Click "Fix Typos" without an API key → should show error
2. Click "Fix Typos" twice quickly → should show rate limit message
3. Paste >5000 characters → should show length error

---

## Verification Checklist

- [ ] `moon check` passes
- [ ] `moon test -p dowdiness/canopy/llm` — all unit tests pass
- [ ] `moon build --target js` — JS build succeeds
- [ ] `examples/web/memo.html` loads in browser
- [ ] Typo correction works end-to-end with real Gemini API key
- [ ] Structured edit works end-to-end
- [ ] Existing lambda and JSON editors still work (`/` and `/json.html`)
