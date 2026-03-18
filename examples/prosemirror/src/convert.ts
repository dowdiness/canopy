import { Node as PmNode } from "prosemirror-model";
import { editorSchema } from "./schema";
import { ProjNodeJson, getKindTag } from "./types";

export function projNodeToPmNode(proj: ProjNodeJson): PmNode {
  const tag = getKindTag(proj.kind);

  switch (tag) {
    case "Int":
      return editorSchema.node("int_literal", {
        value: proj.kind[1],
        nodeId: proj.node_id,
      });
    case "Var":
      return editorSchema.node("var_ref", {
        name: proj.kind[1],
        nodeId: proj.node_id,
      });
    case "Unbound":
      return editorSchema.node("unbound_ref", {
        name: proj.kind[1],
        nodeId: proj.node_id,
      });
    case "Unit":
      return editorSchema.node("unit", { nodeId: proj.node_id });
    case "Error":
      return editorSchema.node("error_node", {
        message: proj.kind[1] || "",
        nodeId: proj.node_id,
      });
    case "Lam": {
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
