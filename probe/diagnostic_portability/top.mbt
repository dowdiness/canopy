///|
/// Deterministic portability boundary: consumes only Lambda's public parser and
/// Loom's neutral diagnostic values, with source text supplied externally.
fn portable_missing_else_probe() -> (String, String, Bool) raise {
  let source_id = @loomcore.SourceId::SourceId("standalone-source")
  let source = "if x then y"
  let (_, diagnostics) = @lambda.parse_cst(source_id, source) catch {
    _ => fail("unexpected lex error")
  }
  guard diagnostics
    .items()
    .iter()
    .find_first(diagnostic => {
      match diagnostic.code() {
        Some(code) => code.value() == "loom.lambda.expected_else"
        None => false
      }
    })
    is Some(diagnostic) else {
    fail("expected loom.lambda.expected_else diagnostic")
  }
  let fixes = diagnostic.fixes()
  guard fixes.length() == 1 else {
    fail("expected exactly one missing-else fix")
  }
  let provider = @loomcore.SourceProvider(requested => {
    if requested == source_id {
      Some(
        @loomcore.DiagnosticSourceFile(
          "standalone.lambda",
          source,
          @loomcore.LineIndex::new(source),
        ),
      )
    } else {
      None
    }
  })
  let rendered = diagnostic.render_plain(provider) catch {
    _ => fail("expected external source provider to render diagnostic")
  }
  let fixed = fixes[0].apply(source_id, source) catch {
    _ => fail("expected validated missing-else fix to apply")
  }
  let (_, reparsed) = @lambda.parse_cst(source_id, fixed) catch {
    _ => fail("unexpected lex error after fix")
  }
  let code_is_gone = !reparsed
    .items()
    .iter()
    .any(diagnostic => {
      match diagnostic.code() {
        Some(code) => code.value() == "loom.lambda.expected_else"
        None => false
      }
    })
  (rendered, fixed, code_is_gone)
}

///|
test "portable named missing-else diagnostic renders, fixes, and clears" {
  let (rendered, fixed, code_is_gone) = portable_missing_else_probe()
  inspect(
    rendered,
    content=(
      #|error[loom.lambda.expected_else]: Expected else
      #|--> standalone.lambda
      #|primary 1:12-1:12
      #|  1 | if x then y
      #|    |            ^
      #|= note: An if expression requires an else branch
    ),
  )
  inspect(fixed, content="if x then y else _")
  inspect(code_is_gone, content="true")
}
