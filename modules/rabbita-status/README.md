# Rabbita Status

Headless status/live-region behavior for Rabbita apps. The package owns the
small semantic tone vocabulary and ARIA live-region attributes; the consumer owns
message copy, domain status calculation, HTML structure, and styling.

## Use

```mbt nocheck
struct Model {
  status_text : String
  status_tone : @status.Tone
}

fn view(_emit : @rabbita.Emit[Msg], model : Model) -> @rabbita.Html {
  @html.p(
    class="status-line",
    attrs=model.status_tone.attrs(),
    [@html.text(model.status_text)],
  )
}
```

Use `Info`, `Success`, and `Error` for domain tone mapping. `Tone::attrs()` emits
`role="status"`, `aria-live="polite"`, `aria-atomic="true"`, and
`data-tone="info|success|error"`. Consumers can chain additional attrs or use
wrapper parameters for ids, classes, and styling.

## Consumer evaluation

- Canvas source-backed Apply status is the first real consumer.
- Ideal peer sync status was evaluated and migrated as a second feedback
  surface; it fits the API because Ideal keeps the sync-state mapping and label
  copy while this package supplies only the live-region/tone attrs.

## Verified Rabbita APIs

Implementation was checked against the vendored Rabbita source, especially:

- `rabbita/doc/002_writing_html/readme.mbt.md`
- `rabbita/rabbita/html/README.mbt.md`
- `rabbita/rabbita/html/design.md`
- `rabbita/rabbita/html/pkg.generated.mbti` — `Attrs::{build, role, aria_live,
  aria_atomic, data_set}`.
