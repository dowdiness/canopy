// Minimal neutral loom grammar for TestExpr, plus the editor factory.
//
// Grammar (s-expression-ish):
//   expr := IDENT                    -> Leaf
//         | IDENT '(' expr* ')'      -> Branch(tag, children)
//   root := expr*                    -> Branch("", children)
//
// The lexer/parser/fold/projection are TOTAL over arbitrary input: any
// byte run that is not an identifier or paren becomes a gap (Whitespace
// trivia for blank gaps, an Error token otherwise), and unparseable spans
// fold to an error Leaf. This matters because the editor unconditionally
// converts the syntax tree to a ProjNode and assumes malformed/partial
// input still yields an AST (e.g. sync_editor_text_wbtest inserts emoji /
// ZWJ / surrogate halves).

// === Tokens ===

///|
enum TestToken {
  Ident
  LParen
  RParen
  Whitespace
  Error
  Eof
} derive(Eq)

///|
impl @seam.IsTrivia for TestToken with fn is_trivia(self) {
  self is Whitespace
}

///|
impl @seam.IsEof for TestToken with fn is_eof(self) {
  self is Eof
}

///|
impl @seam.ToRawKind for TestToken with fn to_raw(self) {
  @seam.RawKind(
    match self {
      Ident => 0
      LParen => 1
      RParen => 2
      Whitespace => 3
      Error => 4
      Eof => 5
    },
  )
}

// === Syntax kinds ===

///|
enum TestKind {
  IdentToken
  LParenToken
  RParenToken
  WhitespaceToken
  ErrorToken
  EofToken
  RootNode
  LeafNode
  BranchNode
  ErrorNode
} derive(Eq, Debug)

///|
impl @seam.ToRawKind for TestKind with fn to_raw(self) {
  @seam.RawKind(
    match self {
      IdentToken => 0
      LParenToken => 1
      RParenToken => 2
      WhitespaceToken => 3
      ErrorToken => 4
      EofToken => 5
      RootNode => 6
      LeafNode => 7
      BranchNode => 8
      ErrorNode => 9
    },
  )
}

///|
impl @seam.FromRawKind for TestKind with fn from_raw(raw) {
  match raw.0 {
    0 => IdentToken
    1 => LParenToken
    2 => RParenToken
    3 => WhitespaceToken
    4 => ErrorToken
    5 => EofToken
    6 => RootNode
    7 => LeafNode
    8 => BranchNode
    _ => ErrorNode
  }
}

// === Lexer (total over arbitrary input) ===

///|
fn is_ident_char(c : Char) -> Bool {
  c is ('a'..='z' | 'A'..='Z' | '0'..='9' | '_')
}

///|
fn lex_test_expr(source : String) -> @loomcore.LexResult[TestToken] {
  let located : Array[@loomcore.LocatedToken[TestToken]] = []
  let n = source.length()
  let mut i = 0
  while i < n {
    match source.code_unit_at(i).to_char() {
      Some('(') => {
        located.push(
          @loomcore.LocatedToken::LocatedToken(LParen, start=i, end=i + 1),
        )
        i = i + 1
      }
      Some(')') => {
        located.push(
          @loomcore.LocatedToken::LocatedToken(RParen, start=i, end=i + 1),
        )
        i = i + 1
      }
      Some(c) if is_ident_char(c) => {
        let start = i
        i = i + 1
        while i < n {
          match source.code_unit_at(i).to_char() {
            Some(c2) if is_ident_char(c2) => i = i + 1
            _ => break
          }
        }
        located.push(@loomcore.LocatedToken::LocatedToken(Ident, start~, end=i))
      }
      // whitespace, punctuation, garbage, or a lone surrogate half: skip and
      // let from_located_tokens fill the gap (blank -> Whitespace trivia,
      // non-blank -> Error token). This keeps the lexer total.
      _ => i = i + 1
    }
  }
  @loomcore.LexResult::from_located_tokens(
    source,
    located,
    gap_token=fn(_text, _start, _end) { Whitespace },
    gap_error_token=fn(_text, _start, _end) { Error },
    diagnose_nonblank_gaps=false,
  )
}

// === Parser ===

///|
fn test_parse_root(ctx : @loomcore.ParserContext[TestToken, TestKind]) -> Unit {
  while !ctx.at_eof() {
    if ctx.at(Ident) {
      parse_test_expr(ctx)
    } else {
      ctx.bump_error()
    }
  }
}

///|
fn parse_test_expr(ctx : @loomcore.ParserContext[TestToken, TestKind]) -> Unit {
  if ctx.peek_nth(1) is LParen {
    ctx.node(BranchNode, fn() {
      ctx.emit_token(IdentToken)
      ctx.emit_token(LParenToken)
      while !ctx.at_eof() && !ctx.at(RParen) {
        if ctx.at(Ident) {
          parse_test_expr(ctx)
        } else {
          ctx.bump_error()
        }
      }
      if ctx.at(RParen) {
        ctx.emit_token(RParenToken)
      } else {
        // Unclosed '(' is the one structural error TestExpr reports, so the
        // editor's generic "get_errors reflects diagnostics / clears on fix"
        // contract is testable. Garbage chars stay silent (lexer gaps), so
        // totality is unaffected.
        ctx.report_at_current(message="unclosed '('")
      }
    })
  } else {
    ctx.node(LeafNode, fn() { ctx.emit_token(IdentToken) })
  }
}

// === Fold (CST -> TestExpr) ===

///|
fn test_node_ident(node : @seam.SyntaxNode) -> String {
  match node.direct_token_of_kind(IdentToken.to_raw()) {
    Some(tok) => tok.text()
    None => ""
  }
}

///|
fn test_fold_node(
  node : @seam.SyntaxNode,
  recurse : (@seam.SyntaxNode) -> TestExpr,
) -> TestExpr {
  let kind : TestKind = @seam.FromRawKind::from_raw(node.kind())
  match kind {
    RootNode => Branch("", node.children().map(recurse))
    BranchNode => Branch(test_node_ident(node), node.children().map(recurse))
    LeafNode => Leaf(test_node_ident(node))
    ErrorNode => Leaf("<error>")
    _ => Leaf("<unknown>")
  }
}

// === Grammar ===

///|
let test_spec : @loomcore.LanguageSpec[TestToken, TestKind] = @loomcore.LanguageSpec::new(
  WhitespaceToken,
  ErrorNode,
  RootNode,
  Eof,
  parse_root=test_parse_root,
  reuse_size_threshold=0,
)

///|
let test_grammar : @loom.Grammar[TestToken, TestKind, TestExpr] = @loom.Grammar::new(
  spec=test_spec,
  lex=lex_test_expr,
  fold_node=test_fold_node,
  incremental_relex_enabled=false,
)

// === Projection (SyntaxNode -> ProjNode[TestExpr]) ===

///|
fn syntax_to_test_proj(
  node : @seam.SyntaxNode,
  counter : Ref[Int],
) -> @core.ProjNode[TestExpr] {
  let kind : TestKind = @seam.FromRawKind::from_raw(node.kind())
  match kind {
    LeafNode => @core.ProjNode::leaf(Leaf(test_node_ident(node)), node, counter)
    // RootNode is the implicit document Branch (empty tag); a BranchNode
    // carries the identifier tag. Otherwise both fold their children the
    // same way.
    BranchNode | RootNode => {
      let tag = if kind is RootNode { "" } else { test_node_ident(node) }
      let kids = node.children().map(fn(c) { syntax_to_test_proj(c, counter) })
      let values = kids.map(fn(k) { k.kind })
      @core.ProjNode::branch(
        Branch(tag, values),
        node.start(),
        node.end(),
        kids,
        counter,
      )
    }
    ErrorNode => @core.ProjNode::leaf(Leaf("<error>"), node, counter)
    _ => @core.ProjNode::leaf(Leaf("<unknown>"), node, counter)
  }
}

///|
/// Memo builder for the TestExpr projection pipeline (3 memos, no
/// language-specific token sub-spans — the no-op filler leaves node ranges
/// to the generic machinery).
fn build_test_projection_memos(
  parser : @loom.Parser[TestExpr],
) -> (
  @incr.Derived[@core.ProjNode[TestExpr]?],
  @incr.Derived[Map[@core.NodeId, @core.ProjNode[TestExpr]]],
  @incr.Derived[@core.SourceMap],
) {
  @core.build_projection_memos(
    parser.runtime(),
    parser.syntax_tree(),
    syntax_to_test_proj,
    fn(_source_map, _syntax, _proj) {  },
    label="testexpr",
  )
}

// === Editor factory ===

///|
/// Construct a language-agnostic editor over the neutral TestExpr grammar,
/// with all-None capabilities (no eval / decorations / annotations).
pub fn new_test_editor(
  agent_id : String,
  capture_timeout_ms? : Int = 500,
  parent_runtime? : @incr.Runtime,
) -> @editor.SyncEditor[TestExpr] {
  @editor.SyncEditor::new_generic(
    agent_id,
    fn(s, rt) { @loom.new_parser(s, test_grammar, runtime?=rt) },
    build_test_projection_memos,
    capture_timeout_ms~,
    parent_runtime?,
  )
}

///|
/// Read the parsed TestExpr AST (the fold result); empty source yields the
/// empty document Branch("", []).
pub fn get_test_ast(editor : @editor.SyncEditor[TestExpr]) -> TestExpr {
  match editor.get_tree() {
    Some(ast) => ast
    None => Branch("", [])
  }
}
