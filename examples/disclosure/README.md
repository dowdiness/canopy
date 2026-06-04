# Disclosure example

Smallest working PoC of the **headless behavior + local styling** pattern on
rabbita 0.12.3, mirroring `examples/resizable`.

- `DisclosureModel` (in `main/client.mbt`) owns state (`open`) and emits ARIA
  via `trigger_attrs` / `content_attrs` returning `@html.Attrs` — no styling.
  `content_id` is the stable panel id referenced by `aria-controls`; it must be
  unique on the page.
- Section copy and behavior state are paired in `Section` records; the view maps
  sections instead of indexing fixed positions.
- The consumer `view` spreads those attrs onto `<button>` / `<div>` via
  `attrs=...` and supplies all classes locally (`public/styles.css`).
- Message lift uses an emit closure (`emit(Toggle(index))`).
- This is a stack of independent Disclosure widgets, not a single Accordion:
  multiple sections may be open, and panels are not exposed as landmarks.
- The PoC keeps the behavior helpers package-private. Extracting `lib/disclosure`
  is the P2 step where `DisclosureModel` and `*_attrs` would become public API.

## Run

```bash
moon install moonbit-community/warren   # once
cd examples/disclosure
warren dev
```

Open the local URL shown by Warren. If Warren is unavailable in your environment,
run `moon build --target js` from this directory and static-serve the generated
bundle with a host page containing `<div id="app"></div>`.

## Manual check

- Click a header: its panel toggles; the chevron rotates (driven by
  `aria-expanded`, no extra markup).
- Tab to a header and press Enter/Space: it toggles (native `<button>`).
- The middle section starts expanded.
- Each trigger's `aria-controls` references its panel `id`.
