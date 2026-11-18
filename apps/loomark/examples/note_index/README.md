# Note index prototype

A clickable prototype of a Loomark note index page, written in MoonBit with
Rabbita. Cards show each note's Document lead from Loomark's own
`internal/document_lead` and are packed with
[`dowdiness/skyline`](../../../../modules/skyline). It exists to try the UX;
the production app does not import it.

The code follows [Functional Core / Imperative Shell](../../../../docs/architecture/functional-core-imperative-shell.md):

- **Core** (`layout.mbt`, `decisions.mbt`, `cursor.mbt`): calculations over
  plain values. `layout.mbt` lists the card widths each note may be drawn at,
  parses measured heights into `MeasuredNote`s (or nothing while one is
  missing), and packs them with skyline. `decisions.mbt` decides what a key
  press does, which card an arrow moves to from the packed boxes, and which
  grid width to use from a measured width.
- **App** (`main.mbt`, `view.mbt`): Rabbita state transitions and HTML. It
  uses no `@dom`; it asks the shell for focus, the grid width, card heights,
  and waits that exist only while their state does, such as a highlight
  fading or the width holding still.
- **Shell** (`shell.mbt`): the only code that touches the DOM. At startup it
  reads the URL, resolves `#grid-width`, and mounts the app once the card
  fonts have loaded. After render it resolves the off-screen `#card-measure`
  layer and reads its cards' heights in one pass, passes the resolved
  `#grid-width` element to a `ResizeObserver`, and moves focus. When font
  faces finish loading after startup it reports `FontsLoaded`, and every card
  is measured again.

The browser breaks and clamps card text, so nothing in MoonBit predicts a
height. Cards not measured yet are drawn off screen at the widths they may
take; until all visible cards are measured, the grid keeps showing the layout
it last packed (`ShownGrid`), so it never shows a guessed height. All listed
notes are measured, not only visible ones, so a search never waits.

## Run

```sh
moon build --target js --release apps/loomark/examples/note_index
P=apps/loomark/examples/note_index/public
cp _build/js/release/build/dowdiness/loomark/examples/note_index/note_index.js $P/
mkdir -p $P/fonts && cp apps/loomark/public/fonts/{iAWriterQuattroS-Regular-2.000.woff2,IBMPlexSansJP-Regular-1.004.woff2} $P/fonts/
python3 -m http.server 8000 --directory $P
```

Notes live in memory; reloading restores the samples.

## Things to try

- Open a card, change it, and press Escape. The index reappears in its old
  order, then the note slides to the first position, keeps focus, and is
  announced.
- Arrow keys move between cards by position, Home and End jump to the first
  and last, `/` focuses Search, and `N` opens a New document. Tab and screen
  readers follow recency order.
- Resize the window or change the card size; the columns follow the width.
- Long code and notes take two columns. `Packer::preview` places such a
  wide card at one column instead when it would trap more than 60px of
  column height.
- **List** shows the same leads as one column.
