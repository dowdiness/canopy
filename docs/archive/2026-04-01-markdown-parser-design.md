# Markdown Parser for Loom

## Why

Canopy needs a third language to validate the framework's genericity and inform
the loomgen code generator design. Markdown is the right choice: its block/inline
duality exercises the new lex-mode system, its structure is fundamentally
different from lambda (expression-based) and JSON (document-based), and it's the
natural content format for the block editor UI planned in TODO §11.

## Scope

**Prerequisite:** Loom lex-modes (PR #67, merged). Grammar `mode_relex` field,
`ModeLexer`, `erase_mode_lexer`, and `tokenize_with_modes` must be available.

In:
- `loom/examples/markdown/` — standalone MoonBit module
- Token enum, SyntaxKind enum, mode-aware lexer, recursive descent parser
- Two-level AST: `Block` and `Inline` enums
- CST→AST conversion
- `TreeNode` + `Renderable` trait impls for Canopy projection
- Tests: lexer, parser, error recovery, incremental
- CST source fidelity: `SyntaxNode.text()` reproduces original input

Out:
- Canopy integration (`lang/markdown/`) — separate spec
- Web UI / block editor — separate spec
- Full CommonMark compliance — we target a practical subset
- Tables, footnotes, HTML blocks, link reference definitions
- Nested lists (flat lists only in V1; nesting is a follow-up)
- AST-level round-trip (CST preserves source; AST is lossy by design)

## Markdown Subset

**Blocks:**
- ATX headings (`# H1` through `###### H6`)
- Paragraphs (text separated by blank lines, may span multiple lines)
- Unordered lists (`-`, `*`, `+` followed by space) — flat only, no nesting
- Fenced code blocks (` ``` ` with optional info string, backtick count matching)

**Inline (within headings and paragraphs):**
- Bold (`**text**`)
- Italic (`*text*`)
- Inline code (`` `code` ``)
- Links (`[text](url)`)

**Structural:**
- Blank lines (block separators)

## Design

### AST: Two Enums

Markdown's block/inline distinction is encoded in the type system:

```moonbit
pub enum Block {
  Document(Array[Block])
  Heading(Int, Array[Inline])          // level 1-6, inline content
  Paragraph(Array[Inline])
  UnorderedList(Array[Block])          // children are ListItems
  ListItem(Array[Inline])              // flat: inline content only (V1)
  CodeBlock(String, String)            // info string, code content
  Error(String)
}

pub enum Inline {
  Text(String)
  Bold(Array[Inline])
  Italic(Array[Inline])
  InlineCode(String)
  Link(Array[Inline], String)          // display text, url
  Error(String)
}
```

Notes:
- No `BlankLine` in AST — blank lines are structural separators consumed by the
  parser, not semantic content.
- `ListItem` contains `Array[Inline]` (flat), not `Array[Block]` (nested).
  Nested lists are a follow-up.
- `Text(String)` includes inter-word spaces. The lexer emits `Text` runs that
  absorb whitespace between words, preserving spaces in the AST.

### Lex Modes

The mode type carries state needed for context-sensitive lexing:

```moonbit
pub enum MarkdownLexMode {
  LineStart           // beginning of line: recognize block markers
  Inline              // within a block: recognize emphasis, links, code spans
  CodeBlock(Int)      // inside fenced code: Int = opening fence backtick count
}
```

`CodeBlock(Int)` carries the opening fence length so the lexer can match closing
fences correctly (a closing fence must have >= the opening count).

Transitions:
- `\n` in any mode → emit `Newline`, switch to `LineStart`
- `# ` in `LineStart` → emit `HeadingMarker(level)`, switch to `Inline`
- `- ` / `* ` / `+ ` in `LineStart` → emit `ListMarker`, switch to `Inline`
- `` ``` `` (n backticks) in `LineStart` → emit `CodeFenceOpen(n, info)`,
  switch to `CodeBlock(n)`
- `` ``` `` (m backticks, m >= n) in `CodeBlock(n)` → emit `CodeFenceClose`,
  switch to `LineStart`
- `` ``` `` (m backticks, m < n) in `CodeBlock(n)` → emit `CodeText` (literal
  backticks, not a fence), stay in `CodeBlock(n)`
- Other in `LineStart` → switch to `Inline` (paragraph content)
- Other in `CodeBlock(n)` → emit `CodeText(line)`, stay in `CodeBlock(n)`

### Token Types

```moonbit
pub enum Token {
  // Block markers (emitted in LineStart mode)
  HeadingMarker(Int)       // # = 1, ## = 2, etc.
  ListMarker               // -, *, +
  CodeFenceOpen(Int, String) // backtick count, info string
  CodeFenceClose           // closing fence (count already matched by lexer)
  BlankLine                // empty line or whitespace-only line

  // Inline markers (emitted in Inline mode)
  Star                     // * (emphasis open/close)
  StarStar                 // ** (strong open/close)
  Backtick                 // ` (inline code delimiter)
  LeftBracket              // [
  RightBracket             // ]
  LeftParen                // (
  RightParen               // )
  Text(String)             // plain text run (includes inter-word spaces)

  // Code content (emitted in CodeBlock mode)
  CodeText(String)         // line of code block content

  // Structural
  Newline                  // line break (non-trivia)
  Error(String)
  EOF
}
```

**No `Whitespace` trivia token.** Inter-word spaces are absorbed into `Text`
runs by the lexer. This ensures the parser and AST preserve all whitespace
without needing a separate trivia mechanism. `Newline` is non-trivia so the
parser can detect block boundaries.

The `IsTrivia` impl returns `false` for all tokens. The parser sees every
token including `Newline`. This is different from lambda/JSON where whitespace
is trivia — Markdown's whitespace is structurally significant.

### SyntaxKind Enum

```moonbit
pub enum SyntaxKind {
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
}
```

### Parser Structure

Single recursive descent parser operating on one token stream via
`ParserContext`. The `cst_parser.mbt` and `inline_parser.mbt` files split the
code for readability, but both operate on the same `ParserContext` instance
within the single `parse_root` call. This matches loom's existing pattern where
`LanguageSpec::new(parse_root=...)` provides one entry point.

**Block parser** (`cst_parser.mbt`):
```
parse_document → while not EOF: parse_block
parse_block → match peek:
  HeadingMarker → parse_heading
  ListMarker → parse_list
  CodeFenceOpen → parse_code_block
  BlankLine → consume (skip)
  Newline → consume (skip)
  _ → parse_paragraph
```

**Multi-line paragraphs:** `parse_paragraph` consumes inline content across
multiple lines. After each `Newline`, it peeks at the next token — if it's a
block marker (`HeadingMarker`, `ListMarker`, `CodeFenceOpen`, `BlankLine`) or
`EOF`, the paragraph ends. Otherwise, the `Newline` is consumed and inline
parsing continues on the next line. This correctly handles:
```
This is a paragraph
that spans two lines.

This is a separate paragraph.
```

**Inline parser** (`inline_parser.mbt`):
```
parse_inline_content → while not at_block_boundary: parse_inline
parse_inline → match peek:
  StarStar → parse_bold
  Star → parse_italic
  Backtick → parse_inline_code
  LeftBracket → parse_link
  Newline → if next is block marker: stop; else: consume, continue
  _ → emit Text
```

`at_block_boundary` returns true for: `BlankLine`, `HeadingMarker`,
`ListMarker`, `CodeFenceOpen`, `EOF`.

**Error recovery:**
- Unclosed emphasis: treat opening `*`/`**` as literal text
- Unclosed link: treat `[` as literal text
- Unclosed code fence: extend to EOF (matches CommonMark behavior)
- Unexpected tokens: wrap in ErrorNode, skip to next block boundary

### Grammar Wiring

```moonbit
let mode_state = erase_mode_lexer(markdown_mode_lexer, Token::EOF)
let markdown_grammar = Grammar::new(
  spec=markdown_spec,
  tokenize=mode_state.tokenize,
  fold_node=markdown_fold_node,
  on_lex_error=fn(msg) { Block::Error(msg) },
  mode_relex=Some(mode_state),
)
```

The `fold_node` function converts `SyntaxNode` → `Block` for block-level nodes,
and dispatches to inline conversion for `HeadingNode` / `ParagraphNode` /
`ListItemNode` children.

### File Structure

```
loom/examples/markdown/
  moon.mod.json
  src/
    token/
      token.mbt            — Token enum + IsTrivia impl (always false)
      moon.pkg
    syntax/
      syntax_kind.mbt      — SyntaxKind enum + ToRawKind/FromRawKind
      moon.pkg
    lexer/
      lexer.mbt            — mode-aware step_lex using ModeLexer
      moon.pkg
    ast/
      ast.mbt              — Block + Inline enums
      proj_traits.mbt      — TreeNode, Renderable impls
      moon.pkg
    grammar.mbt            — Grammar assembly
    markdown_spec.mbt      — LanguageSpec configuration
    cst_parser.mbt         — Block-level parser functions
    inline_parser.mbt      — Inline parser functions (same ParserContext)
    parser.mbt             — Public parse API
    block_convert.mbt      — SyntaxNode → Block conversion
    inline_convert.mbt     — SyntaxNode → Inline conversion
    moon.pkg
    *_test.mbt             — Tests
```

`cst_parser.mbt` and `inline_parser.mbt` are in the same package and share the
`ParserContext`. The split is organizational, not architectural.

### Incremental Parsing

Loom's incremental reuse works at the CST node level. For Markdown:
- Editing inside a paragraph only reparses that paragraph
- Adding/removing a heading only affects that block and its neighbors
- Adding a code fence propagates via lex-mode convergence (re-tokenizes
  until mode stabilizes)

Block reparse optimization (optional, via `block_reparse_spec`):
- Headings, paragraphs, and code blocks are independently reparseable
- List items may require parent context (deferred)

## Testing

**Lexer tests:**
- Mode transitions: LineStart → Inline, LineStart → CodeBlock(n),
  CodeBlock(n) → LineStart
- Token kinds per mode: `*` in LineStart vs Inline, `#` in LineStart vs Inline
- Code fence backtick count: 3 vs 4 backticks, closing fence matching
- Text runs absorb inter-word spaces
- Code fence with info string

**Parser tests:**
- Each block type: heading, paragraph, list, code block
- Multi-line paragraphs (continuation across newlines)
- Inline markup: bold, italic, inline code, links
- Nested inline: bold inside link, italic inside bold
- Multi-block documents
- Blank line handling (separates paragraphs)

**Error recovery tests:**
- Unclosed emphasis
- Unclosed link brackets
- Unclosed code fence (extends to EOF)
- Unexpected tokens in inline context

**Incremental tests:**
- Edit inside paragraph content
- Add/remove heading marker
- Insert/delete code fence (mode propagation)
- Edit inside code block

**Source fidelity test:**
- `SyntaxNode::from_cst(parse_cst(source)).text() == source` for all test inputs
  (CST preserves all tokens, no information loss)

## Acceptance Criteria

- [ ] `moon check` passes with 0 errors
- [ ] `moon test` passes for all markdown tests
- [ ] Headings, paragraphs (including multi-line), lists, code blocks parse correctly
- [ ] Bold, italic, inline code, links parse correctly within blocks
- [ ] Error recovery produces ErrorNode without crashing
- [ ] Lex modes produce correct token kinds per context
- [ ] Code fence backtick count matching works (3 vs 4 backticks)
- [ ] Incremental edit inside a paragraph doesn't reparse other blocks
- [ ] Code fence insertion re-tokenizes correctly via mode convergence
- [ ] CST source fidelity: `SyntaxNode.text()` reproduces original input
- [ ] `TreeNode` + `Renderable` trait impls compile
- [ ] Lambda and JSON regression tests still pass

## Validation

```bash
cd loom/examples/markdown && moon check && moon test
cd loom/examples/lambda && moon test   # regression
cd loom/examples/json && moon test     # regression
```

## Risks

- **Emphasis parsing complexity:** CommonMark's full emphasis rules (left/right
  flanking delimiter runs) are notoriously complex. We implement a simplified
  version: `*` opens/closes italic, `**` opens/closes bold. Nested cases
  (`***bold italic***`) are deferred.
- **MoonBit string handling:** The lexer uses `code_unit_at(pos).to_char()` for
  character access. Markdown with multi-byte UTF-8 characters (emoji in headings)
  may need attention — verify with fuzz tests.
- **No-trivia parser verbosity:** Since all tokens are non-trivia, the parser
  must handle `Newline` tokens explicitly everywhere. This is more verbose than
  lambda/JSON but necessary for Markdown's line-sensitive structure.

## References

- CommonMark spec: https://spec.commonmark.org/
- Loom lex-mode design: `docs/plans/2026-04-01-loom-lex-modes-design.md`
- Lambda parser (reference implementation): `loom/examples/lambda/`
- JSON parser (reference implementation): `loom/examples/json/`
