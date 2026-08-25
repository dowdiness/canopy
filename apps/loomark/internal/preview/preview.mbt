///|
let preview_source_id : @loom_core.SourceId = @loom_core.SourceId(
  "loomark:document",
)

///|
pub struct PreviewFailure {
  priv message : String
} derive(Eq)

///|
pub fn PreviewFailure::message(self : PreviewFailure) -> String {
  "Preview generation failed: " + self.message
}

///|
priv struct PreviewTiming {
  started_ms : Double
  diff_ms : Double
  parser_ms : Double
  semantic_ms : Double
  materialize_ms : Double
} derive(Eq)

///|
pub struct PreviewResult {
  priv input_text : String
  priv content : @html.Html
  priv timing : PreviewTiming
} derive(Eq)

///|
pub fn PreviewResult::input_text(self : PreviewResult) -> String {
  self.input_text
}

///|
pub fn PreviewResult::content(self : PreviewResult) -> @html.Html {
  self.content
}

///|
priv enum PreviewEngineState {
  Uninitialized
  Broken(String)
  Ready(
    @loom.Parser[@markdown.Block],
    @markdown.MarkdownSemanticAttachment,
    String
  )
}

///|
pub struct PreviewEngine {
  priv mut state : PreviewEngineState
}

///|
pub fn PreviewEngine::new() -> PreviewEngine {
  { state: Uninitialized }
}

///|
extern "js" fn now_ms() -> Double =
  #| () => performance.now()

///|
extern "js" fn record_preview_measure(
  name : String,
  started_ms : Double,
  duration_ms : Double,
  input_length : Int,
) -> Unit =
  #| (name, started, duration, inputLength) => {
  #|   performance.measure(name, {
  #|     start: started,
  #|     duration,
  #|     detail: { inputLength },
  #|   });
  #| }

///|
extern "js" fn record_preview_total(
  started_ms : Double,
  input_length : Int,
) -> Unit =
  #| (started, inputLength) => {
  #|   performance.measure("loomark-preview-total", {
  #|     start: started,
  #|     end: performance.now(),
  #|     detail: { inputLength },
  #|   });
  #| }

///|
pub fn record_after_render(result : PreviewResult) -> @cmd.Cmd {
  @cmd.custom_cmd(
    _ => {
      let timing = result.timing
      let input_length = result.input_text.length()
      let mut phase_start = timing.started_ms
      record_preview_measure(
        "loomark-preview-diff",
        phase_start,
        timing.diff_ms,
        input_length,
      )
      phase_start = phase_start + timing.diff_ms
      record_preview_measure(
        "loomark-preview-parser",
        phase_start,
        timing.parser_ms,
        input_length,
      )
      phase_start = phase_start + timing.parser_ms
      record_preview_measure(
        "loomark-preview-semantic",
        phase_start,
        timing.semantic_ms,
        input_length,
      )
      phase_start = phase_start + timing.semantic_ms
      record_preview_measure(
        "loomark-preview-materialize",
        phase_start,
        timing.materialize_ms,
        input_length,
      )
      record_preview_total(timing.started_ms, input_length)
    },
    kind=@cmd.after_render,
  )
}

///|
fn render_children(
  source : String,
  node : @markdown.MarkdownIR,
) -> Array[@html.Html] {
  node.children().map(child => render_markdown(source, child))
}

///|
fn node_source(source : String, node : @markdown.MarkdownIR) -> String {
  let origin = node.origin()
  source[origin.start():origin.end()].to_owned()
}

///|
fn render_markdown(source : String, node : @markdown.MarkdownIR) -> @html.Html {
  match node.view() {
    Document => @html.fragment(render_children(source, node))
    Heading(depth~) => {
      let children = render_children(source, node)
      match depth {
        1 => @html.h1(children)
        2 => @html.h2(children)
        3 => @html.h3(children)
        4 => @html.h4(children)
        5 => @html.h5(children)
        6 => @html.h6(children)
        _ => @html.p(children)
      }
    }
    Paragraph => @html.p(render_children(source, node))
    BlockQuote => @html.blockquote(render_children(source, node))
    UnorderedList(..) => @html.ul(render_children(source, node))
    OrderedList(..) => @html.ol(render_children(source, node))
    ListItem(..) | OrderedListItem(..) =>
      @html.li(render_children(source, node))
    CodeBlock(info~, value~) =>
      @html.pre(
        @html.code(attrs=@html.Attrs::build().data_set("language", info), value),
      )
    HtmlBlock(value~) =>
      @html.pre(class="loomark-preview-raw-html", @html.text(value))
    ThematicBreak => @html.hr()
    Text(value~) => @html.text(value)
    Bold => @html.strong(render_children(source, node))
    Italic => @html.em(render_children(source, node))
    InlineCode(value~) => @html.code(value)
    Link(destination~, ..) =>
      @html.span(
        class="loomark-preview-link",
        [..render_children(source, node), @html.text(" (" + destination + ")")],
      )
    Image(destination~, ..) =>
      @html.span(
        class="loomark-preview-image",
        [
          @html.text("Image: "),
          ..render_children(source, node),
          @html.text(" (" + destination + ")"),
        ],
      )
    Autolink(display~, destination~, ..) =>
      @html.span(
        class="loomark-preview-link",
        display + " (" + destination + ")",
      )
    InlineHtml(value~) => @html.code(class="loomark-preview-raw-html", value)
    SoftBreak => @html.text("\n")
    HardBreak(..) => @html.br()
    Unsupported(message~) => {
      let original = node_source(source, node)
      @html.span(
        class="loomark-preview-unsupported",
        if original == "" {
          "Unsupported: " + message
        } else {
          original
        },
      )
    }
    Raw(value~) => @html.text(value)
    Recovered(message~) => {
      let original = node_source(source, node)
      @html.span(
        class="loomark-preview-recovered",
        if original == "" {
          "Recovered: " + message
        } else {
          original
        },
      )
    }
  }
}

///|
fn PreviewEngine::prepare_now(
  self : PreviewEngine,
  input_text : String,
) -> Result[PreviewResult, PreviewFailure] {
  let started_ms = now_ms()
  let diff_started = now_ms()
  let change = match self.state {
    Uninitialized | Broken(_) => None
    Ready(_, _, source) if source == input_text => None
    Ready(_, _, source) =>
      Some(@text_change.compute_text_change(source, input_text))
  }
  let diff_ms = now_ms() - diff_started
  let parser_started = now_ms()
  let attachment = match self.state {
    Broken(message) => return Err({ message, })
    Uninitialized => {
      let parser = @loom.new_parser(
        preview_source_id, input_text, @markdown.markdown_grammar,
      ) catch {
        Failure::Failure(message) => return Err({ message, })
      }
      let attachment = @markdown.MarkdownSemanticAttachment(parser)
      self.state = Ready(parser, attachment, input_text)
      attachment
    }
    Ready(parser, attachment, _) => {
      match change {
        None => ()
        Some(change) => {
          parser.apply_edit(
            @loom_core.Edit::new(
              change.start,
              change.delete_len,
              change.inserted.length(),
            ),
            input_text,
          ) catch {
            Failure::Failure(message) => {
              self.state = Broken(message)
              return Err({ message, })
            }
          }
          self.state = Ready(parser, attachment, input_text)
        }
      }
      attachment
    }
  }
  let parser_ms = now_ms() - parser_started
  let semantic_started = now_ms()
  let document = attachment.document()
  let semantic_ms = now_ms() - semantic_started
  let materialize_started = now_ms()
  let content = render_markdown(input_text, document)
  let materialize_ms = now_ms() - materialize_started
  Ok({
    input_text,
    content,
    timing: { started_ms, diff_ms, parser_ms, semantic_ms, materialize_ms },
  })
}

///|
/// Prepare Preview after the current browser input task has returned.
pub fn PreviewEngine::prepare(
  self : PreviewEngine,
  input_text : String,
  result~ : @cmd.Emit[Result[PreviewResult, PreviewFailure]],
) -> @cmd.Cmd {
  @cmd.delay(
    @cmd.custom_cmd(scheduler => {
      scheduler.add(result(self.prepare_now(input_text)))
    }),
    0,
  )
}
