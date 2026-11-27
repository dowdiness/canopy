# Resume entries

A Loomark-local experiment
([#1484](https://github.com/dowdiness/canopy/issues/1484)): extract explicitly
recorded observations, decisions, and next steps from selected Markdown
documents, each with its exact source range. It does not change the Canopy
product direction and is not yet used by `app`, `documents`, or Preview.

`extract` takes `(key, text)` pairs in selection order. A key that appears more
than once is used at its first occurrence. Each result keeps the key, the exact
source it was extracted from, and its entries, or `None` when the source could
not be parsed.

Parsing uses the same `parse_cst` → Markdown IR path as `document_lead`. Only
top-level blocks are read, so block quotes and code blocks are never entered:

- `#` clears the project and kind;
- `##` sets the project to its exact heading text and clears the kind;
- `###` `試したこと`, `判断`, and `次にやること` set the kind; another `###`
  title or a deeper heading clears it;
- each top-level item of a list under a kind becomes one entry. Nested content
  stays inside its item. A kind without a project yields entries whose
  `project` is `None` (unclassified).

These headings are an experimental convention, not a formal syntax. Free text
is not extracted and is left unchanged. No date, recency, completion, or
precedence between entries is inferred; projects are grouped only by exact text.

An entry's `start`/`end` is a half-open UTF-16 range, the same unit as
`TextChange` and the textarea selection, ending at the item's last character.
The entry's text is that slice of `ResumeDocument::source`. A range is
meaningful only for the exact source it came from:
`ResumeDocument::is_current(key, text)` is true only when both the key and the
text match. There is no public per-document revision, so callers
re-extract when it is false.

Tests use the agent kit v0.2 fixtures (`resume-a`, `resume-b`, `resume-edge`)
copied into `resume_entries_test.mbt` for R01–R05, R09, and the R06 staleness
check, plus the context rules, UTF-16 offsets, and nested items. UI
integration (R07, R08) is a separate step.
