# Lambda CRDT Editor - React Demo

A demonstration of integrating React with Canopy's MoonBit EditorProtocol FFI.

Part of the [dowdiness/canopy](https://github.com/dowdiness/canopy) monorepo. Depends on the root MoonBit JS build and the [event-graph-walker](../../event-graph-walker/) submodule.

## Features

- **React 19** - Modern React with hooks
- **EditorProtocol** - Handle-based API exposed by Canopy's MoonBit FFI
- **eg-walker** - CRDT-backed text state with undo/redo and sync export
- **TypeScript** - Full type safety
- **Vite** - Fast development server

## Quick Start

Make sure you cloned the monorepo with submodules:

```bash
git clone --recursive https://github.com/dowdiness/canopy.git
cd canopy/examples/demo-react
npm install
npm run dev
```

Open http://localhost:5174 in your browser.

## Project Structure

```
examples/demo-react/
├── src/
│   ├── main.tsx                 # Entry point
│   ├── App.tsx                  # Root component
│   ├── styles.css               # Global styles
│   ├── features/editor/         # Typed wrapper around the MoonBit FFI
│   ├── features/lambda-editor/  # Single-editor UI
│   └── features/collaborative/  # Two-editor demo
├── index.html
├── package.json
├── tsconfig.json
└── vite.config.ts
```

## Using the MoonBit FFI

The demo imports a typed wrapper around the generated MoonBit JS module:

```typescript
import { EditorHandle, getCrdtModule } from './features/editor/crdt-api';

const editor = new EditorHandle(getCrdtModule(), 'user-123');

editor.setTextAndRecord('((x) => x) y');
const text = editor.getText();
```

### Key Patterns

1. **Keep React state at the UI boundary**
   ```typescript
   const [text, setText] = useState(editor.getText());
   editor.setTextAndRecord(nextText);
   setText(editor.getText());
   ```

2. **Cleanup handles on unmount**
   ```typescript
   useEffect(() => {
     return () => editor.destroy();
   }, [editor]);
   ```

3. **Undo/Redo**
   ```typescript
   editor.undo();
   editor.redo();
   ```

## Stub vs MoonBit Build

`vite.config.ts` resolves `@moonbit/crdt` to the generated JS artifact when it
exists. If the MoonBit build has not run yet, it falls back to the in-memory
stub module under `src/features/editor/`.

Run `npm run build:all` to build MoonBit first and then bundle the React app.

## Vite Configuration

The demo uses a path alias to resolve the generated MoonBit module:

```typescript
// vite.config.ts
resolve: {
  alias: {
    '@moonbit/crdt': hasMoonbitBuild
      ? moonbitBuildPath
      : path.resolve(__dirname, 'src/features/editor/crdt-stub-module.ts'),
  },
},
```

## Scripts

| Script | Description |
|--------|-------------|
| `npm run dev` | Start development server |
| `npm run build` | Build for production |
| `npm run preview` | Preview production build |
| `npm run build:all` | Build MoonBit + React |

## License

Apache-2.0
