# MoonBit Coding Conventions

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

### 3. Testing Philosophy

- **Use `inspect`** with snapshot testing (`moon test --update`)
- **Only use `assert_eq`** in loops where snapshots vary
- **Test file naming:**
  - `*_test.mbt` - Blackbox tests
  - `*_wbtest.mbt` - Whitebox tests

**Example:**
```moonbit
test "my feature" {
  let result = my_function(input)
  inspect(result, content="expected output")  // Snapshot test
}
```

### 4. Interface Changes

After refactoring, check `.mbti` generated interface files. If nothing changes, your refactoring didn't affect the public API.

```bash
moon info          # Generate .mbti files
git diff *.mbti    # Check for API changes
```

### 5. Format Before Committing

Always run `moon info && moon fmt` before finalizing changes.

## Property-Based Testing

Use QuickCheck (`@qc`) for algebraic properties:

```moonbit
test "property: addition commutative" @qc(100) {
  fn(x : Int, y : Int) -> Bool {
    x + y == y + x
  }
}
```

**Implement Arbitrary and Shrink traits** for custom types:
- See `causal_graph/version_vector.mbt` for examples
- 25 property tests with 100 test cases each for version vectors

## File Organization

### Package Structure
```
package_name/
├── moon.pkg.json           # Package configuration
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
- **Test files**: `*_test.mbt` or `*_wbtest.mbt`
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
- `moon.pkg.json` - Package metadata

### Project Documentation

When making changes that affect the public API or architecture, update the corresponding documentation:

- **API Changes**: Update `docs/development/API_REFERENCE.md`.
- **JS FFI Changes**: Update `docs/development/JS_INTEGRATION.md` and `examples/web/`.
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

## Performance Considerations

- Use `Array` for index-based access
- Use `HashMap` for key-value lookups
- Profile with `moon bench --release` before optimizing
- Benchmark files end in `_benchmark.mbt`

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

### Immutability

Prefer immutable data structures unless mutation is necessary:
```moonbit
let items = []  // Immutable array
items.push(1)   // Returns new array, original unchanged
```

## References

- [MoonBit Documentation](https://docs.moonbitlang.com)
- [MoonBit Language Tour](https://tour.moonbitlang.com)
