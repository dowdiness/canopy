///|
#derive(Debug, Eq)
pub(all) enum EditAction {
  Replace(line~ : Int32, old~ : String, new~ : String)
  Insert(line~ : Int32, text~ : String)
  Delete(line~ : Int32)
  FixTypos(original~ : String, fixed~ : String)
}

///|
pub impl Show for EditAction with fn output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
/// Manual ToJson: uses object-based wire format matching Gemini API response format.
/// One JSON schema flows end-to-end (Gemini -> MoonBit -> TypeScript).
pub impl ToJson for EditAction with fn to_json(self) -> Json {
  match self {
    FixTypos(original~, fixed~) =>
      Json::object({
        "action": Json("fix_typos"),
        "original": Json(original),
        "fixed": Json(fixed),
      })
    Replace(line~, old~, new~) =>
      Json::object({
        "action": Json("replace"),
        "line": Json(line),
        "old": Json(old),
        "new": Json(new),
      })
    Insert(line~, text~) =>
      Json::object({
        "action": Json("insert"),
        "line": Json(line),
        "text": Json(text),
      })
    Delete(line~) =>
      Json::object({ "action": Json("delete"), "line": Json(line) })
  }
}

///|
#derive(Debug, Eq)
pub(all) enum Role {
  System
  User
  Assistant
}

///|
pub impl Show for Role with fn output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
#derive(Debug, Eq)
pub(all) struct Message {
  role : Role
  content : String
}

///|
pub fn Message::Message(role~ : Role, content~ : String) -> Message {
  { role, content, }
}

///|
#derive(Debug)
pub(all) struct GeminiConfig {
  api_key : String
  model : String
  temperature : Double
  max_output_tokens : Int32
}

///|
pub fn GeminiConfig::GeminiConfig(
  api_key~ : String,
  model~ : String = "gemini-2.5-flash",
  temperature~ : Double = 0.2,
  max_output_tokens~ : Int32 = 1024,
) -> GeminiConfig {
  { api_key, model, temperature, max_output_tokens, }
}

///|
/// Error type for LLM operations (HTTP errors, parse errors, API errors).
#derive(Debug)
pub suberror LlmError {
  LlmError(String)
}

///|
pub impl Show for LlmError with fn output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
pub extend EditAction with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend EditAction with Eq::{equal, not_equal}

///|
pub extend EditAction with Show::{output, to_string}

///|
pub extend EditAction with ToJson::{to_json}

///|
pub extend GeminiConfig with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend LlmError with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend LlmError with Show::{output, to_string}

///|
pub extend Message with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend Message with Eq::{equal, not_equal}

///|
pub extend Role with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend Role with Eq::{equal, not_equal}

///|
pub extend Role with Show::{output, to_string}
