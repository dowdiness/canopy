'use client';

// Empty-paragraph sentinel wiring for the markdown editor.
//
// The caller supplies the sentinel sourced from the MoonBit FFI bundle so this
// pure display transformation and `modules/canopy/lang/markdown/sentinel/` +
// `deps/loom/moji/codepoints.mbt` agree by construction. The build graph routes:
//
//   deps/loom/moji/codepoints.mbt     (canonical const: ZERO_WIDTH_SPACE)
//     → modules/canopy/lang/markdown/sentinel/       (role-name layer: EMPTY_PARAGRAPH_SENTINEL)
//       → modules/canopy/ffi/markdown/markdown_ffi   (JS export: markdown_empty_paragraph_sentinel)
//         → @moonbit/crdt-markdown    (client-only generated module)
//           → app runtime injection   (captures the value once)
//             → this pure function
//               → BlockInput option   (per-instance strip behavior)

/** Strip every occurrence of the empty-paragraph sentinel from a display string. */
export function stripParagraphSentinels(s: string, sentinel: string): string {
  return s.split(sentinel).join('');
}
