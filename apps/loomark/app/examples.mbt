///|
const HELLO_EXAMPLE_SOURCE : String = "# Hello World\n\nWelcome to the Canopy Markdown editor.\n\nThis editor has three modes: raw, block, and preview.\n"

///|
const BLOG_EXAMPLE_SOURCE : String = "# Getting Started\n\nCanopy is an incremental projectional editor.\n\n## Features\n\nThe editor supports real-time collaboration via CRDT.\n\nEvery keystroke is incrementally parsed and projected into a structured view."

///|
const LIST_EXAMPLE_SOURCE : String = "# Shopping List\n\nThings to pick up:\n\n- Apples\n- Bread\n- Coffee\n- Dark chocolate"

///|
const CODE_EXAMPLE_SOURCE : String = "# README\n\nA minimal example project.\n\n## Install\n\n```bash\nnpm install\n```\n\n## Usage\n\n- Run the dev server\n- Open the browser\n- Start editing"

///|
const MARKDOWN_DEMO_SOURCE : String =
  $|# Markdown Feature Tour
  $|
  $|A long-form tour of Markdown syntax for editing in the Raw source view.
  $|The standalone document is stored directly as portable Markdown.
  $|
  $|---
  $|
  $|## Headings
  $|
  $|Headings come in six levels, from the document title down to small captions.
  $|
  $|### Level Three Heading
  $|
  $|#### Level Four Heading
  $|
  $|##### Level Five Heading
  $|
  $|###### Level Six Heading
  $|
  $|## Emphasis and inline styles
  $|
  $|Text can be **bold**, *italic*, or ***both at once***. Use `inline code` for
  $|identifiers and command names, and nest styles like *italic with **bold
  $|inside***. Unsupported extensions stay as plain text, so the editor stays
  $|honest about what it renders.
  $|
  $|## Links and autolinks
  $|
  $|- A regular link: [Canopy repository](https://github.com/dowdiness/canopy)
  $|- An automatic URI link: <https://docs.moonbitlang.com>
  $|- An automatic email link: <hello@canopy.example>
  $|- A relative link: [README](./README.md)
  $|
  $|### Images
  $|
  $|Images render from safe destinations:
  $|
  $|![Canopy placeholder](https://placehold.co/640x160?text=Canopy+Markdown "A placeholder image")
  $|
  $|## Lists
  $|
  $|### Unordered lists
  $|
  $|- Apples
  $|- Bread
  $|- Dairy
  $|  - Milk
  $|  - Yogurt
  $|    - Greek yogurt
  $|- Dark chocolate
  $|
  $|### Ordered lists
  $|
  $|1. Clone the repository
  $|2. Initialize submodules
  $|3. Build the editor
  $|   1. Install the MoonBit toolchain
  $|   2. Run `moon build --target js`
  $|4. Open the preview
  $|
  $|## Blockquotes
  $|
  $|> Markdown is a lightweight markup language for writing plain-text
  $|> documents that read well before and after rendering.
  $|>
  $|> > Nested quotes keep their own left border.
  $|>
  $|> — the Canopy team
  $|
  $|## Code blocks
  $|
  $|Fenced code blocks keep their language hint and scroll horizontally when a
  $|line is too long:
  $|
  $|```moon
  $|fn greet(name : String) -> String {
  $|  "Hello, \{'\\'}{name}!"
  $|}
  $|
  $|pub fn main {
  $|  println(greet("Canopy"))
  $|}
  $|```
  $|
  $|```python
  $|def fibonacci(n):
  $|    if n < 2:
  $|        return n
  $|    return fibonacci(n - 1) + fibonacci(n - 2)
  $|```
  $|
  $|```bash
  $|moon check
  $|moon test
  $|moon build --target js
  $|```
  $|
  $|## Thematic breaks
  $|
  $|Content before the rule.
  $|
  $|---
  $|
  $|Content after the rule.
  $|
  $|## Hard breaks
  $|
  $|A hard break ends the line here \{'\\'}
  $|and continues on the next line without a blank paragraph in between.
  $|
  $|## Inline HTML
  $|
  $|Inline HTML stays literal and never executes: <span class="note">not rendered</span>
  $|
  $|## A long section of prose
  $|
  $|Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod
  $|tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam,
  $|quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo
  $|consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse
  $|cillum dolore eu fugiat nulla pariatur.
  $|
  $|Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia
  $|deserunt mollit anim id est laborum. Sed ut perspiciatis unde omnis iste
  $|natus error sit voluptatem accusantium doloremque laudantium, totam rem
  $|aperiam, eaque ipsa quae ab illo inventore veritatis et quasi architecto
  $|beatae vitae dicta sunt explicabo.
  $|
  $|Nemo enim ipsam voluptatem quia voluptas sit aspernatur aut odit aut fugit,
  $|sed quia consequuntur magni dolores eos qui ratione voluptatem sequi
  $|nesciunt. Neque porro quisquam est, qui dolorem ipsum quia dolor sit amet,
  $|consectetur, adipisci velit, sed quia non numquam eius modi tempora
  $|incidunt ut labore et dolore magnam aliquam quaerat voluptatem.
  $|
  $|Ut enim ad minima veniam, quis nostrum exercitationem ullam corporis
  $|suscipit laboriosam, nisi ut aliquid ex ea commodi consequatur? Quis autem
  $|vel eum iure reprehenderit qui in ea voluptate velit esse quam nihil
  $|molestiae consequatur, vel illum qui dolorem eum fugiat quo voluptas nulla
  $|pariatur.
  $|
  $|At vero eos et accusamus et iusto odio dignissimos ducimus qui blanditiis
  $|praesentium voluptatum deleniti atque corrupti quos dolores et quas
  $|molestias excepturi sint occaecati cupiditate non provident, similique sunt
  $|in culpa qui officia deserunt mollitia animi, id est laborum et dolorum
  $|fuga. Et harum quidem rerum facilis est et expedita distinctio.
  $|
  $|Nam libero tempore, cum soluta nobis est eligendi optio cumque nihil
  $|impedit quo minus id quod maxime placeat facere possimus, omnis voluptas
  $|assumenda est, omnis dolor repellendus. Temporibus autem quibusdam et aut
  $|officiis debitis aut rerum necessitatibus saepe eveniet ut et voluptates
  $|repudiandae sint et molestiae non recusandae.
  $|
  $|Itaque earum rerum hic tenetur a sapiente delectus, ut aut reiciendis
  $|voluptatibus maiores alias consequatur aut perferendis doloribus asperiores
  $|repellat. This final paragraph keeps the document long enough that the
  $|preview pane scrolls, proving the editor handles long documents well.

///|
fn examples_bar(emit : @rabbita.Emit[Msg]) -> @rabbita.Html {
  @html.div(
    class="loomark-examples",
    attrs=@html.Attrs::build().role("toolbar").aria_label("Example documents"),
    [
      @html.button(
        type_="button",
        attrs=@html.Attrs::build().aria_label(
          "Apply Markdown feature tour example",
        ),
        on_click=emit(ExampleSelected(MARKDOWN_DEMO_SOURCE)),
        "Demo",
      ),
      @html.button(
        type_="button",
        attrs=@html.Attrs::build().aria_label("Apply Hello example"),
        on_click=emit(ExampleSelected(HELLO_EXAMPLE_SOURCE)),
        "Hello",
      ),
      @html.button(
        type_="button",
        attrs=@html.Attrs::build().aria_label("Guide: Apply Blog example"),
        on_click=emit(ExampleSelected(BLOG_EXAMPLE_SOURCE)),
        "Guide",
      ),
      @html.button(
        type_="button",
        attrs=@html.Attrs::build().aria_label("Apply List example"),
        on_click=emit(ExampleSelected(LIST_EXAMPLE_SOURCE)),
        "List",
      ),
      @html.button(
        type_="button",
        attrs=@html.Attrs::build().aria_label("Apply Code example"),
        on_click=emit(ExampleSelected(CODE_EXAMPLE_SOURCE)),
        "Code",
      ),
    ],
  )
}
