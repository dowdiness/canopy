///|
pub(all) enum EditAction {
  Replace(line~ : Int, old~ : String, new~ : String)
  Insert(line~ : Int, text~ : String)
  Delete(line~ : Int)
  FixTypos(original~ : String, fixed~ : String)
} derive(Show, Eq)

///|
/// Manual ToJson: uses object-based wire format matching Gemini API response format.
/// One JSON schema flows end-to-end (Gemini -> MoonBit -> TypeScript).
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
      Json::object({ "action": "delete".to_json(), "line": line.to_json() })
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
    model? : String,
    temperature? : Double,
    max_output_tokens? : Int,
  ) -> GeminiConfig
} derive(Show)

///|
pub fn GeminiConfig::new(
  api_key~ : String,
  model? : String = "gemini-2.5-flash",
  temperature? : Double = 0.2,
  max_output_tokens? : Int = 1024,
) -> GeminiConfig {
  { api_key, model, temperature, max_output_tokens }
}

///|
/// Error type for LLM operations (HTTP errors, parse errors, API errors).
pub suberror LlmError {
  LlmError(String)
} derive(Show)
