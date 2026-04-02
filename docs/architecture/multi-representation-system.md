# Multi-Representation System

How the `Printable` trait family solves the expression problem for output
formats, and why most new formats are renderers, not traits.

## The Four Core Representations

Every language in Canopy implements four text-output traits, bundled as
`Printable`:

| Trait    | Output                       | Key property                                |
|----------|------------------------------|---------------------------------------------|
| `Show`   | `String`                     | Compact display                             |
| `Debug`  | `Repr` (auto-wrapping)       | Constructor-style structural inspection     |
| `Source`  | `String`                     | Bidirectional: `parse(to_source(x)) == x`   |
| `Pretty` | `Layout[SyntaxCategory]`     | Width-aware, syntax-annotated               |

`Source` is unique: it guarantees a parse roundtrip. `Pretty` is unique: it
carries semantic annotations and width-aware line-breaking decisions.

## The Commuting Diagram

The four representations form a coherent cycle through the parser:

```
         to_source            parse
   AST ────────────→ Text ───────────→ AST
    │                  ↑                 ‖
    │ to_layout        │                 ‖
    ↓                  │                 ‖
  Layout ───────────→ Text               ‖
        render_string     ╲              ‖
                           ╲─────────────╯
                             parse
```

When the diagram commutes — `parse(render_string(to_layout(x))) == x` —
pretty-printing is also bidirectional through the parser. The pretty-printer
becomes a formatting lens: edit the formatted text, parse it back, recover the
AST. The `Source` roundtrip makes this verifiable at runtime.

## Two Families of Output

New output formats fall into two families, each with a different source of
truth:

| Family             | Backed by                         | Examples                        | To add a new format         |
|--------------------|-----------------------------------|---------------------------------|-----------------------------|
| **Text-format**    | `Layout[SyntaxCategory]` (Pretty) | plain, HTML, ANSI, LaTeX        | Add a `render_*` function   |
| **Structure-format** | `TreeNode` + `Debug`            | DOT, JSON, S-expressions, XML   | Add a traversal function    |

Text-format renderers consume the already-resolved `Layout` (or the `Cmd`
stream from `resolve()`). Structure-format renderers walk the tree structure.
Both families extend independently of each other and independently of the
number of languages.

## The Expression Problem, Solved

```
Adding new languages:   implement Printable + Renderable
Adding new text formats: add render function over Layout[A]
Adding new struct formats: add traversal function over TreeNode
```

No existing code changes along either axis. `Printable` + `Layout[A]` form
the open algebraic foundation; render functions are interpreters.

This connects to the TermSym / Finally Tagless architecture already used for
the lambda language:

```
TermSym (language algebra)
  → PrettyLayout impl (each constructor → Layout)
  → Pretty trait (to_layout)
  → render_* family (each output format)
```

TermSym defines the language; render functions define the output formats.

## When New Traits Are Needed

Most output formats do **not** need a new trait. A new `render_*` function
over `Layout[SyntaxCategory]` is sufficient for any text-format variant.

New traits are needed only when a format requires **semantic information**
beyond what `Printable` captures:

- **Typed** — output needs type annotations (e.g. hover, `.d.ts` generation)
- **Documented** — output needs doc comments attached to nodes
- **Graphable** — output needs custom edges beyond parent-child (e.g. scope
  arrows in DOT, which is why `term_to_dot_resolved` takes a `Resolution`)

These are semantic extensions, not format extensions.

## Framework Integration: ViewMode

The protocol layer can dispatch between representation families via a
`ViewMode` concept:

| Mode          | Backed by    | ViewNode shape                              | Use case                |
|---------------|-------------|---------------------------------------------|-------------------------|
| `Structure`   | Renderable  | Tree with kind_tag, label, children          | Structural editing      |
| `Formatted`   | Pretty      | Per-line nodes with text + token_spans       | Formatted code display  |
| `Debug`       | Debug       | Constructor tree (auto-wrapping)             | AST inspection          |
| `Source`      | Source      | Single text node, parseable                  | Minimal roundtrip text  |

All four modes produce ViewNode trees that flow through the same
ViewPatch → Adapter pipeline. Any language implementing `Printable +
Renderable` gets all four views for free.

Modes can be mixed at different granularities: one mode per panel, or even
per node (e.g. structure view for the tree sidebar, formatted view for the
main panel, debug view for the inspector).

## Practical Consequences

- **Safe formatting**: `UserIntent::Format` → `pretty_print(ast)` →
  verify via `parse(formatted) == ast` (Source roundtrip) → `set_text` →
  CRDT records minimal diff → peers see formatting as incremental edits.

- **`layout_to_view_tree`**: The bridge function in `protocol/` that
  converts `Layout[SyntaxCategory]` → ViewNode. This is the first
  text-format renderer targeting ViewNode, and the template for future
  renderers (`render_html`, `render_ansi`, `render_latex`).

- **No new TypeScript per format**: Each renderer lives in MoonBit. The
  adapter renders ViewNode trees generically. New formats require zero
  host-language code.

- **Property-based validation**: The Printable contract enables automatic
  coherence tests for every language implementation:
  - `parse(to_source(x)) == x` (Source roundtrip)
  - `parse(render_string(to_layout(x))) == x` (Pretty roundtrip)
  - `to_source(x).length() <= render_string(to_layout(x)).length()` (Pretty ≥ Source)
