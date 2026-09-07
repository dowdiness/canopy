# Testing Guide

This guide owns test design, test ownership, and focused test execution.
[Workflow](workflow.md#validation-scope) decides when each validation gate runs.

## Test Coverage

Choose the validation scope in Workflow before selecting commands below.

### Run Specific Package Tests

Run from the owning module or select it explicitly from the repository root:

```bash
moon -C modules/canopy test --release
moon -C deps/event-graph-walker test --release
```

For narrower package checks, use the affected package's path and its owning
module's guidance. Consult [Module / Package Map](module-package-map.md) for
ownership and workspace boundaries.

### Whole Workspace Tests

When investigating a workspace-wide regression, run from the repository root:

```bash
moon test
```

`moon.work` defines coverage. See `.github/workflows/ci.yml` for the full CI
matrices; a root MoonBit test run does not cover every frontend or browser suite.

### Update Snapshots

When behavior changes intentionally:
```bash
moon test --update
```

### Coverage Analysis

```bash
moon coverage analyze > uncovered.log
```

## Test Ownership

Each package tests its own logic. Rely on imported libraries' interface
contracts; when moving code, remove tests that now belong to another
package and track missing coverage in that package's backlog.

## Markdown Stabilization Boundary Matrix

Use this matrix when stabilizing Markdown span projection, commit, or
conversion behavior. It is not a checklist for unrelated changes.

| Dimension | Cases |
|-----------|-------|
| Syntax form | ATX, Setext, multiline, indented |
| Terminator | LF, CRLF, CR, EOF |
| Operation | Span projection, commit, conversion |
| Ownership context | Top level, container, explicitly unsupported |

Record which combinations the affected behavior supports and test its
boundaries, including how explicitly unsupported cases are handled.

## Test Types

### 1. Snapshot Tests (Primary)

Use `inspect` for snapshot testing:

```moonbit
test "feature behavior" {
  let result = my_function(input)
  inspect(result, content="expected output")
}
```

For intentional output changes, follow [Update Snapshots](#update-snapshots).

### 2. Property-Based Tests

Use QuickCheck (`@qc`) for algebraic properties:

```moonbit
test "property: commutativity" @qc(100) {
  fn(x : Int, y : Int) -> Bool {
    x + y == y + x
  }
}
```

**Examples in codebase:**
- See `deps/event-graph-walker/` submodule for property test examples (e.g., version vector properties)

### 3. Unit Tests

Use `assert_eq` only in loops where snapshots vary:

```moonbit
test "loop assertions" {
  for i = 0; i < 10; i = i + 1 {
    assert_eq!(compute(i), expected[i])
  }
}
```

## Test File Naming

- `*_test.mbt` - Blackbox tests (tests using public API only)
- `*_wbtest.mbt` - Whitebox tests (tests using internal implementation)

## Testing Philosophy

### What to Test

1. **Public API behavior** - All exported functions
2. **Edge cases** - Empty inputs, boundary conditions
3. **Error handling** - Invalid inputs, error paths
4. **CRDT properties** - Convergence, commutativity, idempotence
5. **Incremental parser** - Token caching, parse caching, damage tracking

### What NOT to Test

1. **Implementation details** - Internal helper functions
2. **Trivial getters/setters** - Unless they have logic
3. **External libraries** - Trust MoonBit stdlib

## Test Organization

### Test Structure

```moonbit
///| Tests for feature X

///|
test "happy path" {
  // Arrange
  let input = setup()

  // Act
  let result = function_under_test(input)

  // Assert
  inspect(result, content="expected")
}

///|
test "edge case: empty input" {
  let result = function_under_test("")
  inspect(result, content="empty result")
}

///|
test "error case: invalid input" {
  match function_under_test(invalid) {
    Some(_) => abort("Expected None")
    None => ()
  }
}
```

### Test Data

Keep test data close to tests:
```moonbit
let test_cases = [
  ("input1", "output1"),
  ("input2", "output2"),
]

for (input, expected) in test_cases {
  test "case: \(input)" {
    let result = my_function(input)
    inspect(result, content=expected)
  }
}
```

## CRDT-Specific Testing

### Convergence Tests

Test that concurrent operations converge:

```moonbit
test "convergence: concurrent inserts" {
  let doc_a = Document::new("agent_a")
  let doc_b = Document::new("agent_b")

  // Concurrent operations
  let op_a = doc_a.insert(0, "A")
  let op_b = doc_b.insert(0, "B")

  // Merge both ways
  doc_a.apply_remote(op_b)
  doc_b.apply_remote(op_a)

  // Should converge
  inspect(doc_a.to_text(), content=doc_b.to_text())
}
```

### Idempotence Tests

Test that replaying operations is safe:

```moonbit
test "idempotence: replay operation" {
  let doc = Document::new("agent")
  let op = doc.insert(0, "A")

  // Apply twice
  doc.apply_remote(op)
  doc.apply_remote(op)

  // Should have same effect as once
  inspect(doc.to_text(), content="A")
}
```

### Commutativity Tests

Test that operation order doesn't matter:

```moonbit
test "commutativity: order independent" {
  let doc1 = Document::new("agent")
  let doc2 = Document::new("agent")

  let ops = [op_a, op_b, op_c]

  // Apply in different orders
  for op in ops {
    doc1.apply_remote(op)
  }
  for op in ops.reverse() {
    doc2.apply_remote(op)
  }

  // Should converge
  inspect(doc1.to_text(), content=doc2.to_text())
}
```

## Parser-Specific Testing

### Incremental Parsing Tests

Test token caching and parse caching:

```moonbit
test "incremental: reuses tokens" {
  let parser = IncrementalParser::new("x + 1")
  let ast1 = parser.parse()

  // Edit that doesn't affect "x"
  let edit = Edit::new(2, 2, 3)  // Change "+" to "++"
  let ast2 = parser.edit(edit, "x ++ 1")

  // Token "x" should be reused (check via debug output)
  inspect(ast2)
}
```

### Error Recovery Tests

Test parser continues after errors:

```moonbit
test "error recovery: unclosed paren" {
  let parser = IncrementalParser::new("(x")
  let ast = parser.parse()

  // Should have error but still parse
  let errors = collect_errors(ast)
  inspect(errors, content="[Unclosed parenthesis]")
}
```

Include malformed-input recovery and incremental parsing cases. Follow the
owning [Loom package](../../deps/loom/README.md) for its test commands;
`deps/loom/examples/lambda/` provides parser test examples.

## Benchmarking

Benchmarks are tests too! Run with `--release`:

```bash
moon bench --release
moon -C deps/event-graph-walker bench --release
moon -C deps/loom/examples/lambda bench --release
```

See [performance documentation](../performance/BENCHMARK_REDESIGN.md) for details.

## Continuous Integration

`lefthook.yml` defines the local affected-package gates, and
`.github/workflows/ci.yml` defines repository CI. Follow
[Development Workflow](workflow.md) for when to run each gate; do not infer
that every commit runs the complete test suite.

## Debugging Failed Tests

### 1. Read Test Output

```bash
moon test 2>&1 | less
```

### 2. Run Single Test

```bash
moon test -f "test name"
```

### 3. Add Debug Output

```moonbit
test "debug" {
  let result = my_function(input)
  println("Debug: result = \(result)")  // Temporary debug
  inspect(result, content="expected")
}
```

### 4. Check .mbti Files

After refactoring, unexpected test failures might indicate unintended API changes:

```bash
git diff *.mbti
```

## References

- [MoonBit Testing Guide](https://docs.moonbitlang.com/testing)
- Parser edge cases: `deps/loom/examples/lambda/`
- QuickCheck properties: `deps/event-graph-walker/` submodule (version vector properties, CRDT convergence)
