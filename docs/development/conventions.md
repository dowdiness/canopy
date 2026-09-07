# MoonBit Coding Conventions

This guide owns code structure, naming, error handling, and mutation rules.
Use [API Reuse](api-reuse.md) to choose existing APIs before implementing.

## Code Organization

### 1. Block-Style Organization

Code is organized in blocks separated by `///|`. The order of blocks is irrelevant, enabling independent refactoring.

```moonbit
///| First block

///|
fn some_function() -> Unit {
  // ...
}

///| Second block

///|
fn another_function() -> Unit {
  // ...
}
```

### 2. Deprecation

Keep deprecated blocks in `deprecated.mbt` files within each package directory.

### Related guides

Use [Testing](testing.md) for test design and naming, and
[Workflow](workflow.md#validation-scope) for formatting, interface generation,
and validation gates.

## File Organization

### Package Structure
```
package_name/
├── moon.pkg                # Package configuration
├── main_feature.mbt        # Core implementation
├── main_feature_test.mbt   # Tests
├── main_feature_benchmark.mbt  # Benchmarks
├── helper.mbt              # Helper functions
└── deprecated.mbt          # Deprecated code
```

### Naming Conventions

- **Packages**: lowercase with underscores (e.g., `causal_graph`)
- **Files**: snake_case (e.g., `version_vector.mbt`)
- **Types**: PascalCase (e.g., `CausalGraph`)
- **Functions**: snake_case (e.g., `get_frontier`)
- **Test files**: follow [Test File Naming](testing.md#test-file-naming)
- **Benchmark files**: `*_benchmark.mbt`

## Documentation

### Code Comments

- Use `///|` for block separators
- Use `///` for function documentation
- Use `//` for inline comments

**Example:**
```moonbit
///| Module documentation block

///|
/// Function documentation
/// - param1: Description
/// - returns: Description
pub fn my_function(param1 : Int) -> String {
  // Inline comment
  let result = param1.to_string()
  result
}
```

### README Files

Each module should have:
- `README.md` - User-facing documentation
- Package metadata in `moon.pkg`; read module ownership from `moon.mod`

### Project Documentation

When making changes that affect the public API or architecture, update the corresponding documentation:

- **API Changes**: Update `docs/development/API_REFERENCE.md`.
- **JS FFI Changes**: Update `docs/development/JS_INTEGRATION.md` and `apps/web/`.
- **Structural Editing**: Update `docs/development/TREE_EDIT_MANUAL.md`.
- **Architecture**: Update `docs/architecture/ARCHITECTURE_DIAGRAM.md` or `modules.md` if dependency graph changes.

## Error Handling

Use the narrowest error boundary that matches the owning layer.

### Low-level domain errors stay local

- `event-graph-walker/text` owns `TextError` and `SyncFailure`
- `loom` owns lexer/parser errors
- tree/document internals keep their own domain errors

Do not wrap these early just to make everything look uniform.

### `editor/` uses typed boundary errors

At the editor boundary, prefer the explicit local error types over raw strings
or generic `Failure::Failure(...)`:

- `EphemeralError`
- `TreeEditError`
- `ProtocolError`

Use their `.message()` helpers only when crossing into UI, CLI, or FFI-facing
string surfaces.

### Flatten at the edge

Internal code should keep typed errors as long as possible. Root FFI entrypoints
may flatten them to strings or JSON.

Current example:

```moonbit
match parse_tree_edit_op(json) {
  Ok(op) =>
    match editor.apply_tree_edit(op, timestamp_ms) {
      Ok(_) => "ok"
      Err(err) => "error: " + err.message()
    }
  Err(err) => "error: " + err.message()
}
```

### Silent catches need explicit policy

If malformed remote input is intentionally dropped for resilience, document that
at the catch site. Otherwise prefer translating to a typed boundary error or
propagating upward.

### Pattern matching is still preferred

Prefer matching on structured results and typed errors over string inspection:

```moonbit
match result {
  Some(value) => process(value)
  None => default_value
}
```

```moonbit
match err {
  @text.TextError::SyncFailed(@text.SyncFailure::MissingDependency(..)) =>
    retry()
  _ => stop()
}
```

## Language-Specific Features

### Derive Traits

Use `derive` for common traits:
```moonbit
struct MyType {
  field: Int
} derive(Show, Eq)
```

### Pattern Matching

Prefer exhaustive pattern matching:
```moonbit
match value {
  Some(x) => handle_some(x)
  None => handle_none()
}
```

## Declarative Code and Mutation

- Use `match`, `guard`, and pattern matching to express decisions.
- Use existing core APIs for the data shape for lookups, optional/error handling,
  slicing, building, comparison, and transformation. Use `map`, `filter`,
  `fold`, `collect`, or list comprehensions when they express the operation.
- Use arrow functions for higher-order callbacks (`x => expr`,
  `(a, b) => { ... }`). Reserve `fn(...) { ... }` for named/local function
  values, explicit `raise`/`async` shape, or recursion.
- Prefer `ArrayView`, `StringView`, and `BytesView` over unnecessary copying.
  At validated core boundaries, do not expose internal mutable collections;
  use immutable views or defensive copies as ownership requires.

Account for every `let mut`, push loop, manual index loop, and `while` loop.
Mutation is appropriate for builders, true state machines, interop, or
measured performance needs. Local builder mutation may stay in a pure
function only when it has no observable external effect.


Record mutation reasons using [API Reuse](api-reuse.md#record-the-decision-once).
For optimization evidence, follow [Workflow](workflow.md#performance-work).

## Cross-package Construction

Before cross-package struct migrations, verify construction and mutation
access: `pub struct` fields are read-only outside their defining package;
use a named constructor or `pub(all)` as the intended interface requires.


## References

- [MoonBit Documentation](https://docs.moonbitlang.com)
- [MoonBit Language Tour](https://tour.moonbitlang.com)
