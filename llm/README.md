# llm

Optional, JS-only client for Google's Gemini API. Exposes `fix_typos` and `edit_text` as `async` MoonBit functions that resolve to an `Array[EditAction]`. The editor calls these from the `canopy_llm_*` exports in `ffi/lambda`.

This package is opt-in. The native target builds it as a stub; the actual fetch implementation lives in `fetch_ffi.mbt` and is gated to the `js` target in `moon.pkg`.

## Public API

- `GeminiConfig { api_key, model, temperature, max_output_tokens }` with a `GeminiConfig::GeminiConfig` constructor (defaults for everything except `api_key`)
- `EditAction` — `Replace(line~, old~, new~)`, `Insert(line~, text~)`, `Delete(line~)`, `FixTypos(original~, fixed~)`
- `fix_typos(cfg, text) -> Array[EditAction]` (async, raises `LlmError`)
- `edit_text(cfg, instructions, text) -> Array[EditAction]` (async, raises `LlmError`)
- `parse_edit_actions(s : String) -> Array[EditAction]` — pure parser used by both async paths
- `LlmError(String)` — single-variant error type

## Consumers

`ffi/lambda` (`canopy_llm_fix_typos`, `canopy_llm_edit`). No other package imports `llm`.

## Dependencies

- `moonbitlang/async/js_async` — JS Promise integration
- `moonbitlang/core/json`, `moonbitlang/core/debug`

## Stability

**Unstable — route through `ffi/lambda`.** The prompt shapes and `EditAction` variants are tuned against Gemini's current response format. Swapping providers or model versions may force a breaking change in `EditAction`.

## Notes

`fetch_ffi.mbt` is the only file restricted to the `js` target (`options.targets` in `moon.pkg`); the rest of the package is target-agnostic so MoonBit doc and type-checking still run on native. Whitebox tests in `*_wbtest.mbt` cover the prompt builder and response parser without hitting the network.
