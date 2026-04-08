# Markdown Parser Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Markdown parser as a standalone loom module (`loom/examples/markdown/`) that exercises lex modes and produces a two-level AST (Block + Inline).

**Architecture:** Mode-aware lexer (LineStart/Inline/CodeBlock) → recursive descent parser (block + inline on same ParserContext) → CST → two-level AST (Block, Inline). No trivia tokens — parser sees everything. Single package (follows JSON example pattern).

**Tech Stack:** MoonBit, loom parser framework, loom lex-modes.

**Design spec:** `docs/plans/2026-04-01-markdown-parser-design.md`

**Prerequisite:** Loom submodule must be at commit `c2d2dfc` or later (lex-modes PR #67 merged). Verify: `Grammar` struct has `mode_relex` field, `core/mode_lexer.mbt` has `ModeLexer`, `erase_mode_lexer`, `tokenize_with_modes`.

---

## File Structure

All source files in one package (`src/`), following the JSON example pattern.

| File | Responsibility |
|------|----------------|
| `moon.mod.json` | Module config + deps |
| `src/moon.pkg` | Package imports |
| `src/token.mbt` | Token enum, IsTrivia (always false), IsEof, Show |
| `src/syntax_kind.mbt` | SyntaxKind enum, ToRawKind, FromRawKind |
| `src/lex_mode.mbt` | MarkdownLexMode enum |
| `src/lexer.mbt` | Mode-aware step_lex, tokenize, ModeLexer wiring |
| `src/ast.mbt` | Block + Inline enums |
| `src/markdown_spec.mbt` | LanguageSpec with cst_token_matches |
| `src/grammar.mbt` | Grammar assembly with mode_relex |
| `src/cst_parser.mbt` | Block-level parser (parse_document, parse_heading, etc.) |
| `src/inline_parser.mbt` | Inline parser (parse_bold, parse_italic, etc.) |
| `src/parser.mbt` | Public parse/parse_markdown/parse_cst API |
| `src/block_convert.mbt` | SyntaxNode → Block conversion |
| `src/inline_convert.mbt` | SyntaxNode → Inline conversion |
| `src/proj_traits.mbt` | TreeNode + Renderable for Block and Inline |
| `src/lexer_test.mbt` | Lexer tests |
| `src/parser_test.mbt` | Parser tests |
| `src/inline_test.mbt` | Inline markup tests |
| `src/error_recovery_test.mbt` | Error recovery tests (use parse_cst) |
| `src/source_fidelity_test.mbt` | CST source fidelity tests |

---

### Task 1: Module scaffolding — Token, SyntaxKind, AST, lex mode

**Files:** `moon.mod.json`, `src/moon.pkg`, `src/token.mbt`, `src/syntax_kind.mbt`, `src/lex_mode.mbt`, `src/ast.mbt`

- [ ] **Step 1: Create `moon.mod.json`**

```json
{
  "name": "dowdiness/markdown",
  "version": "0.1.0",
  "source": "src",
  "deps": {
    "dowdiness/loom": { "path": "../../loom" },
    "dowdiness/seam": { "path": "../../seam" }
  },
  "license": "Apache-2.0",
  "keywords": ["markdown", "parser"],
  "description": "Markdown parser example for dowdiness/loom"
}
```

- [ ] **Step 2: Create `src/moon.pkg`**

```
import {
  "dowdiness/loom/core" @core,
  "dowdiness/seam" @seam,
  "dowdiness/loom" @loom,
}
```

- [ ] **Step 3: Create `src/token.mbt`**

Heading/list markers consume the trailing space (e.g., `# ` is 2 chars, `- ` is 2 chars). This keeps inline content clean (`Text("Hello")` not `Text(" Hello")`).

```moonbit
///|
pub(all) enum Token {
  HeadingMarker(Int)         // "# " = 1, "## " = 2, etc. (includes trailing space)
  ListMarker                 // "- " or "* " or "+ " (includes trailing space)
  CodeFenceOpen(Int, String) // backtick count, info string
  CodeFenceClose             // closing fence
  BlankLine                  // empty or whitespace-only line
  Star                       // *
  StarStar                   // **
  Backtick                   // `
  LeftBracket                // [
  RightBracket               // ]
  LeftParen                  // (
  RightParen                 // )
  Text(String)               // plain text run (includes inter-word spaces)
  CodeText(String)           // line of code block content
  Newline                    // \n
  Error(String)
  EOF
} derive(Eq, Debug)

///|
pub impl Show for Token with output(self, logger) {
  logger.write_string(
    match self {
      HeadingMarker(n) => "#".repeat(n) + " "
      ListMarker => "- "
      CodeFenceOpen(n, info) =>
        "`".repeat(n) + info
      CodeFenceClose => "```"
      BlankLine => ""
      Star => "*"
      StarStar => "**"
      Backtick => "`"
      LeftBracket => "["
      RightBracket => "]"
      LeftParen => "("
      RightParen => ")"
      Text(s) => s
      CodeText(s) => s
      Newline => "\n"
      Error(msg) => "<error: " + msg + ">"
      EOF => ""
    },
  )
}

///|
pub impl @seam.IsTrivia for Token with is_trivia(_self) {
  false
}

///|
pub impl @seam.IsEof for Token with is_eof(self) {
  self == EOF
}
```

- [ ] **Step 4: Create `src/syntax_kind.mbt`**

```moonbit
///|
pub(all) enum SyntaxKind {
  // Token kinds
  HeadingMarkerToken
  ListMarkerToken
  CodeFenceOpenToken
  CodeFenceCloseToken
  BlankLineToken
  StarToken
  StarStarToken
  BacktickToken
  LeftBracketToken
  RightBracketToken
  LeftParenToken
  RightParenToken
  TextToken
  CodeTextToken
  NewlineToken
  ErrorToken
  EofToken
  // Node kinds
  DocumentNode
  HeadingNode
  ParagraphNode
  UnorderedListNode
  ListItemNode
  CodeBlockNode
  BoldNode
  ItalicNode
  InlineCodeNode
  LinkNode
  ErrorNode
} derive(Show, Eq)

///|
pub fn SyntaxKind::is_token(self : SyntaxKind) -> Bool {
  match self {
    HeadingMarkerToken | ListMarkerToken | CodeFenceOpenToken
    | CodeFenceCloseToken | BlankLineToken | StarToken | StarStarToken
    | BacktickToken | LeftBracketToken | RightBracketToken | LeftParenToken
    | RightParenToken | TextToken | CodeTextToken | NewlineToken | ErrorToken
    | EofToken => true
    _ => false
  }
}

///|
pub impl @seam.ToRawKind for SyntaxKind with to_raw(self) {
  @seam.RawKind(
    match self {
      HeadingMarkerToken => 0
      ListMarkerToken => 1
      CodeFenceOpenToken => 2
      CodeFenceCloseToken => 3
      BlankLineToken => 4
      StarToken => 5
      StarStarToken => 6
      BacktickToken => 7
      LeftBracketToken => 8
      RightBracketToken => 9
      LeftParenToken => 10
      RightParenToken => 11
      TextToken => 12
      CodeTextToken => 13
      NewlineToken => 14
      ErrorToken => 15
      EofToken => 16
      DocumentNode => 17
      HeadingNode => 18
      ParagraphNode => 19
      UnorderedListNode => 20
      ListItemNode => 21
      CodeBlockNode => 22
      BoldNode => 23
      ItalicNode => 24
      InlineCodeNode => 25
      LinkNode => 26
      ErrorNode => 27
    },
  )
}

///|
pub impl @seam.FromRawKind for SyntaxKind with from_raw(raw) {
  match raw.0 {
    0 => HeadingMarkerToken
    1 => ListMarkerToken
    2 => CodeFenceOpenToken
    3 => CodeFenceCloseToken
    4 => BlankLineToken
    5 => StarToken
    6 => StarStarToken
    7 => BacktickToken
    8 => LeftBracketToken
    9 => RightBracketToken
    10 => LeftParenToken
    11 => RightParenToken
    12 => TextToken
    13 => CodeTextToken
    14 => NewlineToken
    15 => ErrorToken
    16 => EofToken
    17 => DocumentNode
    18 => HeadingNode
    19 => ParagraphNode
    20 => UnorderedListNode
    21 => ListItemNode
    22 => CodeBlockNode
    23 => BoldNode
    24 => ItalicNode
    25 => InlineCodeNode
    26 => LinkNode
    27 => ErrorNode
    _ => ErrorNode
  }
}
```

- [ ] **Step 5: Create `src/lex_mode.mbt`**

```moonbit
///|
pub(all) enum MarkdownLexMode {
  LineStart
  Inline
  CodeBlock(Int)
} derive(Eq, Show)
```

- [ ] **Step 6: Create `src/ast.mbt`**

```moonbit
///|
pub(all) enum Block {
  Document(Array[Block])
  Heading(Int, Array[Inline])
  Paragraph(Array[Inline])
  UnorderedList(Array[Block])
  ListItem(Array[Inline])
  CodeBlock(String, String)
  Error(String)
} derive(Show, Eq, Debug)

///|
pub(all) enum Inline {
  Text(String)
  Bold(Array[Inline])
  Italic(Array[Inline])
  InlineCode(String)
  Link(Array[Inline], String)
  Error(String)
} derive(Show, Eq, Debug)
```

- [ ] **Step 7: Run `moon check`**

```bash
cd loom/examples/markdown && moon check
```

Expected: 0 errors.

- [ ] **Step 8: Commit**

```bash
cd loom/examples/markdown && moon info && moon fmt
cd loom && git add examples/markdown
git commit -m "feat(markdown): scaffolding — Token, SyntaxKind, LexMode, AST enums"
```

---

### Task 2: Mode-aware lexer

**Files:** `src/lexer.mbt`, `src/lexer_test.mbt`

This is the most complex task. The lexer has three modes:
- **LineStart**: recognize block markers (`#`, `-`/`*`/`+`, `` ` ``), blank lines
- **Inline**: recognize emphasis markers, brackets, backticks; accumulate text runs with spaces
- **CodeBlock(n)**: emit code text lines; match closing fence with backtick count >= n

- [ ] **Step 1: Write lexer tests**

Create `src/lexer_test.mbt`. All tests call `tokenize(...)` directly (same package).

```moonbit
///|
test "lexer: heading" {
  let tokens = tokenize("# Hello\n")
  inspect(tokens[0].token, content="HeadingMarker(1)")
  inspect(tokens[1].token, content="Text(\"Hello\")")
  inspect(tokens[2].token, content="Newline")
  inspect(tokens[3].token, content="EOF")
}

///|
test "lexer: h2 heading" {
  let tokens = tokenize("## World\n")
  inspect(tokens[0].token, content="HeadingMarker(2)")
  inspect(tokens[1].token, content="Text(\"World\")")
}

///|
test "lexer: paragraph text preserves spaces" {
  let tokens = tokenize("hello world\n")
  inspect(tokens[0].token, content="Text(\"hello world\")")
  inspect(tokens[1].token, content="Newline")
}

///|
test "lexer: code fence with info" {
  let tokens = tokenize("```python\ncode here\n```\n")
  inspect(tokens[0].token, content="CodeFenceOpen(3, \"python\")")
  inspect(tokens[1].token, content="Newline")
  inspect(tokens[2].token, content="CodeText(\"code here\")")
  inspect(tokens[3].token, content="Newline")
  inspect(tokens[4].token, content="CodeFenceClose")
  inspect(tokens[5].token, content="Newline")
}

///|
test "lexer: inline markers" {
  let tokens = tokenize("**bold** and *italic*\n")
  inspect(tokens[0].token, content="StarStar")
  inspect(tokens[1].token, content="Text(\"bold\")")
  inspect(tokens[2].token, content="StarStar")
  inspect(tokens[3].token, content="Text(\" and \")")
  inspect(tokens[4].token, content="Star")
  inspect(tokens[5].token, content="Text(\"italic\")")
  inspect(tokens[6].token, content="Star")
}

///|
test "lexer: list marker consumes trailing space" {
  let tokens = tokenize("- item\n")
  inspect(tokens[0].token, content="ListMarker")
  inspect(tokens[1].token, content="Text(\"item\")")
}

///|
test "lexer: blank line" {
  let tokens = tokenize("\n\n")
  // First \n from empty line → BlankLine, second \n → BlankLine
  inspect(tokens[0].token, content="BlankLine")
}

///|
test "lexer: code fence backtick count matching" {
  let tokens = tokenize("````\n```\n````\n")
  inspect(tokens[0].token, content="CodeFenceOpen(4, \"\")")
  inspect(tokens[2].token, content="CodeText(\"```\")")
  inspect(tokens[4].token, content="CodeFenceClose")
}

///|
test "lexer: link brackets" {
  let tokens = tokenize("[text](url)\n")
  inspect(tokens[0].token, content="LeftBracket")
  inspect(tokens[1].token, content="Text(\"text\")")
  inspect(tokens[2].token, content="RightBracket")
  inspect(tokens[3].token, content="LeftParen")
  inspect(tokens[4].token, content="Text(\"url\")")
  inspect(tokens[5].token, content="RightParen")
}
```

- [ ] **Step 2: Implement `src/lexer.mbt`**

The lexer structure:

```moonbit
///|
fn char_at(input : String, pos : Int) -> Char? {
  if pos >= input.length() { return None }
  input.code_unit_at(pos).to_char()
}

///|
/// Count consecutive backticks starting at pos.
fn count_backticks(input : String, pos : Int) -> Int {
  let mut n = 0
  while pos + n < input.length() {
    match char_at(input, pos + n) {
      Some('`') => n = n + 1
      _ => break
    }
  }
  n
}

///|
/// Count consecutive '#' starting at pos.
fn count_hashes(input : String, pos : Int) -> Int {
  let mut n = 0
  while pos + n < input.length() && n < 6 {
    match char_at(input, pos + n) {
      Some('#') => n = n + 1
      _ => break
    }
  }
  n
}

///|
/// Lex from LineStart mode. Recognizes block markers at line beginning.
fn lex_line_start(
  input : String,
  pos : Int,
) -> (@core.LexStep[Token], MarkdownLexMode) {
  if pos >= input.length() { return (Done, LineStart) }
  match char_at(input, pos) {
    Some('\n') =>
      // Empty line = BlankLine
      (Produced(@core.TokenInfo::new(BlankLine, 1), next_offset=pos + 1), LineStart)
    Some('#') => {
      let n = count_hashes(input, pos)
      // Must be followed by space (or EOL) to be a heading
      if n > 0 && n <= 6 {
        match char_at(input, pos + n) {
          Some(' ') =>
            // HeadingMarker includes the trailing space
            (Produced(@core.TokenInfo::new(HeadingMarker(n), n + 1), next_offset=pos + n + 1), Inline)
          Some('\n') | None =>
            // Heading with no content (just "##\n")
            (Produced(@core.TokenInfo::new(HeadingMarker(n), n), next_offset=pos + n), Inline)
          _ =>
            // Not a valid heading marker, treat as paragraph text
            lex_inline(input, pos)
        }
      } else {
        lex_inline(input, pos)
      }
    }
    Some('-') | Some('*') | Some('+') =>
      // List marker: must be followed by space
      match char_at(input, pos + 1) {
        Some(' ') =>
          (Produced(@core.TokenInfo::new(ListMarker, 2), next_offset=pos + 2), Inline)
        _ =>
          // Not a list marker in LineStart; fall through to inline
          // (e.g., "**bold**" at line start — * not followed by space)
          lex_inline(input, pos)
      }
    Some('`') => {
      let n = count_backticks(input, pos)
      if n >= 3 {
        // Code fence — consume info string until newline
        let mut info_end = pos + n
        while info_end < input.length() {
          match char_at(input, info_end) {
            Some('\n') | None => break
            _ => info_end = info_end + 1
          }
        }
        let info : StringView = input[pos + n:info_end]
        (Produced(@core.TokenInfo::new(CodeFenceOpen(n, info.to_string()), info_end - pos), next_offset=info_end), CodeBlock(n))
      } else {
        // Less than 3 backticks — not a fence, treat as inline
        lex_inline(input, pos)
      }
    }
    _ =>
      // No block marker recognized — switch to inline for paragraph content
      lex_inline(input, pos)
  }
}

///|
/// Special characters that terminate a Text run in Inline mode.
fn is_inline_special(ch : Char) -> Bool {
  match ch {
    '*' | '`' | '[' | ']' | '(' | ')' | '\n' => true
    _ => false
  }
}

///|
/// Lex from Inline mode. Recognizes emphasis, code, links, text runs.
fn lex_inline(
  input : String,
  pos : Int,
) -> (@core.LexStep[Token], MarkdownLexMode) {
  if pos >= input.length() { return (Done, Inline) }
  match char_at(input, pos) {
    Some('\n') =>
      (Produced(@core.TokenInfo::new(Newline, 1), next_offset=pos + 1), LineStart)
    Some('*') =>
      match char_at(input, pos + 1) {
        Some('*') =>
          (Produced(@core.TokenInfo::new(StarStar, 2), next_offset=pos + 2), Inline)
        _ =>
          (Produced(@core.TokenInfo::new(Star, 1), next_offset=pos + 1), Inline)
      }
    Some('`') =>
      (Produced(@core.TokenInfo::new(Backtick, 1), next_offset=pos + 1), Inline)
    Some('[') =>
      (Produced(@core.TokenInfo::new(LeftBracket, 1), next_offset=pos + 1), Inline)
    Some(']') =>
      (Produced(@core.TokenInfo::new(RightBracket, 1), next_offset=pos + 1), Inline)
    Some('(') =>
      (Produced(@core.TokenInfo::new(LeftParen, 1), next_offset=pos + 1), Inline)
    Some(')') =>
      (Produced(@core.TokenInfo::new(RightParen, 1), next_offset=pos + 1), Inline)
    _ => {
      // Text run: consume until next special char or newline
      let mut end = pos + 1
      while end < input.length() {
        match char_at(input, end) {
          Some(ch) if is_inline_special(ch) => break
          None => break
          _ => end = end + 1
        }
      }
      let text : StringView = input[pos:end]
      (Produced(@core.TokenInfo::new(Text(text.to_string()), end - pos), next_offset=end), Inline)
    }
  }
}

///|
/// Lex from CodeBlock mode. Emits CodeText lines until closing fence.
fn lex_code_block(
  input : String,
  pos : Int,
  fence_len : Int,
) -> (@core.LexStep[Token], MarkdownLexMode) {
  if pos >= input.length() { return (Done, CodeBlock(fence_len)) }
  match char_at(input, pos) {
    Some('\n') =>
      (Produced(@core.TokenInfo::new(Newline, 1), next_offset=pos + 1), CodeBlock(fence_len))
    Some('`') => {
      let n = count_backticks(input, pos)
      if n >= fence_len {
        // Check that rest of line is empty (only whitespace/newline)
        let mut after = pos + n
        let mut is_close = true
        while after < input.length() {
          match char_at(input, after) {
            Some('\n') | None => break
            Some(' ') | Some('\t') => after = after + 1
            _ => { is_close = false; break }
          }
        }
        if is_close {
          // Closing fence (consume backticks + trailing whitespace, not the newline)
          (Produced(@core.TokenInfo::new(CodeFenceClose, after - pos), next_offset=after), LineStart)
        } else {
          // Backticks followed by non-whitespace — treat as code text
          let mut line_end = pos
          while line_end < input.length() {
            match char_at(input, line_end) {
              Some('\n') | None => break
              _ => line_end = line_end + 1
            }
          }
          let text : StringView = input[pos:line_end]
          (Produced(@core.TokenInfo::new(CodeText(text.to_string()), line_end - pos), next_offset=line_end), CodeBlock(fence_len))
        }
      } else {
        // Fewer backticks than fence — treat as code text
        let mut line_end = pos
        while line_end < input.length() {
          match char_at(input, line_end) {
            Some('\n') | None => break
            _ => line_end = line_end + 1
          }
        }
        let text : StringView = input[pos:line_end]
        (Produced(@core.TokenInfo::new(CodeText(text.to_string()), line_end - pos), next_offset=line_end), CodeBlock(fence_len))
      }
    }
    _ => {
      // Code text: consume until newline
      let mut line_end = pos
      while line_end < input.length() {
        match char_at(input, line_end) {
          Some('\n') | None => break
          _ => line_end = line_end + 1
        }
      }
      let text : StringView = input[pos:line_end]
      (Produced(@core.TokenInfo::new(CodeText(text.to_string()), line_end - pos), next_offset=line_end), CodeBlock(fence_len))
    }
  }
}

///|
/// Mode-aware lex step. Dispatches to mode-specific lexer.
pub fn markdown_lex_step(
  input : String,
  pos : Int,
  mode : MarkdownLexMode,
) -> (@core.LexStep[Token], MarkdownLexMode) {
  if pos >= input.length() { return (Done, mode) }
  match mode {
    LineStart => lex_line_start(input, pos)
    Inline => lex_inline(input, pos)
    CodeBlock(n) => lex_code_block(input, pos, n)
  }
}

///|
/// The ModeLexer instance for Markdown.
pub let markdown_mode_lexer : @core.ModeLexer[Token, MarkdownLexMode] = {
  lex_step: markdown_lex_step,
  initial_mode: LineStart,
}

///|
/// Tokenize a full Markdown source string.
pub fn tokenize(
  input : String,
) -> Array[@core.TokenInfo[Token]] raise @core.LexError {
  let (tokens, _modes) = @core.tokenize_with_modes(
    markdown_mode_lexer, input, EOF,
  )
  tokens
}
```

- [ ] **Step 3: Run `moon check` then `moon test`**

```bash
cd loom/examples/markdown && moon check && moon test
```

Update snapshots with `moon test --update` if expectations don't match, then verify they look correct.

- [ ] **Step 4: Commit**

```bash
cd loom/examples/markdown && moon info && moon fmt
cd loom && git add examples/markdown
git commit -m "feat(markdown): mode-aware lexer with LineStart/Inline/CodeBlock modes"
```

---

### Task 3: LanguageSpec, Grammar, block parser, CST→AST conversion, public API

This task wires everything together. The parser and conversion must be real (not stubs) because tests assert fully folded AST values.

**Files:** `src/markdown_spec.mbt`, `src/grammar.mbt`, `src/cst_parser.mbt`, `src/inline_parser.mbt`, `src/block_convert.mbt`, `src/inline_convert.mbt`, `src/parser.mbt`, `src/parser_test.mbt`

- [ ] **Step 1: Write parser tests**

Create `src/parser_test.mbt`. Tests call `parse(...)` and `parse_cst(...)` directly (same package).

```moonbit
///|
test "parse: heading" {
  let block = parse("# Hello\n")
  inspect(block, content="Document([Heading(1, [Text(\"Hello\")])])")
}

///|
test "parse: paragraph" {
  let block = parse("Hello world\n")
  inspect(block, content="Document([Paragraph([Text(\"Hello world\")])])")
}

///|
test "parse: multi-line paragraph" {
  let block = parse("line one\nline two\n\n")
  inspect(
    block,
    content="Document([Paragraph([Text(\"line one\"), Text(\"line two\")])])",
  )
}

///|
test "parse: code block" {
  let block = parse("```python\nx = 1\n```\n")
  inspect(block, content="Document([CodeBlock(\"python\", \"x = 1\")])")
}

///|
test "parse: list" {
  let block = parse("- one\n- two\n")
  inspect(
    block,
    content="Document([UnorderedList([ListItem([Text(\"one\")]), ListItem([Text(\"two\")])])])",
  )
}

///|
test "parse: mixed document" {
  let block = parse("# Title\n\nSome text\n\n- item\n")
  match block {
    Document(blocks) => inspect(blocks.length(), content="3")
    _ => inspect(false, content="true")
  }
}
```

- [ ] **Step 2: Create `src/markdown_spec.mbt`**

```moonbit
///|
/// Token-CST matching for incremental reuse.
/// Payload tokens (Text, CodeText, HeadingMarker, CodeFenceOpen) compare
/// by text content. Fixed tokens compare by kind only.
fn cst_token_matches(
  raw : @seam.RawKind,
  text : String,
  token : Token,
) -> Bool {
  let kind : SyntaxKind = @seam.FromRawKind::from_raw(raw)
  match (kind, token) {
    (TextToken, Text(s)) => text == s
    (CodeTextToken, CodeText(s)) => text == s
    (HeadingMarkerToken, HeadingMarker(_)) => true
    (ListMarkerToken, ListMarker) => true
    (CodeFenceOpenToken, CodeFenceOpen(_, _)) => true
    (CodeFenceCloseToken, CodeFenceClose) => true
    (BlankLineToken, BlankLine) => true
    (StarToken, Star) => true
    (StarStarToken, StarStar) => true
    (BacktickToken, Backtick) => true
    (LeftBracketToken, LeftBracket) => true
    (RightBracketToken, RightBracket) => true
    (LeftParenToken, LeftParen) => true
    (RightParenToken, RightParen) => true
    (NewlineToken, Newline) => true
    (EofToken, EOF) => true
    (ErrorToken, Error(_)) => true
    _ => false
  }
}

///|
pub let markdown_spec : @core.LanguageSpec[Token, SyntaxKind] = @core.LanguageSpec::new(
  whitespace_kind=ErrorToken,  // no trivia — ErrorToken is a placeholder (never used)
  error_kind=ErrorNode,
  root_kind=DocumentNode,
  eof_token=EOF,
  cst_token_matches~,
  reuse_size_threshold=0,
)
```

Note: `whitespace_kind` is set to `ErrorToken` because there are no trivia tokens. The parser never calls trivia-skipping logic since `IsTrivia` always returns false.

- [ ] **Step 3: Create `src/grammar.mbt`**

```moonbit
///|
let mode_state : @core.ModeRelexState[Token] = @core.erase_mode_lexer(
  markdown_mode_lexer, EOF,
)

///|
fn tokenize_for_grammar(
  source : String,
) -> Array[@core.TokenInfo[Token]] raise @core.LexError {
  let (tokens, _) = (mode_state.tokenize)(source)
  tokens
}

///|
pub let markdown_grammar : @loom.Grammar[Token, SyntaxKind, Block] = @loom.Grammar::new(
  spec=markdown_spec,
  tokenize=tokenize_for_grammar,
  fold_node=markdown_fold_node,
  on_lex_error=fn(msg) { Block::Error("lex error: " + msg) },
  error_token=Some(Error("")),
  mode_relex=Some(mode_state),
)
```

- [ ] **Step 4: Create `src/cst_parser.mbt`**

Block-level parser with `parse_root` as entry point. Key functions:
- `parse_root(ctx)` — creates DocumentNode, loops `parse_block`
- `parse_block(ctx)` — dispatches on peek token
- `parse_heading(ctx)` — HeadingNode: emit HeadingMarker, then `parse_inline_content`
- `parse_paragraph(ctx)` — ParagraphNode: `parse_inline_content` with multi-line continuation
- `parse_list(ctx)` — UnorderedListNode: collect ListItemNodes
- `parse_code_block(ctx)` — CodeBlockNode: emit CodeFenceOpen, CodeText lines, CodeFenceClose

Multi-line paragraph: after each Newline, peek at next token. If it's a block marker (HeadingMarker, ListMarker, CodeFenceOpen, BlankLine) or EOF, end the paragraph. Otherwise, emit the Newline and continue inline parsing.

Helper: `fn is_block_boundary(token : Token) -> Bool` returns true for HeadingMarker, ListMarker, CodeFenceOpen, BlankLine, EOF.

`parse_root` is wired into `markdown_spec` via `LanguageSpec::new(parse_root=parse_root)`.

- [ ] **Step 5: Create `src/inline_parser.mbt`**

Inline parser functions, operating on the same `ParserContext`:
- `parse_inline_content(ctx)` — loop until block boundary or Newline-at-block-boundary
- `parse_inline(ctx)` — dispatch: StarStar→parse_bold, Star→parse_italic, Backtick→parse_inline_code, LeftBracket→parse_link, Text→emit
- `parse_bold(ctx)` — BoldNode: emit StarStar, parse_inline_content until StarStar
- `parse_italic(ctx)` — ItalicNode: emit Star, parse_inline_content until Star
- `parse_inline_code(ctx)` — InlineCodeNode: emit Backtick, consume until Backtick
- `parse_link(ctx)` — LinkNode: emit `[`, inline content, `]`, `(`, text, `)`

Error recovery: if closing delimiter not found before Newline/EOF, treat opener as text.

- [ ] **Step 6: Create `src/block_convert.mbt` and `src/inline_convert.mbt`**

`block_convert.mbt`: `fn markdown_fold_node(node, recurse) -> Block` — matches on SyntaxKind of the node, converts children recursively. DocumentNode → `Document(children)`, HeadingNode → extract level from HeadingMarker + inline content, ParagraphNode → `Paragraph(inline_children)`, etc.

`inline_convert.mbt`: Helper functions to convert inline CST children → `Array[Inline]`. BoldNode → `Bold(inline_children)`, TextToken → `Text(token_text)`, etc.

- [ ] **Step 7: Create `src/parser.mbt`**

```moonbit
///|
pub suberror ParseError {
  ParseError(String, Token)
}

///|
pub fn parse_cst(
  source : String,
) -> (@seam.CstNode, Array[@core.Diagnostic[Token]]) raise @core.LexError {
  markdown_grammar.parse_cst(source)
}

///|
pub fn parse_markdown(
  source : String,
) -> (Block, Array[@core.Diagnostic[Token]]) raise @core.LexError {
  let (cst, diags) = parse_cst(source)
  let syntax = @seam.SyntaxNode::from_cst(cst)
  (markdown_fold_node(syntax, fn(child) { markdown_fold_node(child, fn(c) { markdown_fold_node(c, fn(_) { Block::Error("too deep") }) }) }), diags)
}

///|
pub fn parse(source : String) -> Block {
  // Tolerant parse — returns Document with Error nodes on failure
  let (cst, _diags) = try {
    parse_cst(source)
  } catch {
    _ => return Block::Error("lex error")
  }
  let syntax = @seam.SyntaxNode::from_cst(cst)
  let fold = @core.CstFold::new(markdown_grammar.fold_node)
  fold.fold(syntax)
}
```

Note: `parse` is tolerant (never raises) — suitable for error recovery tests. `parse_cst` returns raw CST — suitable for source fidelity tests.

- [ ] **Step 8: Run `moon check` then `moon test`**

```bash
cd loom/examples/markdown && moon check && moon test
```

- [ ] **Step 9: Commit**

```bash
cd loom/examples/markdown && moon info && moon fmt
cd loom && git add examples/markdown
git commit -m "feat(markdown): block parser, grammar wiring, CST→AST, public API"
```

---

### Task 4: Inline markup tests

**Files:** `src/inline_test.mbt`

- [ ] **Step 1: Write inline markup tests**

```moonbit
///|
test "inline: bold" {
  let block = parse("**bold**\n")
  inspect(block, content="Document([Paragraph([Bold([Text(\"bold\")])])])")
}

///|
test "inline: italic" {
  let block = parse("*italic*\n")
  inspect(block, content="Document([Paragraph([Italic([Text(\"italic\")])])])")
}

///|
test "inline: inline code" {
  let block = parse("`code`\n")
  inspect(block, content="Document([Paragraph([InlineCode(\"code\")])])")
}

///|
test "inline: link" {
  let block = parse("[click](http://example.com)\n")
  inspect(
    block,
    content="Document([Paragraph([Link([Text(\"click\")], \"http://example.com\")])])",
  )
}

///|
test "inline: bold inside paragraph" {
  let block = parse("Hello **world** end\n")
  inspect(
    block,
    content="Document([Paragraph([Text(\"Hello \"), Bold([Text(\"world\")]), Text(\" end\")])])",
  )
}

///|
test "inline: bold in heading" {
  let block = parse("# **Bold** title\n")
  inspect(
    block,
    content="Document([Heading(1, [Bold([Text(\"Bold\")]), Text(\" title\")])])",
  )
}
```

- [ ] **Step 2: Fix any failures, run full suite**

- [ ] **Step 3: Commit**

```bash
cd loom/examples/markdown && moon info && moon fmt
cd loom && git add examples/markdown
git commit -m "test(markdown): inline markup tests — bold, italic, code, links"
```

---

### Task 5: Error recovery + source fidelity tests

**Files:** `src/error_recovery_test.mbt`, `src/source_fidelity_test.mbt`

- [ ] **Step 1: Write error recovery tests**

Error recovery tests use `parse` (tolerant API) and `parse_cst` (raw CST). They verify the parser doesn't crash on malformed input.

```moonbit
///|
test "error recovery: unclosed bold" {
  let block = parse("**unclosed\n")
  match block {
    Document(blocks) => inspect(blocks.length() > 0, content="true")
    _ => inspect(false, content="true")
  }
}

///|
test "error recovery: unclosed link" {
  let block = parse("[unclosed\n")
  match block {
    Document(blocks) => inspect(blocks.length() > 0, content="true")
    _ => inspect(false, content="true")
  }
}

///|
test "error recovery: unclosed code fence" {
  let block = parse("```\ncode without close\n")
  match block {
    Document(blocks) => inspect(blocks.length() > 0, content="true")
    _ => inspect(false, content="true")
  }
}
```

- [ ] **Step 2: Write source fidelity tests**

Source fidelity tests use `parse_cst` and verify `SyntaxNode.text() == source`.

```moonbit
///|
test "source fidelity: heading" {
  let source = "# Hello\n"
  let (cst, _) = parse_cst(source)
  let syntax = @seam.SyntaxNode::from_cst(cst)
  inspect(syntax.text() == source, content="true")
}

///|
test "source fidelity: paragraph with bold" {
  let source = "Hello **bold** world\n"
  let (cst, _) = parse_cst(source)
  let syntax = @seam.SyntaxNode::from_cst(cst)
  inspect(syntax.text() == source, content="true")
}

///|
test "source fidelity: code block" {
  let source = "```python\nx = 1\n```\n"
  let (cst, _) = parse_cst(source)
  let syntax = @seam.SyntaxNode::from_cst(cst)
  inspect(syntax.text() == source, content="true")
}

///|
test "source fidelity: mixed document" {
  let source = "# Title\n\nText here\n\n- item one\n- item two\n\n```\ncode\n```\n"
  let (cst, _) = parse_cst(source)
  let syntax = @seam.SyntaxNode::from_cst(cst)
  inspect(syntax.text() == source, content="true")
}
```

- [ ] **Step 3: Run tests, fix any failures**

- [ ] **Step 4: Commit**

```bash
cd loom/examples/markdown && moon info && moon fmt
cd loom && git add examples/markdown
git commit -m "test(markdown): error recovery + source fidelity tests"
```

---

### Task 6: Projection traits

**Files:** `src/proj_traits.mbt`

- [ ] **Step 1: Implement TreeNode + Renderable for Block**

```moonbit
///|
fn inline_text(inlines : Array[Inline]) -> String {
  let buf = StringBuilder::new()
  for item in inlines {
    match item {
      Text(s) => buf.write_string(s)
      Bold(children) => {
        buf.write_string("**")
        buf.write_string(inline_text(children))
        buf.write_string("**")
      }
      Italic(children) => {
        buf.write_string("*")
        buf.write_string(inline_text(children))
        buf.write_string("*")
      }
      InlineCode(s) => {
        buf.write_string("`")
        buf.write_string(s)
        buf.write_string("`")
      }
      Link(children, url) => {
        buf.write_string("[")
        buf.write_string(inline_text(children))
        buf.write_string("](")
        buf.write_string(url)
        buf.write_string(")")
      }
      Error(msg) => buf.write_string("<error: " + msg + ">")
    }
  }
  buf.to_string()
}

///|
pub impl @core.TreeNode for Block with children(self) {
  match self {
    Document(blocks) | UnorderedList(blocks) => blocks
    _ => []
  }
}

///|
pub impl @core.TreeNode for Block with same_kind(self, other) {
  match (self, other) {
    (Document(_), Document(_)) => true
    (Heading(a, _), Heading(b, _)) => a == b
    (Paragraph(_), Paragraph(_)) => true
    (UnorderedList(_), UnorderedList(_)) => true
    (ListItem(_), ListItem(_)) => true
    (CodeBlock(a, _), CodeBlock(b, _)) => a == b
    (Error(_), Error(_)) => true
    _ => false
  }
}

///|
pub impl @core.Renderable for Block with kind_tag(self) {
  match self {
    Document(_) => "Document"
    Heading(n, _) => "H" + n.to_string()
    Paragraph(_) => "Paragraph"
    UnorderedList(_) => "List"
    ListItem(_) => "ListItem"
    CodeBlock(info, _) =>
      if info.length() > 0 { "Code(" + info + ")" } else { "Code" }
    Error(_) => "Error"
  }
}

///|
pub impl @core.Renderable for Block with label(self) {
  match self {
    Document(blocks) => "[" + blocks.length().to_string() + " blocks]"
    Heading(_, inlines) => inline_text(inlines)
    Paragraph(inlines) => {
      let text = inline_text(inlines)
      if text.length() > 40 { text.substring(end=40) + "..." } else { text }
    }
    UnorderedList(items) => "[" + items.length().to_string() + " items]"
    ListItem(inlines) => inline_text(inlines)
    CodeBlock(_, code) =>
      if code.length() > 30 { code.substring(end=30) + "..." } else { code }
    Error(msg) => "Error: " + msg
  }
}

///|
pub impl @core.Renderable for Block with placeholder(_self) {
  "..."
}

///|
pub impl @core.Renderable for Block with unparse(self) {
  match self {
    Document(blocks) => blocks.map(fn(b) { @core.Renderable::unparse(b) }).join("\n")
    Heading(n, inlines) => "#".repeat(n) + " " + inline_text(inlines)
    Paragraph(inlines) => inline_text(inlines)
    UnorderedList(items) => items.map(fn(b) { @core.Renderable::unparse(b) }).join("\n")
    ListItem(inlines) => "- " + inline_text(inlines)
    CodeBlock(info, code) => "```" + info + "\n" + code + "\n```"
    Error(msg) => "<error: " + msg + ">"
  }
}
```

- [ ] **Step 2: Implement TreeNode + Renderable for Inline**

```moonbit
///|
pub impl @core.TreeNode for Inline with children(self) {
  match self {
    Bold(children) | Italic(children) | Link(children, _) => children
    _ => []
  }
}

///|
pub impl @core.TreeNode for Inline with same_kind(self, other) {
  match (self, other) {
    (Text(_), Text(_)) => true
    (Bold(_), Bold(_)) => true
    (Italic(_), Italic(_)) => true
    (InlineCode(_), InlineCode(_)) => true
    (Link(_, _), Link(_, _)) => true
    (Error(_), Error(_)) => true
    _ => false
  }
}

///|
pub impl @core.Renderable for Inline with kind_tag(self) {
  match self {
    Text(_) => "Text"
    Bold(_) => "Bold"
    Italic(_) => "Italic"
    InlineCode(_) => "Code"
    Link(_, _) => "Link"
    Error(_) => "Error"
  }
}

///|
pub impl @core.Renderable for Inline with label(self) {
  match self {
    Text(s) =>
      if s.length() > 30 { s.substring(end=30) + "..." } else { s }
    Bold(children) => "**" + inline_text(children) + "**"
    Italic(children) => "*" + inline_text(children) + "*"
    InlineCode(s) => "`" + s + "`"
    Link(children, url) => "[" + inline_text(children) + "](" + url + ")"
    Error(msg) => "Error: " + msg
  }
}

///|
pub impl @core.Renderable for Inline with placeholder(_self) {
  "..."
}

///|
pub impl @core.Renderable for Inline with unparse(self) {
  inline_text([self])
}
```

- [ ] **Step 3: Run `moon check` then `moon test`**

- [ ] **Step 4: Commit**

```bash
cd loom/examples/markdown && moon info && moon fmt
cd loom && git add examples/markdown
git commit -m "feat(markdown): TreeNode + Renderable for Block and Inline"
```

---

### Task 7: Regression tests + final cleanup

**Files:** All

- [ ] **Step 1: Run regression tests**

```bash
cd loom/examples/lambda && moon test
cd loom/examples/json && moon test
cd loom/loom && moon test
```

All must pass with no regressions.

- [ ] **Step 2: Full markdown suite**

```bash
cd loom/examples/markdown && moon check && moon test
```

- [ ] **Step 3: Format and update interfaces**

```bash
cd loom/examples/markdown && moon info && moon fmt
```

- [ ] **Step 4: Verify .mbti exports**

Check that Block, Inline, parse, parse_cst, parse_markdown, tokenize, markdown_grammar are exported.

- [ ] **Step 5: Final commit**

```bash
cd loom && git add examples/markdown
git commit -m "chore(markdown): final cleanup — interfaces, formatting, all tests green"
```
