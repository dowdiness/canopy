---
name: moonbit-deprecated-syntax
description: "Tracks deprecated MoonBit syntax to avoid generating invalid code. Reference this before writing MoonBit code. Auto-maintained when deprecated patterns are discovered."
---

# MoonBit Deprecated Syntax Reference

Reference this skill before generating MoonBit code to avoid deprecated patterns.

## Deprecated Patterns

### Error Propagation: `!` suffix (DEPRECATED)

**Old syntax (deprecated):**
```moonbit
let result = may_fail()!  // WRONG: ! suffix
```

**Current syntax:**
```moonbit
// Automatic propagation when caller also declares `raise`
fn caller() -> T raise E {
  let result = may_fail()  // Errors propagate automatically
}

// Or explicit try/catch
try {
  may_fail()
} catch {
  e => handle(e)
}
```

### Labeled Arguments: `~` prefix vs suffix

**Old syntax (deprecated):**
```moonbit
fn foo(~label : Int) -> Unit  // WRONG: ~ prefix
foo(~label=42)                // WRONG: ~ prefix in call
```

**Current syntax:**
```moonbit
fn foo(label~ : Int) -> Unit  // Correct: ~ suffix
foo(label~=42)                // Correct: ~ suffix in call
foo(label=42)                 // Also valid without ~
```

---

## Maintenance

When the AI generates code that fails due to deprecated syntax:
1. Add the deprecated pattern to this file
2. Include the old (wrong) and new (correct) syntax
3. Add a brief explanation

This file is the source of truth for deprecated MoonBit patterns in this project.
