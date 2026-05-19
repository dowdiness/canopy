# CodeMirror Rabbita Demo

Minimal standalone Rabbita app for the `dowdiness/rabbita_codemirror`
binding. It exercises the P2.4 public API surface without depending on the
existing Canopy examples.

## Run

```bash
moon build --target js --release
npm install
npm run build
npm run dev
```

Open the Vite URL and use the controls on the page.

## Manual Smoke Checklist

1. The editor mounts when the app starts.
2. Typing in the editor fires `DocChanged`; the readout updates.
3. The "Set doc" button calls `set_doc` and resets the editor contents.
4. The "Toggle readonly" button flips readonly mode in place.
5. The "Unmount" button removes the editor contents; "Mount" recreates it.
6. The "Swap tagger" button changes the doc-change variant. Type before the
   swap and the readout shows `A:`; type after the swap and it shows `B:`.
