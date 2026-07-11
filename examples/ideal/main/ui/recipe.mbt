///|
/// CVA-inspired recipe helpers.
///
/// CVA's useful idea is the recipe model (base + typed variants + composition)
/// rather than the JS package itself. MoonBit's `match` on private variant enums
/// replaces CVA's `compoundVariants` schema; this module provides the small
/// join utility that keeps recipe definitions free of manual `" "` concatenation.
///
/// Anti-goals (per docs/development/ideal-tailwind-style-management.md):
///   - No JS `cva` package.
///   - No Tailwind `@apply`.
///   - No runtime-generated tokens like `"bg-" + tone`.
///   - No generic variant-schema abstraction.

///|
/// Join class strings with a single space, filtering out empty entries so
/// callers can conditionally include classes without inline `if` branches.
fn cx(classes : ArrayView[String]) -> String {
  classes.iter().filter(fn(c) { c.length() > 0 }).join(" ")
}
