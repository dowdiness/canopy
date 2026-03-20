import { Node as PmNode } from "prosemirror-model";
import { editorSchema } from "./schema";
import { ProjNodeJson, getKindTag, TermKindTag } from "./types";

/**
 * Extract the attrs a ProjNode would produce for a given PM node.
 * Shared between convert.ts (initial build) and reconciler.ts (incremental diff).
 */
export function attrsForKind(
  proj: ProjNodeJson,
  tag: TermKindTag,
): Record<string, unknown> {
  switch (tag) {
    case "Int": return { value: proj.kind[1], nodeId: proj.node_id };
    case "Var": return { name: proj.kind[1], nodeId: proj.node_id };
    case "Unbound": return { name: proj.kind[1], nodeId: proj.node_id };
    case "Unit": return { nodeId: proj.node_id };
    case "Error": return { message: proj.kind[1] || "", nodeId: proj.node_id };
    case "Lam": return { param: proj.kind[1], nodeId: proj.node_id };
    case "App": return { nodeId: proj.node_id };
    case "Bop": return { op: proj.kind[1], nodeId: proj.node_id };
    case "If": return { nodeId: proj.node_id };
    case "Module": return { nodeId: proj.node_id };
  }
}

export function projNodeToPmNode(proj: ProjNodeJson): PmNode {
  const tag = getKindTag(proj.kind);

  switch (tag) {
    case "Int":
      return editorSchema.node("int_literal", attrsForKind(proj, tag));
    case "Var":
      return editorSchema.node("var_ref", attrsForKind(proj, tag));
    case "Unbound":
      return editorSchema.node("unbound_ref", attrsForKind(proj, tag));
    case "Unit":
      return editorSchema.node("unit", attrsForKind(proj, tag));
    case "Error":
      return editorSchema.node("error_node", attrsForKind(proj, tag));
    case "Lam": {
      if (proj.children.length < 1) {
        return editorSchema.node("error_node", { message: "malformed Lam: missing body", nodeId: proj.node_id });
      }
      const paramName = proj.kind[1];
      const bodyPm = projNodeToPmNode(proj.children[0]);
      return editorSchema.node(
        "lambda",
        {
          param: paramName,
          nodeId: proj.node_id,
        },
        [bodyPm],
      );
    }
    case "App": {
      if (proj.children.length < 2) {
        return editorSchema.node("error_node", { message: "malformed App: needs func and arg", nodeId: proj.node_id });
      }
      const funcPm = projNodeToPmNode(proj.children[0]);
      const argPm = projNodeToPmNode(proj.children[1]);
      return editorSchema.node(
        "application",
        {
          nodeId: proj.node_id,
        },
        [funcPm, argPm],
      );
    }
    case "Bop": {
      if (proj.children.length < 2) {
        return editorSchema.node("error_node", { message: "malformed Bop: needs left and right", nodeId: proj.node_id });
      }
      const op = proj.kind[1];
      const leftPm = projNodeToPmNode(proj.children[0]);
      const rightPm = projNodeToPmNode(proj.children[1]);
      return editorSchema.node(
        "binary_op",
        {
          op,
          nodeId: proj.node_id,
        },
        [leftPm, rightPm],
      );
    }
    case "If": {
      if (proj.children.length < 3) {
        return editorSchema.node("error_node", { message: "malformed If: needs cond, then, else", nodeId: proj.node_id });
      }
      const condPm = projNodeToPmNode(proj.children[0]);
      const thenPm = projNodeToPmNode(proj.children[1]);
      const elsePm = projNodeToPmNode(proj.children[2]);
      return editorSchema.node(
        "if_expr",
        {
          nodeId: proj.node_id,
        },
        [condPm, thenPm, elsePm],
      );
    }
    case "Module": {
      if (proj.children.length < 1) {
        return editorSchema.node("error_node", { message: "malformed Module: missing body", nodeId: proj.node_id });
      }
      // Module kind: ["Module", [["name0", term0], ["name1", term1]], body_term]
      // ProjNode children: [init0, init1, ..., body]
      const defs: [string, any][] = proj.kind[1];
      const children: PmNode[] = [];
      for (let i = 0; i < proj.children.length - 1; i++) {
        const name = i < defs.length ? defs[i][0] : "_";
        const initPm = projNodeToPmNode(proj.children[i]);
        children.push(
          editorSchema.node(
            "let_def",
            {
              name,
              nodeId: proj.children[i].node_id,
            },
            [initPm],
          ),
        );
      }
      const bodyPm = projNodeToPmNode(
        proj.children[proj.children.length - 1],
      );
      children.push(bodyPm);
      return editorSchema.node(
        "module",
        {
          nodeId: proj.node_id,
        },
        children,
      );
    }
    default:
      return editorSchema.node("error_node", {
        message: `Unknown kind: ${tag}`,
        nodeId: proj.node_id,
      });
  }
}

export function projNodeToDoc(proj: ProjNodeJson): PmNode {
  const content = projNodeToPmNode(proj);
  return editorSchema.node("doc", null, [content]);
}
