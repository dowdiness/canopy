# dowdiness/canopy

- [Repository](https://github.com/dowdiness/canopy)
- [Web App](https://lambda-editor.koji-ishimoto.workers.dev/)

## Eg-Walker CRDT Editor in MoonBit

An implementation of the eg-walker CRDT algorithm for collaborative text editing, using the FugueMax sequence CRDT and retreat-advance-apply merge strategy.

## Project Structure

This is a monorepo with git submodules. Reusable libraries live in their own repositories and are linked here as submodules.

```
crdt/
├── event-graph-walker/   # Core CRDT library (submodule)
├── loom/                 # Incremental parser framework (submodule)
├── svg-dsl/              # SVG DSL (submodule)
├── graphviz/             # Graphviz DOT renderer (submodule)
├── valtio/               # Valtio state management (submodule)
├── editor/               # Editor abstractions
├── text_change/          # Shared contiguous text-change helpers
├── projection/           # Projectional editing
├── cmd/                  # CLI entry points
├── examples/web/         # Web frontend (Vite)
└── examples/demo-react/  # React demo
```

See [Monorepo & Submodule Guide](docs/development/monorepo.md) for the full workflow.

## Getting Started

```sh
git clone --recursive https://github.com/dowdiness/canopy.git
cd crdt
moon test
```

If you already cloned without `--recursive`:

```sh
git submodule update --init --recursive
```

## Building for Web

```sh
moon build --target js
cd examples/web
npm install
npm run dev
```

## EBNF Grammar

```ebnf
Expression   ::= BinaryOp

BinaryOp     ::= Application (('+' | '-') Application)*

Application  ::= Atom+

Atom         ::= Integer
               | Variable
               | Lambda
               | IfThenElse
               | '(' Expression ')'

Lambda       ::= ('λ' | '\') Identifier '.' Expression

IfThenElse   ::= 'if' Expression 'then' Expression 'else' Expression

Integer      ::= [0-9]+

Variable     ::= [a-zA-Z_][a-zA-Z0-9_]*

Identifier   ::= Variable
```

## Basic Syntax

### Literals

```
42          // Integer
x           // Variable
```

### Lambda Functions

```
λx.x        // Identity function (using λ symbol)
\x.x        // Identity function (using backslash)
λf.λx.f x   // Nested lambdas
```

### Arithmetic

```
1 + 2       // Addition
5 - 3       // Subtraction
a + b - c   // Chained operations (left-associative)
```

### Function Application

```
f x         // Apply f to x
f x y       // Apply (f x) to y
(λx.x) 5   // Apply identity to 5
```

### Conditionals

```
if x then 1 else 0
if x then y + 1 else y - 1
```

## Testing

```sh
moon test                                    # crdt module
cd event-graph-walker && moon test && cd ..   # CRDT library
cd loom/loom && moon test && cd ../..         # Parser framework
cd loom/examples/lambda && moon test && cd ../..  # Lambda parser
```

## Performance

Run benchmarks (always use `--release`):

```sh
moon bench --release
cd event-graph-walker && moon bench --release && cd ..
```

See [docs/performance/](docs/performance/) for detailed results.

## Documentation

- **[docs/](docs/)** - Full documentation index
- **[docs/development/monorepo.md](docs/development/monorepo.md)** - Monorepo & submodule workflow
- **[docs/development/workflow.md](docs/development/workflow.md)** - Development process
- **[docs/architecture/modules.md](docs/architecture/modules.md)** - Module structure
- **[event-graph-walker/README.md](event-graph-walker/README.md)** - Core CRDT library
- **[loom/README.md](loom/README.md)** - Incremental parser framework

## References

- [Eg-walker paper](https://arxiv.org/abs/2409.14252)
- [MoonBit documentation](https://docs.moonbitlang.com)
