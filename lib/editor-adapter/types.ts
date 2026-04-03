// TypeScript type definitions mirroring MoonBit editor protocol types.
// These match the JSON wire format produced by framework/protocol/ custom ToJson impls.

export type ViewNode = {
  id: number;
  kind_tag: string;
  label: string;
  text: string | null;
  text_range: [number, number];
  token_spans: { role: string; start: number; end: number }[];
  editable: boolean;
  css_class: string;
  children: ViewNode[];
  annotations: { kind: string; label: string; severity: string }[];
};

export type Decoration = {
  from: number;
  to: number;
  css_class: string;
  data: string | null;
  widget: boolean;
};

export type Diagnostic = {
  from: number;
  to: number;
  severity: "error" | "warning" | "info" | "hint";
  message: string;
};

export type ViewPatch =
  | { type: "TextChange"; from: number; to: number; insert: string }
  | { type: "ReplaceNode"; node_id: number; node: ViewNode }
  | { type: "InsertChild"; parent_id: number; index: number; child: ViewNode }
  | { type: "RemoveChild"; parent_id: number; index: number; child_id: number }
  | { type: "UpdateNode"; node_id: number; label: string; css_class: string; text: string | null }
  | { type: "SetDecorations"; decorations: Decoration[] }
  | { type: "SetDiagnostics"; diagnostics: Diagnostic[] }
  | { type: "SetSelection"; anchor: number; head: number }
  | { type: "SelectNode"; node_id: number }
  | { type: "FullTree"; root: ViewNode | null };

export type UserIntent =
  | { type: "TextEdit"; from: number; to: number; insert: string }
  | { type: "StructuralEdit"; node_id: number; op: string; params: Record<string, string> }
  | { type: "SelectNode"; node_id: number }
  | { type: "SetCursor"; position: number }
  | { type: "Undo" }
  | { type: "Redo" }
  | { type: "CommitEdit"; node_id: number; value: string };
