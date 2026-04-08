# Loom Lex Modes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add mode-aware tokenization to loom so context-sensitive languages (Markdown) can produce correct tokens per lexer mode.

**Architecture:** `ModeLexer[T, M]` produces tokens + mode transitions. `erase_mode_lexer` converts it into type-erased `ModeRelexState[T]` (closure wrapping `tokenize`). Grammar stores it optionally. TokenBuffer's `update` method uses full mode-aware retokenize when present. Convergence-based partial re-lex is a future optimization.

**Tech Stack:** MoonBit, loom parser framework (`loom/loom/`), quickcheck for property tests.

**Design spec:** `docs/plans/2026-04-01-loom-lex-modes-design.md`

---

## File Structure

| File | Action | Responsibility |
|------|--------|----------------|
| `loom/loom/src/core/mode_lexer.mbt` | Create | `ModeLexer[T,M]`, `ModeRelexState[T]`, `erase_mode_lexer`, `tokenize_with_modes` |
| `loom/loom/src/core/mode_lexer_wbtest.mbt` | Create | Unit tests for ModeLexer, tokenize_with_modes, erase_mode_lexer |
| `loom/loom/src/core/mode_relex_wbtest.mbt` | Create | Incremental re-lex convergence tests with mock 2-mode language |
| `loom/loom/src/core/token_buffer.mbt` | Modify | Add optional `mode_relex` field, mode-aware update path |
| `loom/loom/src/grammar.mbt` | Modify | Add optional `mode_relex` field to Grammar struct + constructor |
| `loom/loom/src/factories.mbt` | Modify | Wire `mode_relex` from Grammar into TokenBuffer |

---

### Task 1: ModeLexer struct and tokenize_with_modes

**Files:**
- Create: `loom/loom/src/core/mode_lexer.mbt`
- Test: `loom/loom/src/core/mode_lexer_wbtest.mbt`

- [ ] **Step 1: Write the failing test for tokenize_with_modes**

In `loom/loom/src/core/mode_lexer_wbtest.mbt`:

```moonbit
///| Mock 2-mode language: Normal and String.
///  `"` toggles between modes.
///  Normal mode: Text tokens for non-quote chars.
///  String mode: StringContent tokens for non-quote chars.
///  `"` always produces a Quote token in either mode.
priv enum MockMode {
  Normal
  StringMode
} derive(Eq, Show)

///|
priv enum MockToken {
  Text(String)
  StringContent(String)
  Quote
  EOF
} derive(Eq, Show)

///|
fn mock_char_at(input : String, pos : Int) -> Char? {
  input.code_unit_at(pos).to_char()
}

///|
fn mock_lex_step(
  input : String,
  pos : Int,
  mode : MockMode,
) -> (LexStep[MockToken], MockMode) {
  if pos >= input.length() {
    return (Done, mode)
  }
  match mock_char_at(input, pos) {
    Some('"') => {
      let next_mode = match mode {
        Normal => StringMode
        StringMode => Normal
      }
      (Produced(TokenInfo::new(Quote, 1), next_offset=pos + 1), next_mode)
    }
    _ => {
      // Consume run of non-quote characters
      let mut end = pos + 1
      while end < input.length() {
        match mock_char_at(input, end) {
          Some('"') => break
          _ => end = end + 1
        }
      }
      let text : StringView = input[pos:end]
      let token = match mode {
        Normal => Text(text.to_string())
        StringMode => StringContent(text.to_string())
      }
      (Produced(TokenInfo::new(token, end - pos), next_offset=end), mode)
    }
  }
}

///|
test "tokenize_with_modes basic" {
  let lexer : ModeLexer[MockToken, MockMode] = {
    lex_step: mock_lex_step,
    initial_mode: Normal,
  }
  let (tokens, modes) = tokenize_with_modes(lexer, "hello\"world\"end", MockToken::EOF)
  // tokens: Text("hello"), Quote, StringContent("world"), Quote, Text("end"), EOF
  inspect(tokens.length(), content="6")
  inspect(tokens[0].token, content="Text(\"hello\")")
  inspect(tokens[1].token, content="Quote")
  inspect(tokens[2].token, content="StringContent(\"world\")")
  inspect(tokens[3].token, content="Quote")
  inspect(tokens[4].token, content="Text(\"end\")")
  inspect(tokens[5].token, content="EOF")
  // modes: Normal, Normal, StringMode, StringMode, Normal, Normal
  inspect(modes[0], content="Normal")
  inspect(modes[1], content="Normal")
  inspect(modes[2], content="StringMode")
  inspect(modes[3], content="StringMode")
  inspect(modes[4], content="Normal")
  inspect(modes[5], content="Normal")
}

///|
test "tokenize_with_modes empty input" {
  let lexer : ModeLexer[MockToken, MockMode] = {
    lex_step: mock_lex_step,
    initial_mode: Normal,
  }
  let (tokens, modes) = tokenize_with_modes(lexer, "", MockToken::EOF)
  inspect(tokens.length(), content="1")
  inspect(tokens[0].token, content="EOF")
  inspect(modes[0], content="Normal")
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd loom/loom && moon test -p dowdiness/loom/core -f mode_lexer_wbtest.mbt`
Expected: FAIL — `ModeLexer` and `tokenize_with_modes` not defined.

- [ ] **Step 3: Write ModeLexer struct and tokenize_with_modes**

In `loom/loom/src/core/mode_lexer.mbt`:

```moonbit
///| Mode-aware lexer. Each step takes a mode and returns
///  the token plus the next mode.
pub(all) struct ModeLexer[T, M] {
  lex_step : (String, Int, M) -> (LexStep[T], M)
  initial_mode : M
}

///| Tokenize a full input with mode tracking.
///  Returns parallel arrays: tokens and mode-at-each-token.
///  The mode array records the mode BEFORE each token was lexed.
///  Appends EOF sentinel as the last element (matching tokenize_via_steps contract).
pub fn[T, M] tokenize_with_modes(
  lexer : ModeLexer[T, M],
  input : String,
  eof_token : T,
) -> (Array[TokenInfo[T]], Array[M]) raise LexError {
  let tokens : Array[TokenInfo[T]] = []
  let modes : Array[M] = []
  let mut pos = 0
  let mut mode = lexer.initial_mode
  while true {
    let (step, next_mode) = (lexer.lex_step)(input, pos, mode)
    match step {
      Produced(tok, next_offset~) => {
        if next_offset <= pos {
          raise LexError(
            "mode lexer made no progress at position " + pos.to_string(),
          )
        }
        modes.push(mode)
        tokens.push(TokenInfo::new(tok.token, next_offset - pos))
        mode = next_mode
        pos = next_offset
      }
      Invalid(message~, ..) => raise LexError(message)
      Incomplete(expected~, ..) => raise LexError(expected)
      Done => {
        modes.push(mode)
        tokens.push(TokenInfo::new(eof_token, 0))
        break
      }
    }
  }
  (tokens, modes)
}
```

- [ ] **Step 4: Run `moon check` to verify compilation**

Run: `cd loom/loom && moon check`
Expected: 0 errors.

- [ ] **Step 5: Run test to verify it passes**

Run: `cd loom/loom && moon test -p dowdiness/loom/core -f mode_lexer_wbtest.mbt`
Expected: PASS. Update snapshots with `moon test --update` if needed.

- [ ] **Step 6: Commit**

```bash
cd loom/loom && moon info && moon fmt
git add src/core/mode_lexer.mbt src/core/mode_lexer_wbtest.mbt
git commit -m "feat(core): add ModeLexer and tokenize_with_modes"
```

---

### Task 2: ModeRelexState and erase_mode_lexer

**Files:**
- Modify: `loom/loom/src/core/mode_lexer.mbt`
- Test: `loom/loom/src/core/mode_lexer_wbtest.mbt`

- [ ] **Step 1: Write the failing test for erase_mode_lexer**

Append to `loom/loom/src/core/mode_lexer_wbtest.mbt`:

```moonbit
///|
test "erase_mode_lexer tokenize matches tokenize_with_modes" {
  let lexer : ModeLexer[MockToken, MockMode] = {
    lex_step: mock_lex_step,
    initial_mode: Normal,
  }
  let state = erase_mode_lexer(lexer, MockToken::EOF)
  let (tokens, starts) = (state.tokenize)("hello\"world\"end")
  inspect(tokens.length(), content="6")
  inspect(tokens[0].token, content="Text(\"hello\")")
  inspect(tokens[2].token, content="StringContent(\"world\")")
  // Starts are prefix sums: 0, 5, 6, 11, 12, 15
  inspect(starts[0], content="0")
  inspect(starts[1], content="5")
  inspect(starts[2], content="6")
  inspect(starts[3], content="11")
  inspect(starts[4], content="12")
  inspect(starts[5], content="15")
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd loom/loom && moon test -p dowdiness/loom/core -f mode_lexer_wbtest.mbt`
Expected: FAIL — `erase_mode_lexer` not defined.

- [ ] **Step 3: Write ModeRelexState and erase_mode_lexer**

Append to `loom/loom/src/core/mode_lexer.mbt`:

```moonbit
///| Type-erased closure bundle for mode-aware tokenization.
///  Hides M — Grammar only sees T.
///
///  Currently provides full retokenize only. Incremental convergence-based
///  re-lex (partial re-lex with mode propagation) is a future optimization,
///  to be added when profiling shows full retokenize is a bottleneck.
pub struct ModeRelexState[T] {
  /// Tokenize full input. Returns (tokens, starts).
  /// Internally maintains a modes-per-token array for future
  /// incremental re-lex support.
  tokenize : (String) -> (Array[TokenInfo[T]], Array[Int]) raise LexError
}

///| Erase the mode type M, producing a type-erased closure that Grammar
///  can store without knowing M.
pub fn[T, M : Eq] erase_mode_lexer(
  lexer : ModeLexer[T, M],
  eof_token : T,
) -> ModeRelexState[T] {
  // Mutable state captured by closure — modes array maintained for
  // future incremental re-lex (convergence check needs mode at each token).
  let modes_ref : Ref[Array[M]] = Ref::new([])
  let tokenize = fn(source : String) -> (Array[TokenInfo[T]], Array[Int]) raise LexError {
    let (tokens, modes) = tokenize_with_modes(lexer, source, eof_token)
    modes_ref.val = modes
    let starts = build_starts(tokens)
    (tokens, starts)
  }
  { tokenize }
}
```

- [ ] **Step 4: Run `moon check`**

Run: `cd loom/loom && moon check`
Expected: 0 errors.

- [ ] **Step 5: Run test to verify it passes**

Run: `cd loom/loom && moon test -p dowdiness/loom/core -f mode_lexer_wbtest.mbt`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
cd loom/loom && moon info && moon fmt
git add src/core/mode_lexer.mbt src/core/mode_lexer_wbtest.mbt
git commit -m "feat(core): add ModeRelexState and erase_mode_lexer"
```

---

### Task 3: Wire ModeRelexState into Grammar and factories

**Files:**
- Modify: `loom/loom/src/grammar.mbt`
- Modify: `loom/loom/src/factories.mbt`
- Test: `loom/loom/src/core/mode_lexer_wbtest.mbt`

- [ ] **Step 1: Add mode_relex field to Grammar**

In `loom/loom/src/grammar.mbt`, add the field to the struct and constructor:

```moonbit
pub struct Grammar[T, K, Ast] {
  spec : @core.LanguageSpec[T, K]
  tokenize : (String) -> Array[@core.TokenInfo[T]] raise @core.LexError
  fold_node : (@seam.SyntaxNode, (@seam.SyntaxNode) -> Ast) -> Ast
  on_lex_error : (String) -> Ast
  error_token : T?
  prefix_lexer : @core.PrefixLexer[T]?
  block_reparse_spec : @core.BlockReparseSpec[T, K]?
  mode_relex : @core.ModeRelexState[T]?
}

pub fn[T, K, Ast] Grammar::new(
  spec~ : @core.LanguageSpec[T, K],
  tokenize~ : (String) -> Array[@core.TokenInfo[T]] raise @core.LexError,
  fold_node~ : (@seam.SyntaxNode, (@seam.SyntaxNode) -> Ast) -> Ast,
  on_lex_error~ : (String) -> Ast,
  error_token? : T? = None,
  prefix_lexer? : @core.PrefixLexer[T]? = None,
  block_reparse_spec? : @core.BlockReparseSpec[T, K]? = None,
  mode_relex? : @core.ModeRelexState[T]? = None,
) -> Grammar[T, K, Ast] {
  {
    spec,
    tokenize,
    fold_node,
    on_lex_error,
    error_token,
    prefix_lexer,
    block_reparse_spec,
    mode_relex,
  }
}
```

- [ ] **Step 2: Run `moon check`**

Run: `cd loom/loom && moon check`
Expected: 0 errors. Existing lambda/JSON grammars don't pass `mode_relex`, so they default to `None`.

- [ ] **Step 3: Verify no regressions**

Run: `cd loom/loom && moon test`
Then: `cd loom/examples/lambda && moon test`
Then: `cd loom/examples/json && moon test`
Expected: All pass.

- [ ] **Step 4: Wire mode_relex into TokenBuffer in factories**

In `loom/loom/src/factories.mbt`, modify `create_buffer` to accept and store mode_relex. Add `mode_relex` field to `TokenBuffer`:

First, modify `loom/loom/src/core/token_buffer.mbt` — add the optional field:

```moonbit
pub struct TokenBuffer[T] {
  priv tokenize_fn : (String) -> Array[TokenInfo[T]] raise LexError
  priv retokenize_full : (String) -> (Array[TokenInfo[T]], Array[Int]) raise LexError
  priv incremental_relex_enabled : Bool
  priv eof_token : T
  priv mut tokens : Array[TokenInfo[T]]
  priv mut starts : Array[Int]
  mut source : String
  mut version : Int
  priv mode_relex : ModeRelexState[T]?
}
```

Add `mode_relex: None` to the struct literal in each existing constructor:

1. `TokenBuffer::new` (line 78): add `mode_relex: None,` after `version: 0,`
2. `TokenBuffer::new_resilient` (line 107): add `mode_relex: None,` after `version: 0,`
3. `TokenBuffer::new_resilient_compat` — delegates to `new_resilient`, no change needed
4. `TokenBuffer::new_from_steps` (line 152): add `mode_relex: None,` after `version: 0,`
5. `TokenBuffer::new_from_steps_strict` (line 182): add `mode_relex: None,` after `version: 0,`

Then in `loom/loom/src/factories.mbt`, modify `create_buffer`:

```moonbit
fn[T] create_buffer(
  source : String,
  tokenize : (String) -> Array[@core.TokenInfo[T]] raise @core.LexError,
  eof_token : T,
  error_token : T?,
  prefix_lexer? : @core.PrefixLexer[T]? = None,
  mode_relex? : @core.ModeRelexState[T]? = None,
) -> @core.TokenBuffer[T] raise @core.LexError {
  match mode_relex {
    Some(state) => {
      // Mode-aware path: use state.tokenize for initial tokenization
      let (tokens, starts) = (state.tokenize)(source)
      @core.TokenBuffer::new_with_mode_relex(source, tokens, starts, eof_token, state)
    }
    None => {
      // Existing stateless path (unchanged)
      match (prefix_lexer, error_token) {
        (Some(lexer), Some(err_tok)) =>
          @core.TokenBuffer::new_from_steps(source, lexer, eof_token~, error_token=err_tok)
        (Some(lexer), None) =>
          @core.TokenBuffer::new_from_steps_strict(source, lexer, eof_token~)
        (None, Some(err_tok)) =>
          @core.TokenBuffer::new_resilient_compat(source, tokenize_fn=tokenize, eof_token~, error_token=err_tok)
        (None, None) =>
          @core.TokenBuffer::new(source, tokenize_fn=tokenize, eof_token~)
      }
    }
  }
}
```

Add the new constructor to `loom/loom/src/core/token_buffer.mbt`:

```moonbit
///| Construct a TokenBuffer with mode-aware re-lex support.
pub fn[T] TokenBuffer::new_with_mode_relex(
  source : String,
  tokens : Array[TokenInfo[T]],
  starts : Array[Int],
  eof_token : T,
  mode_relex : ModeRelexState[T],
) -> TokenBuffer[T] {
  let retokenize_full = mode_relex.tokenize
  let tokenize_fn : (String) -> Array[TokenInfo[T]] raise LexError = s => {
    let (tokens, _) = (mode_relex.tokenize)(s)
    tokens
  }
  {
    tokenize_fn,
    retokenize_full,
    incremental_relex_enabled: true,
    eof_token,
    tokens,
    starts,
    source,
    version: 0,
    mode_relex: Some(mode_relex),
  }
}
```

Update `new_imperative_parser` to pass `mode_relex` through:

In `new_imperative_parser` (`factories.mbt:52-210`), extract `mode_relex` alongside other grammar fields:

```moonbit
  let mode_relex = grammar.mode_relex
```

Then update all three `create_buffer` calls in the function (lines 72, 135, 155) to pass `mode_relex~`:

```moonbit
      let buffer = create_buffer(
        source,
        tokenize,
        spec.eof_token,
        error_token,
        prefix_lexer~,
        mode_relex~,
      )
```

Update `new_reactive_parser` the same way:

In `new_reactive_parser` (`factories.mbt:225-327`), extract `mode_relex`:

```moonbit
  let mode_relex = grammar.mode_relex
```

Then update the `create_buffer` call inside the token memo closure (line 244) to pass `mode_relex~`:

```moonbit
      let buffer = create_buffer(
        s,
        tokenize,
        spec.eof_token,
        error_token,
        prefix_lexer~,
        mode_relex~,
      )
```

- [ ] **Step 5: Run `moon check`**

Run: `cd loom/loom && moon check`
Expected: 0 errors.

- [ ] **Step 6: Verify no regressions**

Run: `cd loom/loom && moon test`
Then: `cd loom/examples/lambda && moon test`
Then: `cd loom/examples/json && moon test`
Expected: All pass (mode_relex is None for both, stateless path unchanged).

- [ ] **Step 7: Commit**

```bash
cd loom/loom && moon info && moon fmt
git add src/grammar.mbt src/factories.mbt src/core/token_buffer.mbt
git commit -m "feat: wire ModeRelexState into Grammar and TokenBuffer"
```

---

### Task 4: Mode-aware incremental re-lex with convergence

**Files:**
- Modify: `loom/loom/src/core/token_buffer.mbt`
- Modify: `loom/loom/src/core/mode_lexer.mbt`
- Test: `loom/loom/src/core/mode_relex_wbtest.mbt`

- [ ] **Step 1: Write failing test for mode-aware incremental re-lex**

Create `loom/loom/src/core/mode_relex_wbtest.mbt`:

```moonbit
///| Test incremental re-lex with mode convergence.
///  Uses the mock 2-mode language from mode_lexer_wbtest.mbt.

///| Helper: create a TokenBuffer with mode-aware re-lex for the mock language.
fn create_mock_buffer(
  source : String,
) -> TokenBuffer[MockToken] raise LexError {
  let lexer : ModeLexer[MockToken, MockMode] = {
    lex_step: mock_lex_step,
    initial_mode: Normal,
  }
  let state = erase_mode_lexer(lexer, MockToken::EOF)
  let (tokens, starts) = (state.tokenize)(source)
  TokenBuffer::new_with_mode_relex(source, tokens, starts, MockToken::EOF, state)
}

///|
test "mode relex: edit inside normal region converges immediately" {
  let buffer = create_mock_buffer("hello\"world\"end")
  // Edit: change "hello" to "hi" (replace 5 chars with 2)
  let edit = Edit::new(0, 5, 2)
  buffer.update(edit, "hi\"world\"end")
  inspect(buffer.token_count(), content="6")
  inspect(buffer.get_token(0), content="Text(\"hi\")")
  inspect(buffer.get_token(2), content="StringContent(\"world\")")
}

///|
test "mode relex: insert quote changes mode — propagates" {
  let buffer = create_mock_buffer("hello world")
  // tokens: Text("hello world"), EOF
  // Insert a quote at position 5: "hello"world"
  // Wait, that's wrong. Let me make it "hello\" world"
  // Actually: insert `"` at pos 5 → "hello\"world" → but source has no closing quote
  let edit = Edit::new(5, 0, 1)
  buffer.update(edit, "hello\" world")
  // Now: Text("hello"), Quote, StringContent(" world"), EOF
  inspect(buffer.get_token(0), content="Text(\"hello\")")
  inspect(buffer.get_token(1), content="Quote")
  inspect(buffer.get_token(2), content="StringContent(\" world\")")
}

///|
test "mode relex: delete quote reverts mode" {
  let buffer = create_mock_buffer("hello\"world\"end")
  // Delete first quote (at position 5, length 1)
  let edit = Edit::new(5, 1, 0)
  buffer.update(edit, "helloworld\"end")
  // Now: Text("helloworld"), Quote, StringContent("end"), EOF
  inspect(buffer.get_token(0), content="Text(\"helloworld\")")
  inspect(buffer.get_token(1), content="Quote")
  inspect(buffer.get_token(2), content="StringContent(\"end\")")
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd loom/loom && moon test -p dowdiness/loom/core -f mode_relex_wbtest.mbt`
Expected: FAIL — mode-aware update path not yet implemented in TokenBuffer.

- [ ] **Step 3: Implement mode-aware update in TokenBuffer**

In `loom/loom/src/core/token_buffer.mbt`, modify the `update` method. At the top, before the existing incremental path, add:

```moonbit
pub fn[T] TokenBuffer::update(
  self : TokenBuffer[T],
  edit : Edit,
  new_source : String,
) -> Unit raise LexError {
  // Mode-aware path: full retokenize with mode tracking.
  // The ModeRelexState closures maintain the modes array internally.
  // Convergence optimization (partial re-lex) is a future improvement.
  match self.mode_relex {
    Some(state) => {
      let (tokens, starts) = (state.tokenize)(new_source)
      self.tokens = tokens
      self.starts = starts
      self.source = new_source
      self.version = self.version + 1
      return
    }
    None => ()
  }
  // ... existing stateless update code unchanged below ...
```

This is the simple correct implementation: full retokenize on every edit. The modes array is rebuilt inside the closure. Convergence-based partial re-lex is a future optimization (only needed when profiling shows this is a bottleneck).

- [ ] **Step 4: Run `moon check`**

Run: `cd loom/loom && moon check`
Expected: 0 errors.

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd loom/loom && moon test -p dowdiness/loom/core -f mode_relex_wbtest.mbt`
Expected: PASS. Update snapshots with `moon test --update` if needed.

- [ ] **Step 6: Run full regression suite**

Run: `cd loom/loom && moon test`
Then: `cd loom/examples/lambda && moon test`
Then: `cd loom/examples/json && moon test`
Expected: All pass.

- [ ] **Step 7: Commit**

```bash
cd loom/loom && moon info && moon fmt
git add src/core/token_buffer.mbt src/core/mode_relex_wbtest.mbt src/core/mode_lexer.mbt
git commit -m "feat(core): mode-aware incremental re-lex in TokenBuffer"
```

---

### Task 5: Property tests and backward compatibility verification

**Files:**
- Modify: `loom/loom/src/core/mode_lexer_wbtest.mbt`
- Modify: `loom/loom/src/core/mode_relex_wbtest.mbt`

- [ ] **Step 1: Add property test — full tokenize equals step-by-step replay**

Append to `loom/loom/src/core/mode_lexer_wbtest.mbt`:

```moonbit
///| Property: tokenize_with_modes produces the same tokens as manually
///  stepping through lex_step with mode threading.
///  Uses quickcheck to generate random strings containing quotes and text.
test "property: tokenize_with_modes consistent with step replay" {
  @qc.quick_check_fn(fn(input : String) -> Bool {
    let lexer : ModeLexer[MockToken, MockMode] = {
      lex_step: mock_lex_step,
      initial_mode: Normal,
    }
    let (tokens, modes) = try {
      tokenize_with_modes(lexer, input, MockToken::EOF)
    } catch {
      _ => return true // skip inputs that cause lex errors
    }
    // Manual replay
    let mut pos = 0
    let mut mode : MockMode = Normal
    let mut i = 0
    while pos < input.length() {
      let (step, next_mode) = mock_lex_step(input, pos, mode)
      match step {
        Produced(tok, next_offset~) => {
          if tokens[i].token != tok.token { return false }
          if modes[i] != mode { return false }
          mode = next_mode
          pos = next_offset
          i = i + 1
        }
        _ => break
      }
    }
    // EOF sentinel
    tokens[i].token == MockToken::EOF
  })
}
```

- [ ] **Step 2: Add backward compat test — existing buffer constructors still work**

Append to `loom/loom/src/core/mode_relex_wbtest.mbt`:

```moonbit
///| Verify that TokenBuffer without mode_relex behaves identically.
test "backward compat: TokenBuffer::new still works without mode_relex" {
  let tokenize_fn : (String) -> Array[TokenInfo[MockToken]] raise LexError = s => {
    let lexer : ModeLexer[MockToken, MockMode] = {
      lex_step: mock_lex_step,
      initial_mode: Normal,
    }
    let (tokens, _modes) = tokenize_with_modes(lexer, s, MockToken::EOF)
    tokens
  }
  let buffer = TokenBuffer::new("hello", tokenize_fn~, eof_token=MockToken::EOF)
  inspect(buffer.token_count(), content="2")
  inspect(buffer.get_token(0), content="Text(\"hello\")")
}
```

- [ ] **Step 3: Run all tests**

Run: `cd loom/loom && moon test`
Then: `cd loom/examples/lambda && moon test`
Then: `cd loom/examples/json && moon test`
Expected: All pass.

- [ ] **Step 4: Commit**

```bash
cd loom/loom && moon info && moon fmt
git add src/core/mode_lexer_wbtest.mbt src/core/mode_relex_wbtest.mbt
git commit -m "test: add property tests and backward compat verification for lex modes"
```

---

### Task 6: Final cleanup and interface update

**Files:**
- All modified files

- [ ] **Step 1: Run moon info and verify .mbti changes**

```bash
cd loom/loom && moon info
git diff *.mbti
```

Review: only `core/` should have new exports (`ModeLexer`, `ModeRelexState`, `erase_mode_lexer`, `tokenize_with_modes`, `TokenBuffer::new_with_mode_relex`). Grammar should have one new optional field (`mode_relex`). No removed exports.

- [ ] **Step 2: Run moon fmt**

```bash
cd loom/loom && moon fmt
```

- [ ] **Step 3: Run full validation suite**

```bash
cd loom/loom && moon check && moon test
cd loom/examples/lambda && moon check && moon test
cd loom/examples/json && moon check && moon test
```

Expected: All pass, 0 warnings.

- [ ] **Step 4: Final commit**

```bash
cd loom/loom && git add -A
git diff --cached --stat  # verify only expected files
git commit -m "chore: update interfaces and format for lex modes"
```
