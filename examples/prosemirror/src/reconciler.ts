import { Transaction } from "prosemirror-state";
import { EditorState } from "prosemirror-state";
import { Node as PmNode } from "prosemirror-model";
import { projNodeToPmNode } from "./convert";
import { ProjNodeJson, getKindTag, TermKindTag } from "./types";

/**
 * Map from ProjNode kind tag to the corresponding PM node type name.
 */
const kindToPmType: Record<TermKindTag, string> = {
  Int: "int_literal",
  Var: "var_ref",
  Unbound: "unbound_ref",
  Unit: "unit",
  Error: "error_node",
  Lam: "lambda",
  App: "application",
  Bop: "binary_op",
  If: "if_expr",
  Module: "module",
};

/**
 * Extract the attrs a ProjNode would produce for a given PM node.
 * Must stay in sync with projNodeToPmNode in convert.ts.
 */
function projAttrs(
  proj: ProjNodeJson,
  tag: TermKindTag,
): Record<string, unknown> {
  switch (tag) {
    case "Int":
      return { value: proj.kind[1], nodeId: proj.node_id };
    case "Var":
      return { name: proj.kind[1], nodeId: proj.node_id };
    case "Unbound":
      return { name: proj.kind[1], nodeId: proj.node_id };
    case "Unit":
      return { nodeId: proj.node_id };
    case "Error":
      return { message: proj.kind[1] || "", nodeId: proj.node_id };
    case "Lam":
      return { param: proj.kind[1], nodeId: proj.node_id };
    case "App":
      return { nodeId: proj.node_id };
    case "Bop":
      return { op: proj.kind[1], nodeId: proj.node_id };
    case "If":
      return { nodeId: proj.node_id };
    case "Module":
      return { nodeId: proj.node_id };
  }
}

/**
 * Compare two PM attribute objects for shallow equality.
 */
function attrsEqual(
  a: Record<string, unknown>,
  b: Record<string, unknown>,
): boolean {
  const keysA = Object.keys(a);
  const keysB = Object.keys(b);
  if (keysA.length !== keysB.length) return false;
  for (const key of keysA) {
    if (a[key] !== b[key]) return false;
  }
  return true;
}

/**
 * Incremental subtree-diff reconciler.
 *
 * Walks the old PM doc and new ProjNode in parallel, only emitting PM steps
 * for changed subtrees. Unchanged NodeViews (and their CM6 instances) are
 * preserved — no focus loss on unchanged leaves.
 */
export function reconcile(
  state: EditorState,
  newProj: ProjNodeJson,
): Transaction | null {
  const tr = state.tr;
  const docNode = state.doc;

  // doc has exactly one child (the root term or module)
  const rootPm = docNode.firstChild;
  if (!rootPm) {
    // Empty doc — do a full replace
    const newPm = projNodeToPmNode(newProj);
    tr.replaceWith(0, docNode.content.size, newPm);
    tr.setMeta("fromCrdt", true);
    return tr;
  }

  // Position 1 = right after the doc's open tag (position 0 is before the doc content)
  diffNode(tr, rootPm, newProj, 1);

  if (!tr.docChanged) return null;
  tr.setMeta("fromCrdt", true);
  return tr;
}

/**
 * Recursively diff a PM node against a ProjNode.
 *
 * @param tr - The transaction to accumulate steps into
 * @param pmNode - The existing PM node in the document
 * @param proj - The new ProjNode from the CRDT
 * @param pmPos - The position of pmNode in the *original* document
 *                (before any transaction steps). We use tr.mapping.map()
 *                to convert to current positions when emitting steps.
 */
function diffNode(
  tr: Transaction,
  pmNode: PmNode,
  proj: ProjNodeJson,
  pmPos: number,
): void {
  const tag = getKindTag(proj.kind);
  const expectedPmType = kindToPmType[tag];

  // 1. Type mismatch — replace entire subtree
  if (pmNode.type.name !== expectedPmType) {
    replaceSubtree(tr, pmNode, proj, pmPos);
    return;
  }

  // 2. Handle Module specially (has synthesized let_def wrappers)
  if (tag === "Module") {
    diffModule(tr, pmNode, proj, pmPos);
    return;
  }

  // 3. Check attributes
  const newAttrs = projAttrs(proj, tag);
  if (!attrsEqual(pmNode.attrs as Record<string, unknown>, newAttrs)) {
    const mappedPos = tr.mapping.map(pmPos);
    tr.setNodeMarkup(mappedPos, null, newAttrs);
  }

  // 4. For atom nodes (leaves), we're done — attrs carry all the data
  if (pmNode.isAtom) return;

  // 5. For compound nodes, recurse into children
  diffChildren(tr, pmNode, proj, pmPos);
}

/**
 * Replace an entire PM subtree with a freshly-converted ProjNode.
 */
function replaceSubtree(
  tr: Transaction,
  pmNode: PmNode,
  proj: ProjNodeJson,
  pmPos: number,
): void {
  const newPm = projNodeToPmNode(proj);
  const from = tr.mapping.map(pmPos);
  const to = tr.mapping.map(pmPos + pmNode.nodeSize);
  tr.replaceWith(from, to, newPm);
}

/**
 * Diff the children of a non-Module compound node.
 *
 * For lambda, application, binary_op, if_expr: the PM children correspond
 * 1:1 with the ProjNode children.
 */
function diffChildren(
  tr: Transaction,
  pmNode: PmNode,
  proj: ProjNodeJson,
  pmPos: number,
): void {
  const projChildren = proj.children;
  let childIndex = 0;

  // Walk PM children and match to ProjNode children by index
  pmNode.forEach((child, offset, index) => {
    if (childIndex < projChildren.length) {
      // pmPos + 1 skips the parent's open tag
      // offset is the offset from the start of the parent's content
      const childPmPos = pmPos + 1 + offset;
      diffNode(tr, child, projChildren[childIndex], childPmPos);
    }
    childIndex++;
  });

  // If child count changed (shouldn't happen for non-Module fixed-arity nodes,
  // but handle defensively), do a full subtree replace
  if (childIndex !== projChildren.length) {
    replaceSubtree(tr, pmNode, proj, pmPos);
  }
}

/**
 * Diff a Module node, handling the let_def wrapper asymmetry.
 *
 * ProjNode Module: children = [init0, init1, ..., body]
 * PM module:       children = [let_def(init0), let_def(init1), ..., body_term]
 *
 * The let_def nodes are synthesized during conversion. We need to:
 * - Match let_defs by position
 * - Check let_def attrs (name) and recurse into their single child (the init term)
 * - Match the body term (last child in both)
 */
function diffModule(
  tr: Transaction,
  pmNode: PmNode,
  proj: ProjNodeJson,
  pmPos: number,
): void {
  // Check module-level attributes
  const newModuleAttrs = projAttrs(proj, "Module");
  if (
    !attrsEqual(pmNode.attrs as Record<string, unknown>, newModuleAttrs)
  ) {
    const mappedPos = tr.mapping.map(pmPos);
    tr.setNodeMarkup(mappedPos, null, newModuleAttrs);
  }

  const defs: [string, any][] = proj.kind[1];
  const projChildren = proj.children;
  const numDefs = projChildren.length - 1; // all except last (body)
  const bodyProj = projChildren[projChildren.length - 1];

  // Count PM children
  let pmChildCount = 0;
  pmNode.forEach(() => {
    pmChildCount++;
  });

  // If structural mismatch in child count, replace entire module
  // PM should have numDefs let_defs + 1 body = numDefs + 1 = projChildren.length
  if (pmChildCount !== projChildren.length) {
    replaceSubtree(tr, pmNode, proj, pmPos);
    return;
  }

  // Collect PM children first (can't bail out of forEach)
  const pmChildren: { node: PmNode; offset: number }[] = [];
  pmNode.forEach((child, offset) => {
    pmChildren.push({ node: child, offset });
  });

  for (let childIndex = 0; childIndex < pmChildren.length; childIndex++) {
    const { node: pmChild, offset } = pmChildren[childIndex];
    const childPmPos = pmPos + 1 + offset;

    if (childIndex < numDefs) {
      // This PM child should be a let_def wrapping projChildren[childIndex]
      if (pmChild.type.name !== "let_def") {
        // Type mismatch — replace entire module and stop
        replaceSubtree(tr, pmNode, proj, pmPos);
        return;
      }

      // Check let_def attrs
      const defName = childIndex < defs.length ? defs[childIndex][0] : "_";
      const expectedLetDefAttrs = {
        name: defName,
        nodeId: projChildren[childIndex].node_id,
      };
      if (
        !attrsEqual(
          pmChild.attrs as Record<string, unknown>,
          expectedLetDefAttrs,
        )
      ) {
        const mappedPos = tr.mapping.map(childPmPos);
        tr.setNodeMarkup(mappedPos, null, expectedLetDefAttrs);
      }

      // Recurse into the let_def's single child (the init term)
      const initProj = projChildren[childIndex];
      if (pmChild.childCount === 1) {
        const initPm = pmChild.firstChild!;
        const initPmPos = childPmPos + 1;
        diffNode(tr, initPm, initProj, initPmPos);
      } else {
        const newInitPm = projNodeToPmNode(initProj);
        const from = tr.mapping.map(childPmPos + 1);
        const to = tr.mapping.map(childPmPos + 1 + pmChild.content.size);
        tr.replaceWith(from, to, newInitPm);
      }
    } else {
      // Last child: the body term (not wrapped in let_def)
      diffNode(tr, pmChild, bodyProj, childPmPos);
    }
  }
}
