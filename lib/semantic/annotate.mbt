///|
/// Symbolic annotation: assign structural roles based on block position.
///
/// Sliding window over Document(children). Rules are positional:
///   - Paragraph at index 0 (document opens with a paragraph) → Abstract
///   - Paragraph after Heading → SectionIntro
///   - Paragraph before CodeBlock → CodeExplanation
///   - List after Heading → KeyPoints
///   - Everything else → Unknown (not Unclassified — leave room for LLM)
///
/// Priority when multiple rules apply: SectionIntro > CodeExplanation > Abstract.
pub fn annotate_symbolic(doc : @md.Block) -> FixedArray[Confidence[Role]] {
  let children = match doc {
    @md.Document(c) => c
    _ => return []
  }
  let result : FixedArray[Confidence[Role]] = FixedArray::make(
    children.length(),
    Unknown,
  )
  for i in 0..<children.length() {
    if classify(i, children) is Some(r) {
      result[i] = RuleBased(r)
    }
  }
  result
}

///|
fn classify(index : Int, children : Array[@md.Block]) -> Role? {
  let prev = children.get(index - 1)
  match children[index] {
    @md.Paragraph(_) if prev is Some(@md.Heading(_, _)) => Some(SectionIntro)
    @md.Paragraph(_) if children.get(index + 1) is Some(@md.CodeBlock(_, _)) =>
      Some(CodeExplanation)
    @md.Paragraph(_) if index == 0 => Some(Abstract)
    @md.UnorderedList(_) if prev is Some(@md.Heading(_, _)) => Some(KeyPoints)
    _ => None
  }
}
