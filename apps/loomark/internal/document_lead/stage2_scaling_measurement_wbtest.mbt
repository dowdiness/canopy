///|
/// Stage 2 size-scaling evidence only. This file deliberately reuses the
/// production parser, experimental IR conversion seam, and full `extract` API.
/// Fixture construction is outside timed spans; every fixture ends at a complete
/// Markdown block (never a byte/prefix cut).
fn scaling_default_targets() -> Array[Int] {
  [1000, 10000, 50000, 100000, 250000, 500000, 1270000]
}

///|
fn scaling_env(name : String, fallback : String) -> String {
  match @env.get_env_var(name) {
    Some(value) => value
    None => fallback
  }
}

///|
fn scaling_int_env(name : String, fallback : Int) -> Int {
  @string.parse_int(scaling_env(name, fallback.to_string())) catch {
    _ => fallback
  }
}

///|
fn scaling_targets() -> Array[Int] {
  let configured = scaling_env("LOOMARK_STAGE2_SCALING_TARGET", "")
  if configured == "" {
    scaling_default_targets()
  } else {
    [@string.parse_int(configured) catch { _ => 0 }]
  }
}

///|
fn scaling_corpora() -> Array[String] {
  let configured = scaling_env("LOOMARK_STAGE2_SCALING_CORPUS", "all")
  if configured == "all" {
    ["ordinary", "structure"]
  } else {
    [configured]
  }
}

///|
fn scaling_phases() -> Array[String] {
  let configured = scaling_env("LOOMARK_STAGE2_SCALING_PHASE", "all")
  if configured == "all" {
    ["parse", "ir", "extract"]
  } else {
    [configured]
  }
}

///|
fn scaling_block(corpus : String, index : Int) -> String {
  if corpus == "ordinary" {
    "# Ordinary heading \{index}\n\nA paragraph with **inline** text and a [link](https://example.com).\n\n"
  } else {
    "# Structure heading \{index}\n\n- [ ] task item \{index}\n  - nested child \{index}\n    - third level child\n\n> quoted block \{index}\n\n```moonbit\nlet value = \{index}\nlet next = value\n```\n\n"
  }
}

///|
fn scaling_fixture(corpus : String, target : Int) -> String {
  // The fixture alphabet is ASCII, so String.length() is its UTF-8 byte count.
  // Keep the builder and byte counter outside every measured span.
  let builder = StringBuilder(size_hint=target)
  let mut bytes = 0
  let mut index = 0
  while bytes < target {
    let block = scaling_block(corpus, index)
    builder.write_string(block)
    bytes += block.length()
    index += 1
  }
  builder.to_string()
}

///|
fn scaling_node_count(node : @markdown.MarkdownIR) -> Int {
  1 +
  node
  .children()
  .map(child => scaling_node_count(child))
  .fold(init=0, (sum, count) => sum + count)
}

///|
fn scaling_parsed(source : String) -> (@seam.SyntaxNode, @loom.DiagnosticSet) {
  let (cst, diagnostics) = @markdown.parse_cst(name_source_id, source) catch {
    error => abort("scaling fixture parser failure: \{error}")
  }
  (@seam.SyntaxNode::from_cst(cst), diagnostics)
}

///|
fn scaling_ir(
  root : @seam.SyntaxNode,
  diagnostics : @loom.DiagnosticSet,
) -> @markdown.MarkdownIR {
  @markdown.experimental_markdown_ir_from_syntax_with_diagnostics(
    name_source_id,
    root,
    diagnostics,
    extensions=@markdown.MarkdownExtensions::task_list(),
  )
}

///|
fn scaling_sample(
  corpus : String,
  target : Int,
  phase : String,
  sample : Int,
  record : Bool,
  run : String,
  source : String,
  root : @seam.SyntaxNode?,
  diagnostics : @loom.DiagnosticSet?,
  retained_cst : Ref[@seam.CstNode?],
  retained_ir : Ref[@markdown.MarkdownIR?],
  retained_output : Ref[DocumentLead?],
  checksum : Ref[Int],
) -> Unit {
  let started = @bench.monotonic_clock_start()
  if phase == "parse" {
    let (cst, _) = @markdown.parse_cst(name_source_id, source) catch {
      error => abort("scaling fixture parser failure: \{error}")
    }
    retained_cst.val = Some(cst)
    let elapsed_us = @bench.monotonic_clock_end(started)
    checksum.val += source.char_length()
    if record {
      println(
        "SAMPLE run=\{run} corpus=\{corpus} target=\{target} bytes=\{@utf8.encode(source).length()} phase=\{phase} sample=\{sample} us=\{elapsed_us}",
      )
    }
    return
  } else if phase == "ir" {
    let document = scaling_ir(root.unwrap(), diagnostics.unwrap())
    retained_ir.val = Some(document)
    let elapsed_us = @bench.monotonic_clock_end(started)
    checksum.val += scaling_node_count(document)
    if record {
      println(
        "SAMPLE run=\{run} corpus=\{corpus} target=\{target} bytes=\{@utf8.encode(source).length()} phase=\{phase} sample=\{sample} us=\{elapsed_us}",
      )
    }
    return
  } else {
    let output = extract(
      source,
      limits=test_limits(primary=80, description=160),
    )
    retained_output.val = Some(output)
    let elapsed_us = @bench.monotonic_clock_end(started)
    checksum.val += output.primary().char_length() +
      output.description().char_length()
    if record {
      println(
        "SAMPLE run=\{run} corpus=\{corpus} target=\{target} bytes=\{@utf8.encode(source).length()} phase=\{phase} sample=\{sample} us=\{elapsed_us}",
      )
    }
    return
  }
}

///|
fn scaling_metadata(source : String, phase : String) -> Unit {
  let (root, diagnostics) = scaling_parsed(source)
  let document = scaling_ir(root, diagnostics)
  let output = extract(source, limits=test_limits(primary=80, description=160))
  println(
    "METADATA phase=\{phase} bytes=\{@utf8.encode(source).length()} chars=\{source.char_length()} ir_nodes=\{scaling_node_count(document)} top_level_blocks=\{document.children().length()} output_chars=\{output.primary().char_length() + output.description().char_length()}",
  )
}

///|
/// A configurable single-cell runner. The external runner invokes this test
/// once per cell/process, so cold repetitions never get pooled with warm data.
test "stage2 size scaling raw samples" {
  if scaling_env("LOOMARK_STAGE2_SCALING", "") != "1" {
    return
  }
  let sample_count = scaling_int_env("LOOMARK_STAGE2_SCALING_SAMPLE_COUNT", 20).max(
    1,
  )
  let warmups = scaling_int_env("LOOMARK_STAGE2_SCALING_WARMUPS", 20).max(0)
  let run = scaling_env("LOOMARK_STAGE2_SCALING_RUN", "unspecified")
  let checksum = Ref(0)
  let retained_cst : Ref[@seam.CstNode?] = Ref(None)
  let retained_ir : Ref[@markdown.MarkdownIR?] = Ref(None)
  let retained_output : Ref[DocumentLead?] = Ref(None)
  for corpus in scaling_corpora() {
    for target in scaling_targets() {
      let source = scaling_fixture(corpus, target)
      let phase = scaling_phases()[0]
      // IR-only setup must parse first. This is a parser prerequisite, not a
      // cold parser measurement; no IR or output metadata is computed here.
      let (root, diagnostics) = if phase == "ir" {
        let (parsed_root, parsed_diagnostics) = scaling_parsed(source)
        (Some(parsed_root), Some(parsed_diagnostics))
      } else {
        (None, None)
      }
      let setup = if phase == "ir" { "parser-prerequisite" } else { "none" }
      // Do not inspect source metadata before a cold parse/extract call.
      println(
        "FIXTURE run=\{run} corpus=\{corpus} target=\{target} phase=\{phase} setup=\{setup}",
      )
      for sample in 0..<warmups {
        scaling_sample(
          corpus,
          target,
          phase,
          -sample - 1,
          false,
          run,
          source,
          root,
          diagnostics,
          retained_cst,
          retained_ir,
          retained_output,
          checksum,
        )
      }
      for sample in 0..<sample_count {
        scaling_sample(
          corpus, target, phase, sample, true, run, source, root, diagnostics, retained_cst,
          retained_ir, retained_output, checksum,
        )
      }
      // Metadata is intentionally first computed after all timed samples.
      scaling_metadata(source, phase)
    }
  }
  println("SCALING_CHECKSUM run=\{run} value=\{checksum.val}")
}
