# Note index prototype

A clickable prototype of the Loomark Document index, written in MoonBit with
Rabbita. The index itself is
[`internal/document_index`](../../internal/document_index), which shows each
note's Document lead from Loomark's own `internal/document_lead` and packs the
cards with [`dowdiness/skyline`](../../../../modules/skyline). This page hosts
it with in-memory notes and a plain editor to try the UX; the production app
does not import this example.

The code follows [Functional Core / Imperative Shell](../../../../docs/architecture/functional-core-imperative-shell.md):

- **Core** (`internal/document_index`'s `layout.mbt`, `decisions.mbt`,
  `cursor.mbt`): calculations over plain values. `layout.mbt` lists the card
  widths each document may be drawn at, parses measured heights into
  `MeasuredCard`s (or nothing while one is missing), and packs them with
  skyline. `decisions.mbt` decides what a key press does, which card an
  arrow moves to from the packed boxes, and which grid width to use from a
  measured width.
- **App** (`internal/document_index`'s `document_index.mbt` and `view.mbt`,
  and this example's `main.mbt` and `view.mbt`): Rabbita state transitions
  and HTML. The index asks `@browser` and `@timeout` for focus, the grid
  width, card heights, and waits that exist only while their state does,
  such as a highlight fading or the width holding still. This example routes
  between the index and the editor and deletes notes.
- **Shell** (`shell.mbt` and `internal/browser`): the only code that touches
  the DOM. At startup `shell.mbt` reads the URL and mounts the app once the
  card fonts have loaded. After render `internal/browser` observes the grid
  width element the index draws with a `ResizeObserver`, resolves the
  off-screen `#card-measure` layer and reads its cards' heights in one pass,
  and moves focus. When font faces finish loading after startup it reports
  `FontsLoaded`, and every card is measured again.

The browser breaks and clamps card text, so nothing in MoonBit predicts a
height or a width: no card is shown until the grid width is measured. Cards not measured yet are drawn off screen at the widths they may
take; until all visible cards are measured, the grid keeps showing the layout
it last packed (`ShownGrid`), so it never shows a guessed height. All listed
notes are measured, not only visible ones, so a search never waits.

The index's styles are `internal/document_index/document_index.css`, which
Loomark imports and `public/document_index.css` links to. `public/styles.css`
holds only this page's tokens, its editor stand-in, and how it covers the
index under the editor.

## Run

```sh
moon build --target js --release apps/loomark/examples/note_index
P=apps/loomark/examples/note_index/public
cp _build/js/release/build/dowdiness/loomark/examples/note_index/note_index.js $P/
mkdir -p $P/fonts && cp apps/loomark/public/fonts/{iAWriterQuattroS-Regular-2.000.woff2,IBMPlexSansJP-Regular-1.004.woff2} $P/fonts/
python3 -m http.server 8000 --directory $P
```

Notes live in memory; reloading restores the samples.

## Browser tests

`scripts/test-loomark-standalone-e2e.sh` builds this page into
`apps/loomark/.note-index-e2e-dist` and runs
[`tests/note-index.spec.ts`](../vanilla/tests/note-index.spec.ts) against it.
The tests check that packed slots match the cards the browser draws, after a
resize and a late font, and that arrow keys and focus follow the cards on
screen.

## Things to try

- Open a card, change it, and press Escape. The index reappears in its old
  order, then the note slides to the first position, keeps focus, and is
  announced.
- Arrow keys move between cards by position, Home and End jump to the first
  and last, `/` focuses Search, and `N` opens a New document. Tab and screen
  readers follow recency order.
- Resize the window; the columns follow the width.
- Delete a card with its trash button. After confirmation it stays in place,
  Pending deletion, for a moment, then the other cards move into its place
  and focus moves to the card that takes it.
- Long code and notes take two columns. `Packer::preview` places such a
  wide card at one column instead when it would trap more than 60px of
  column height.
