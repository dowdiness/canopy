# MoonBit Conventions — Code Examples

Concrete patterns for MoonBit code in this project. See [API Reuse](api-reuse.md)
for API discovery and implementation guidance.

## Custom constructors

Declare a custom constructor as a toplevel `fn Type::Type(...)`. This enables `Type(args)` construction syntax with labelled/optional parameters, validation, and defaults, for structs and enums alike. Prefer it over bare struct literals `{ field: value }` and over `Type::new`.

```moonbit
struct MyStruct {
  x : Int
  y : Int
}

fn MyStruct::MyStruct(x~ : Int, y? : Int = x) -> MyStruct {
  { x, y }
}

let s = MyStruct(x=1)  // usage — like enum constructors
```

Do not declare `fn new(...)` inside the type body; the compiler deprecates it.

## StringView/ArrayView patterns

Use `.view()` + array patterns for iteration instead of index loops. Works with `String`, `Array`, `Bytes`.

```moonbit
// Prefer this:
loop text.view(), 0 {
  [], _ => ()
  [ch, ..rest], i => {
    process(ch)
    continue rest, i + 1
  }
}
// Over this:
for i = 0; i < text.length(); i = i + 1 {
  let ch = text[i]
  process(ch)
}
```

Also useful for prefix matching: `match s.view() { [.."let", ..rest] => ... }` and palindrome-style middle access: `[a, ..rest, b] => ...`
