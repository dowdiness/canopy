# LLM API Integration for Memo Editor

**Status:** Design
**Date:** 2026-04-04

## Goal

Integrate LLM API calls into the canopy web app to enable AI-powered editing — starting with typo correction, then generalizing to structured edit operations via `EditAction`.

Design principle: **LLM decides "what to do", the app executes "how to do it"**. LLM output is reified as data (`EditAction` enum), not executed as raw text.

## Architecture

```
User clicks "Fix Typos" in browser
  → TS calls exported FFI function (e.g. canopy_llm_fix_typos)
  → MoonBit returns Promise[String] via Promise::from_async()
  → Inside the async fn:
      → builds Gemini request (url + JSON body)
      → calls extern "js" fn js_fetch() → @js_async.Promise[String]
      → .wait() suspends MoonBit coroutine until fetch resolves
      → parses JSON response → Array[EditAction]
      → returns EditAction array as JSON string
  → TS awaits the Promise, applies edits to textarea
```

## Platform & Dependencies

- **Build target:** `--target js` (existing Vite pipeline)
- **New dependency:** `moonbitlang/async` (for `@js_async.Promise`, `Promise::wait()`, `Promise::from_async()`)
- **Existing:** `moonbitlang/core/json` for JSON parsing/construction
- **No npm dependencies** — uses browser `fetch()` directly via FFI (unlike `tiye/genai` which wraps `@google/genai` npm)

## Core Types

### EditAction

```moonbit
pub(all) enum EditAction {
  Replace(line~ : Int, old~ : String, new~ : String)
  Insert(line~ : Int, text~ : String)
  Delete(line~ : Int)
  FixTypos(original~ : String, fixed~ : String)
} derive(Show, Eq)
```

### LLM Types

```moonbit
pub(all) enum Role {
  System
  User
  Assistant
} derive(Show, Eq)

pub(all) struct Message {
  role : Role
  content : String
} derive(Show)

pub(all) struct GeminiConfig {
  api_key : String
  model : String           // default: "gemini-2.5-flash"
  temperature : Double     // default: 0.2
  max_output_tokens : Int  // default: 1024
} derive(Show)
```

## Fetch FFI

```moonbit
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
  #|   }).then(r => r.text())
  #| }
```

Async MoonBit code awaits this via `js_fetch(...).wait()`.

## Gemini API Integration

Request format uses Gemini's REST API directly (no SDK):

- **Endpoint:** `https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent?key={api_key}`
- **JSON mode:** `responseMimeType: "application/json"` in `generationConfig` — Gemini returns valid JSON directly
- **System instruction:** via `systemInstruction.parts[0].text`

## Prompts

### Typo Correction

```
System: You are a Japanese/English text proofreader.
Fix typos, misspellings, and grammatical errors in the given text.
Respond ONLY with a JSON object: {"original": "<original text>", "fixed": "<corrected text>"}
```

### Structured Edits

```
System: You are an editor assistant. The user provides text and an instruction.
Respond with a JSON array of edit operations:
- {"action": "replace", "line": <1-based>, "old": "<find>", "new": "<replacement>"}
- {"action": "insert", "line": <1-based>, "text": "<text to insert after line>"}
- {"action": "delete", "line": <1-based>}
If no changes needed, return []
```

## FFI Exports

Exported functions return `@js_async.Promise[String]` to TypeScript via `Promise::from_async()`:

```moonbit
// Returns Promise<string> — JSON-encoded EditAction
pub fn canopy_llm_fix_typos(text : String, api_key : String) -> @js_async.Promise[String]

// Returns Promise<string> — JSON-encoded Array[EditAction]
pub fn canopy_llm_edit(text : String, instruction : String, api_key : String) -> @js_async.Promise[String]

// Pure, synchronous — for TS to set/get config
pub fn canopy_llm_set_config(config_json : String) -> String
```

## Package Structure

```
llm/
  moon.pkg              # imports: moonbitlang/async/js_async, moonbitlang/core/json
  types.mbt             # EditAction, Role, Message, GeminiConfig
  fetch_ffi.mbt         # extern "js" fn js_fetch (JS-target only)
  gemini.mbt            # Gemini request builder, response parser
  prompt.mbt            # System prompts, user message formatting
  parse.mbt             # JSON response → Array[EditAction]
  types_test.mbt        # Unit tests for types/parsing

ffi/
  canopy_llm.mbt        # FFI exports: canopy_llm_fix_typos, canopy_llm_edit, canopy_llm_set_config

examples/web/
  memo.html             # New entry point (textarea + toolbar)
  src/memo-editor.ts    # TS glue: textarea, "Fix Typos" button, API key input, result display
```

## Web UI (Minimal)

- Textarea for editing
- "Fix Typos" button (calls `canopy_llm_fix_typos`)
- API key input field (stored in memory only, not localStorage)
- Diff display showing original vs corrected text
- Follows existing design palette (navy base `#1a1a2e`, purple accent `#8250df`)

## Reference Libraries

Studied these MoonBit LLM libraries for design patterns:

| Library | What we took | What we skipped |
|---------|-------------|-----------------|
| `tiye/genai@0.0.2` | `#external` opaque types, JSON serialization across FFI | `@google/genai` npm dependency, Interactions API |
| `mizchi/llm@0.2.2` | `Provider` trait shape, `ProviderConfig`, `collect_text()` | `curl`/`spawnSync` transport, streaming SSE |
| `trkbt10/llm_interop@0.3.0` | Gateway/dialect architecture (future reference) | Multi-provider complexity |

Key difference: we use `moonbitlang/async` + browser `fetch()` instead of Node.js subprocess calls or npm SDKs.

## Defensive Measures

- Explicit user action required (button click, not auto-trigger)
- Max input: 5,000 characters
- Client-side rate limit: 1 request per 5 seconds
- API key in memory only (not persisted)

## Implementation Steps

1. **fetch FFI + async wiring** — `llm/fetch_ffi.mbt` with `js_fetch()`, verify with a test call
2. **Gemini client** — request builder + response parser in `llm/gemini.mbt`
3. **EditAction types + parsing** — `llm/types.mbt`, `llm/parse.mbt` with unit tests
4. **Typo correction** — system prompt + `FixTypos` parsing in `llm/prompt.mbt`
5. **FFI exports** — `ffi/canopy_llm.mbt` with `Promise::from_async()` wrapper
6. **Web UI** — `memo.html` + `memo-editor.ts`
7. **Structured edits** — generalize prompts to `Replace`/`Insert`/`Delete`
8. **Provider abstraction** — `Provider` trait, multiple backends (future)

## Future: UserIntent Unification

The prototype `EditAction` is a standalone type for the memo editor textarea. When LLM integration moves into the real canopy editors (lambda, JSON), `EditAction` should be replaced by the existing `UserIntent` protocol type.

### Operation Hierarchy (existing)

```
UserIntent (protocol)           ← LLM output lands here
  → TreeEditOp / JsonEditOp     (lang-specific, 41 / 9 variants)
    → SpanEdit                   (core: start, delete_len, inserted)
      → Edit                     (loom parser)
        → Op                     (CRDT: Insert/Delete with causal metadata)
```

### EditAction → UserIntent Mapping

| `EditAction` | `UserIntent` equivalent |
|---|---|
| `FixTypos(original, fixed)` | `TextEdit(from=0, to=len, insert=fixed)` |
| `Replace(line, old, new)` | `TextEdit(from, to, insert)` after line→byte conversion |
| `Insert(line, text)` | `TextEdit(from, to=from, insert)` |
| `Delete(line)` | `TextEdit(from, to, insert="")` |

All four variants are text-level edits expressed with line numbers. `UserIntent::TextEdit(from, to, insert)` already covers this — the only gap is **line→byte position conversion**, which requires the current document text.

### Phase 2: Text-Level LLM Edits in Real Editors

```moonbit
fn edit_action_to_intent(
  action : EditAction,
  source_text : String,
) -> UserIntent {
  match action {
    FixTypos(fixed~, ..) =>
      TextEdit(from=0, to=source_text.length(), insert=fixed)
    Replace(line~, old~, new~) => {
      let (from, to) = find_in_line(source_text, line, old)
      TextEdit(from~, to~, insert=new)
    }
    Insert(line~, text~) => {
      let from = line_end_offset(source_text, line)
      TextEdit(from~, to=from, insert="\n" + text)
    }
    Delete(line~) => {
      let (from, to) = line_span(source_text, line)
      TextEdit(from~, to~, insert="")
    }
  }
}
```

At this point, the LLM becomes just another source of `UserIntent` — same as keyboard input, structural toolbar, or collaboration peers. Undo/redo, CRDT sync, and incremental parsing all work automatically.

### Phase 3: Structural LLM Edits

The LLM could emit `UserIntent::StructuralEdit` directly, reusing existing `TreeEditOp` variants:

```moonbit
// LLM suggests "extract this expression to a let binding"
UserIntent::StructuralEdit(
  node_id=selected_node,
  op="extract_to_let",
  params={"var_name": "result"}.to_json(),
)
```

This gives the LLM access to all 41 lambda structural operations and 9 JSON operations without inventing new types. The existing `Action` system (with `needs_input`, `ActionGroup`, `NodeContext`) can filter which operations are valid in context before presenting them to the LLM as available tools.

### Why Not Unify Now

The prototype memo editor is a standalone textarea — no `SyncEditor`, no CRDT, no AST, no `NodeId`. `UserIntent` requires the full editor infrastructure (source maps, projection registry). Unifying prematurely would force the prototype to depend on the entire editor stack.

## Future: API Key Management & Deployment

The prototype sends the API key directly from the browser to Gemini. This is fine for local development but blocks deployment. Three options, lightest to heaviest:

### Option 1: Cloudflare Worker (recommended)

~20 lines. Free tier handles 100K req/day. Key lives in Workers secrets, never reaches the client.

```
Browser → your-worker.workers.dev/api/llm → Gemini API
              (key in env secret)
```

The MoonBit side only changes the fetch URL. No other code changes needed.

### Option 2: Vite dev server proxy (team development only)

Add a proxy rule to `vite.config.ts` that forwards `/api/llm` to Gemini with the key from `.env` (gitignored). Zero deployment, but only works in `npm run dev`.

### Option 3: Full backend (if per-user auth/billing needed)

Overkill unless you need per-user quotas, usage tracking, or multiple API keys.

### Migration path

1. Extract the Gemini URL into a config constant (currently hardcoded in `gemini.mbt`)
2. Point it at the Worker URL instead of `generativelanguage.googleapis.com`
3. Move API key from `build_gemini_headers` to the Worker's secret store
4. Remove the API key input field from `memo.html`

The `llm/` package architecture doesn't need to change — only the URL and header construction in `gemini.mbt`.

## Non-Goals (Current Phase)

- Streaming responses (batch is fine for typo correction)
- Function Calling / Tool Use API (JSON mode first)
- Fine-tuning or custom models

## Acceptance Criteria

- [ ] `moon check` passes with `llm/` package
- [ ] `moon test` passes for EditAction parsing
- [ ] Typo correction works end-to-end in browser with Gemini API key
- [ ] Structured edit instruction works for replace/insert/delete operations
- [ ] API key is never persisted to disk or localStorage
