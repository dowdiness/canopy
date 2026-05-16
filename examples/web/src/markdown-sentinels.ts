// Empty-paragraph sentinel wiring for the markdown editor.
//
// Sources the sentinel codepoint from the MoonBit FFI bundle so this file
// and `lang/markdown/sentinel/` + `lib/moji/codepoints.mbt` agree by
// construction. The build graph routes:
//
//   lib/moji/codepoints.mbt           (canonical const: ZERO_WIDTH_SPACE)
//     → lang/markdown/sentinel/       (role-name layer: EMPTY_PARAGRAPH_SENTINEL)
//       → ffi/markdown/markdown_ffi   (JS export: markdown_empty_paragraph_sentinel)
//         → @moonbit/crdt-markdown    (Vite virtual module)
//           → this file               (captures the value once)
//             → BlockInput option     (per-instance strip behavior)

import { markdown_empty_paragraph_sentinel } from '@moonbit/crdt-markdown';

const SENTINEL = markdown_empty_paragraph_sentinel();

/** Strip every occurrence of the empty-paragraph sentinel from a display string. */
export function stripParagraphSentinels(s: string): string {
  return s.split(SENTINEL).join('');
}
