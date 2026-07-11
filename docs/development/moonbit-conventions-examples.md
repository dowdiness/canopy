# MoonBit Conventions — Code Examples

Referenced from AGENTS.md. These are concrete patterns for MoonBit code in this project.

## Custom constructors for structs

When defining public structs, declare a custom constructor via `fn new(...)` inside the struct body. This enables `StructName(args)` construction syntax with labelled/optional parameters, validation, and defaults. Prefer this over bare struct literals `{ field: value }`.

```moonbit
struct MyStruct {
  x : Int
  y : Int

  fn new(x~ : Int, y? : Int) -> MyStruct  // declaration inside struct
} derive(Debug)

fn MyStruct::new(x~ : Int, y? : Int = x) -> MyStruct {  // implementation
  { x, y }
}

let s = MyStruct(x=1)  // usage — like enum constructors
```

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
