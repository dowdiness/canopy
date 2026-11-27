# Resume view

A Loomark-local experiment
([#1484](https://github.com/dowdiness/canopy/issues/1484)). Shows the
`resume_entries` of the given documents, grouped by project in order of first
appearance and then by kind. Each entry shows its exact source text and its
document's name; nothing is merged, ranked, or dropped. Choosing an entry
returns a `Choice` with the source text its range was taken from, so the host
selects the range only while the document still has that exact text.
