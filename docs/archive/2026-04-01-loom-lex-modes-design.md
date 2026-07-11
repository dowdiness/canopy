# Loom Lex Modes

Add mode-aware tokenization to loom's lexer protocol for context-sensitive
languages like Markdown.

## Why

Loom's current `step_lex(input, pos) -> LexStep[T]` is stateless — same input
and position always produce the same token. This works for context-free languages
(lambda calculus, JSON) but not for Markdown, where the same character has
different meaning depending on context:

- `*` at line start followed by space = list marker; mid-line = emphasis
- `**` inside a code block = literal text, not bold
- `#` at line start = heading marker; mid-line = literal text
- Leading whitespace = indentation (semantic); mid-line whitespace = trivia

A workaround (backward-scanning to infer context from the input string) is
possible but puts context-recovery logic in the wrong place and produces tokens
with misleading kinds inside code blocks.

## Scope

In:
- `ModeLexer[T, M]` type in `loom/core`
- `tokenize_with_modes` function
- Mode-aware incremental re-lex in `TokenBuffer`
- Type erasure of M via `erase_mode_lexer` helper function
- Mock 2-mode language for testing

Out:
- Markdown parser (separate design, depends on this)
- Parser-controlled modes (future extension for Python-style indentation)
- Changes to ParserContext, LanguageSpec, or the parse phase

## Design

### Core Model: Lexer-Driven Mode Transitions

The lex step function takes a mode and returns a token plus the next mode:

```
lex_step(input, pos, mode) -> (LexStep[T], next_mode)
```

The lexer — not the parser — decides mode transitions based on what it sees.
This is sufficient for Markdown (transitions determined by the token being
produced) and most context-sensitive cases (HTML `<script>`, string
interpolation). Parser-controlled modes (needed for Python indent tracking)
are a future extension.

For Markdown, the transitions would be:
- `\n` in any mode -> emit Newline, switch to `LineStart`
- `# ` in `LineStart` -> emit HeadingMarker, switch to `Inline`
- `` ``` `` in `LineStart` -> emit CodeFence, switch to `CodeBlock`
- `` ``` `` in `CodeBlock` -> emit CodeFence, switch to `LineStart`
- Any character in `CodeBlock` -> emit CodeText (not emphasis/link markers)
- Block marker consumed in `LineStart` -> switch to `Inline`

### New Types

```moonbit
/// Mode-aware lexer. Each lex step takes a mode and returns
/// the token plus the next mode.
pub struct ModeLexer[T, M] {
  lex_step : (String, Int, M) -> (LexStep[T], M)
  initial_mode : M
}
```

`LexStep[T]` is unchanged — the mode is returned alongside it, not inside it.

### Grammar Integration: Type Erasure via Helper Function

Grammar keeps its existing type signature `Grammar[T, K, Ast]`. The `M` type
parameter from `ModeLexer[T, M]` is erased BEFORE reaching Grammar — a helper
function converts `ModeLexer[T, M]` into type-erased closures that Grammar
stores:

```moonbit
/// Type-erased closure bundle for mode-aware tokenization.
/// Hides M — Grammar only sees T.
pub struct ModeRelexState[T] {
  /// Tokenize full input, returning tokens + starts.
  /// Internally maintains a modes array for re-lex.
  tokenize : (String) -> (Array[TokenInfo[T]], Array[Int])
  /// Re-lex a damaged range [left_tok, right_tok) given the full new source.
  /// Returns (new_tokens, new_starts, converged).
  /// If not converged, caller must extend right_tok and call again.
  relex_range : (String, Int, Int) -> (Array[TokenInfo[T]], Array[Int], Bool)
  /// Splice the internal modes array after a successful re-lex.
  splice_modes : (Int, Int, Int) -> Unit  // (start, delete_count, insert_count)
}

/// Erase M at the call site, producing type-erased closures.
pub fn[T, M : Eq] erase_mode_lexer(
  mode_lexer : ModeLexer[T, M],
  eof_token : T,
) -> ModeRelexState[T]
```

Grammar gains one optional field:

```moonbit
struct Grammar[T, K, Ast] {
  // ... existing fields unchanged
  mode_relex : ModeRelexState[T]?

  fn new(
    // existing params...
    mode_relex? : ModeRelexState[T],
  ) -> Grammar[T, K, Ast]
}
```

**Call site for Markdown:**
```moonbit
let mode_state = erase_mode_lexer(markdown_mode_lexer, Token::EOF)
let grammar = Grammar::new(
  spec=markdown_spec,
  tokenize=mode_state.tokenize,  // full tokenize uses mode-aware path
  // ...
  mode_relex=Some(mode_state),
)
```

**Call site for lambda/JSON:** unchanged — `mode_relex` defaults to `None`.

**Precedence:** When `mode_relex` is `Some`, the factory uses
`mode_relex.tokenize` for full tokenization and `mode_relex.relex_range` for
incremental re-lex. The existing `tokenize` field and `prefix_lexer` field
are ignored for the mode-aware path. When `mode_relex` is `None`, the existing
stateless path is used unchanged.

This avoids the M-in-constructor problem entirely. Type erasure happens at the
call site via `erase_mode_lexer`, not inside Grammar's constructor.

### TokenBuffer: Mode-Aware Incremental Re-lex

TokenBuffer gains optional closures from Grammar for mode-aware re-lex.
The mode-per-token array is managed inside these closures — TokenBuffer
itself doesn't know about M.

**Incremental re-lex with convergence:**

1. Find damaged token range `[left, right)` (same algorithm as current)
2. If `mode_relex` is `None`: existing stateless re-lex (unchanged)
3. If `mode_relex` is `Some(state)`:
   a. Call `state.relex_range(new_source, left, right)`
   b. Returns `(new_tokens, new_starts, converged)`
   c. **Convergence** means: the mode after the last new token matches the
      old mode at token index `right`. Comparison is at token-index boundaries
      (aligned with the old token array), not arbitrary text offsets.
   d. If not converged: extend `right` by one token, call `relex_range` again
      with the wider range. Repeat until converged or `right` reaches EOF.
   e. Once converged: splice new tokens into the buffer, call
      `state.splice_modes(left, right - left, new_tokens.length())` to keep
      the internal modes array in sync.

**Interaction with `incremental_relex_enabled`:** When `mode_relex` is `Some`,
mode-aware re-lex is always used regardless of the `incremental_relex_enabled`
flag. The mode-aware path subsumes the stateless incremental path. When
`mode_relex` is `None`, the existing flag controls behavior as before.

Convergence is guaranteed because: (a) the mode set is finite, (b) re-lexing
eventually reaches EOF, and (c) at EOF the mode is deterministic (always the
mode produced by the last token in the document).

**Performance:** Most edits converge immediately (mode unchanged). Inserting
a code fence propagates to the closing fence or EOF — this is inherent to
code fences, not a design flaw. Same cost as backward-scan or parser-only
approaches.

### No Changes To

- `ParserContext` — accesses tokens via indexed closures, doesn't see modes
- `LanguageSpec` — parse rules unchanged
- `PrefixLexer` — still works for stateless lexers
- `ImperativeParser` / `ReactiveParser` — use factories which handle modes
  internally
- Lambda grammar / JSON grammar — don't pass `mode_lexer`
- `seam` module — CstNode/SyntaxNode unchanged

### File Changes

**New files:**
- `loom/loom/src/core/mode_lexer.mbt` (~100 lines) — `ModeLexer` struct,
  `ModeRelexState` struct, `erase_mode_lexer` function, `tokenize_with_modes`

**Modified files:**
- `loom/loom/src/grammar.mbt` (~20 lines) — add optional `mode_relex` field
  + constructor param
- `loom/loom/src/core/token_buffer.mbt` (~120 lines) — mode-aware re-lex path
  with convergence loop, splice_modes callback
- `loom/loom/src/factories.mbt` (~30 lines) — read `mode_relex` from Grammar,
  wire into TokenBuffer

**New test files:**
- `loom/loom/src/core/mode_lexer_wbtest.mbt` (~100 lines) — ModeLexer unit
  tests, tokenize_with_modes, erase_mode_lexer
- `loom/loom/src/core/mode_relex_wbtest.mbt` (~100 lines) — incremental re-lex
  convergence tests with mock 2-mode language

**Total: ~500 lines, 0 breaking changes.**

## Testing

**Unit tests for ModeLexer:**
- Mode transitions produce correct next_mode for each token
- `tokenize_with_modes` produces correct parallel token + mode arrays
- Edge cases: empty input, single token, mode at EOF

**Incremental re-lex tests:**
- Edit inside a single-mode region — converges immediately
- Insert mode-changing token — re-lex propagates until convergence
- Delete mode-changing token — mode reverts, re-lex propagates
- Edit inside alternate-mode region — converges immediately

**Backward compatibility:**
- Lambda grammar produces identical tokens (no `mode_lexer`)
- JSON grammar produces identical tokens
- `TokenBuffer` with no mode closures behaves identically to current

**Mock 2-mode language:**
- Define a minimal language with Normal and String modes (e.g., `"` toggles
  mode, tokens differ between modes)
- Tests validate the framework feature independent of Markdown

**Property test:**
- Full tokenization equals token-by-token replay — mode threading is consistent

## Acceptance Criteria

- [ ] `ModeLexer[T, M]` struct and `tokenize_with_modes` compile and pass tests
- [ ] Grammar accepts optional `mode_lexer` parameter; existing grammars unchanged
- [ ] TokenBuffer mode-aware re-lex converges correctly on mode-changing edits
- [ ] Mock 2-mode language passes all incremental re-lex tests
- [ ] Lambda `moon test` passes (no regressions)
- [ ] JSON `moon test` passes (no regressions)
- [ ] `moon check` passes with 0 warnings across loom module

## Validation

```bash
cd loom/loom && moon check && moon test
cd loom/examples/lambda && moon check && moon test
cd loom/examples/json && moon check && moon test
```

## Risks

- **MoonBit type inference for M:** Type erasure happens at the call site via
  `erase_mode_lexer`, not inside Grammar's constructor. M is fully resolved
  before reaching Grammar. No inference issue expected, but verify that
  `erase_mode_lexer` correctly infers M from the `ModeLexer` argument.
- **Closure capture of mutable mode array:** The type-erased closures capture
  a mutable `Array[M]`. Verify that MoonBit's closure semantics handle this
  correctly (reference capture, not copy).
- **Convergence performance on pathological input:** An unclosed code fence
  re-lexes to EOF. This is inherent to the problem and acceptable — same
  cost regardless of approach.

## References

- Tree-sitter external scanners — same pattern (parser/lexer-controlled modes
  with serialized state for incremental reuse)
- VS Code Monarch tokenizer — state-per-line caching for incremental
  re-tokenization
- CommonMark spec — two-phase parsing (block structure, then inline) motivates
  the mode design
