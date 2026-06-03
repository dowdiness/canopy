# Resizable example

Runnable Rabbita demo for `dowdiness/rabbita-resizable`.

## Run

```bash
moon install moonbit-community/warren
warren dev
```

Open the local URL shown by Warren.

## Manual check

- Drag the corner handle on the box; width and height change within bounds.
- Drag the vertical split-pane separator; the left pane width changes.
- Release the mouse outside the thin handle; resizing still ends because the package installs a document-level `mouseup` subscription.
- Focus a handle with Tab and use arrow keys: the corner handle responds on both axes, and the split handle responds to Left/Right.
