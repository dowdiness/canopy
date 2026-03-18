# Lambda Calculus CRDT Editor - Web Interface

A collaborative lambda calculus editor built with MoonBit CRDT and JavaScript.

Part of the [dowdiness/canopy](https://github.com/dowdiness/canopy) monorepo.

## Features

- **Real-time syntax highlighting** for lambda calculus
- **Error recovery** with inline error display
- **CRDT-based** text editing for future collaboration
- **Vite plugin** for automatic MoonBit builds and HMR

## Getting Started

### Prerequisites

- Node.js 18+ and npm
- MoonBit compiler (`curl -fsSL https://cli.moonbitlang.com/install/unix.sh | bash`)
- The full monorepo cloned with submodules:
  ```bash
  git clone --recursive https://github.com/dowdiness/canopy.git
  ```

### Development

```bash
cd examples/web
npm install
npm run dev

# Open http://localhost:5173
```

The Vite plugin (`vite-plugin-moonbit`) automatically runs `moon build --target js` and watches for `.mbt` file changes during development.

### Production Build

```bash
npm run build
npm run preview
```

### Deploy Build (Cloudflare Pages)

```bash
npm run build:deploy
```

This installs the MoonBit CLI, fetches MoonBit package dependencies, then runs the Vite build. Use this as the build command on Cloudflare Pages or other CI environments that don't have `moon` pre-installed.

## Architecture

- **Frontend**: TypeScript + Vite
- **Backend**: MoonBit CRDT compiled to JavaScript via `vite-plugin-moonbit`
- **Parser**: Error-recovering lambda calculus parser
- **Editor**: contenteditable-based with AST-driven highlighting

### Vite Plugin

The `vite-plugin-moonbit.ts` plugin handles the MoonBit integration:

- Builds MoonBit modules at startup (`moon build --target js`)
- Provides virtual modules (`@moonbit/crdt`, `@moonbit/graphviz`) importable in TypeScript
- Watches `.mbt` files and triggers full reload on changes during development

## Usage

1. Open the editor in your browser
2. Start typing lambda calculus expressions
3. See real-time syntax highlighting and error detection

### Example Expressions

```
(\x. x + 1) 5
(\f. \x. f (f x)) (\y. y * 2) 3
if 1 then 2 else 3
```
