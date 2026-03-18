# Lambda CRDT Editor - React + Valtio Demo

A demonstration of integrating React with the MoonBit Valtio FFI module (`valtio-egwalker`).

Part of the [dowdiness/canopy](https://github.com/dowdiness/canopy) monorepo. Depends on the [valtio](../../valtio/) and [event-graph-walker](../../event-graph-walker/) submodules.

## Features

- **React 19** - Modern React with hooks
- **Valtio** - Proxy-based state management with `useSnapshot`
- **valtio-egwalker** - MoonBit Valtio FFI integration
- **TypeScript** - Full type safety
- **Vite** - Fast development server

## Quick Start

Make sure you cloned the monorepo with submodules:

```bash
git clone --recursive https://github.com/dowdiness/canopy.git
cd crdt/examples/demo-react
npm install
npm run dev
```

Open http://localhost:5174 in your browser.

## Project Structure

```
examples/demo-react/
├── src/
│   ├── main.tsx           # Entry point
│   ├── App.tsx            # Root component
│   ├── styles.css         # Global styles
│   └── components/
│       ├── LambdaEditor.tsx      # Main editor using valtio-egwalker
│       ├── Toolbar.tsx           # Undo/redo toolbar
│       ├── StatusBar.tsx         # Status display
│       └── CollaborativeDemo.tsx # Two-editor demo
├── index.html
├── package.json
├── tsconfig.json
└── vite.config.ts
```

## Using valtio-egwalker

This demo uses the MoonBit Valtio FFI module directly:

```typescript
import { createEgWalkerProxy, type TextState } from 'valtio-egwalker/stub';
import { useSnapshot } from 'valtio';

// Create CRDT-backed proxy
const egwalker = createEgWalkerProxy<TextState>({
  agentId: 'user-123',
  undoManager: true,
});

// In React component:
function Editor() {
  // Read from snapshot (reactive)
  const snap = useSnapshot(egwalker.proxy, { sync: true });

  return (
    <textarea
      value={snap.text}
      onChange={(e) => {
        // Mutate proxy directly
        egwalker.proxy.text = e.target.value;
      }}
    />
  );
}
```

### Key Patterns

1. **Read from snapshot, mutate proxy**
   ```typescript
   const snap = useSnapshot(egwalker.proxy);
   // Read: snap.text
   // Write: egwalker.proxy.text = newValue
   ```

2. **Use `{ sync: true }` for controlled inputs**
   ```typescript
   const snap = useSnapshot(egwalker.proxy, { sync: true });
   ```

3. **Cleanup on unmount**
   ```typescript
   useEffect(() => {
     return () => egwalker.dispose();
   }, [egwalker]);
   ```

4. **Undo/Redo**
   ```typescript
   egwalker.undo();
   egwalker.redo();
   ```

## Stub vs Production

### Development (Stub)
```typescript
import { createEgWalkerProxy } from 'valtio-egwalker/stub';
```
Uses a JavaScript mock implementation - no MoonBit build required.

### Production (MoonBit)
```typescript
import { createEgWalkerProxy } from 'valtio-egwalker';
```
Requires building MoonBit: `cd ../../valtio && moon build --target js`

## Vite Configuration

The demo uses path aliases to resolve the valtio-egwalker module from the monorepo:

```typescript
// vite.config.ts
resolve: {
  alias: {
    'valtio-egwalker/stub': path.resolve(__dirname, '../../valtio/src/egwalker_api_stub.ts'),
    'valtio-egwalker': path.resolve(__dirname, '../../valtio/src/egwalker_api.ts'),
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
