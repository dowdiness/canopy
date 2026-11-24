# Document index

This package owns the Document index screen: cards packed into columns with
`dowdiness/skyline` from heights the browser measured, search, keyboard
movement, focus, and the card states shared with Recent documents.

The host resolves each document into a `Seed` under its own key type, such as
the app's document key, and keeps a `DocumentIndex` in its Model. It forwards the index's `Msg` to `update` and runs its
`subscriptions`. It reports changes made elsewhere through `listing`,
`returned_from`, `removed`, and `return_focus`. Delete document only asks the
host through `on_delete`. The host confirms, deletes, and lists the result.
Card states are drawn over the cards, so they never change a measured height.
Product requirements are in the
[Loomark vocabulary and behaviour contract](../../CONTEXT.md).
