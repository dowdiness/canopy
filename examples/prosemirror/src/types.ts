export interface ProjNodeJson {
  node_id: number;
  kind: any[];
  children: ProjNodeJson[];
  start: number;
  end: number;
}

export type TermKindTag =
  | "Int"
  | "Var"
  | "Lam"
  | "App"
  | "Bop"
  | "If"
  | "Module"
  | "Unit"
  | "Unbound"
  | "Error";

export function getKindTag(kind: any[]): TermKindTag {
  return kind[0] as TermKindTag;
}
