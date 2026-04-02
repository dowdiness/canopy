// HTMLAdapter: Vanilla DOM renderer for ViewPatch streams.

import type { EditorAdapter } from './adapter';
import type { ViewNode, ViewPatch, UserIntent, Diagnostic } from './types';

function parseObjectKeys(label: string): string[] | null {
  if (!label.startsWith('{') || !label.endsWith('}')) return null;
  const inner = label.slice(1, -1).trim();
  if (!inner) return [];
  return inner.split(',').map(k => k.trim());
}

function edgeLabelFor(parent: ViewNode, childIndex: number): string {
  if (parent.kind_tag === 'Object') {
    const keys = parseObjectKeys(parent.label);
    if (keys && childIndex < keys.length) return keys[childIndex];
  }
  return String(childIndex);
}

/** Derive edge label for a node being replaced, by finding its index in the parent. */
function deriveEdgeLabel(container: HTMLElement, el: Element, parentNode: ViewNode | null): string | null {
  if (!parentNode) return null;
  const parentEl = container.querySelector(`[data-node-id="${parentNode.id}"]`);
  if (!parentEl) return null;
  const childrenContainer = parentEl.querySelector(':scope > .node-children') ?? parentEl;
  const siblings = childrenContainer.children;
  for (let i = 0; i < siblings.length; i++) {
    if (siblings[i] === el) return edgeLabelFor(parentNode, i);
  }
  return null;
}

export class HTMLAdapter implements EditorAdapter {
  private container: HTMLElement;
  private diagnosticsEl: HTMLElement | null;
  private intentCallback: ((intent: UserIntent) => void) | null = null;
  private selectedNodeId: number | null = null;
  private currentTree: ViewNode | null = null;

  constructor(container: HTMLElement, diagnosticsEl?: HTMLElement) {
    this.container = container;
    this.diagnosticsEl = diagnosticsEl ?? null;
  }

  applyPatches(patches: ViewPatch[]): void {
    for (const patch of patches) {
      this.applyPatch(patch);
    }
  }

  onIntent(callback: (intent: UserIntent) => void): void {
    this.intentCallback = callback;
  }

  destroy(): void {
    this.intentCallback = null;
    this.currentTree = null;
    this.container.replaceChildren();
    if (this.diagnosticsEl) this.diagnosticsEl.replaceChildren();
  }

  getSelectedNodeId(): number | null {
    return this.selectedNodeId;
  }

  getTree(): ViewNode | null {
    return this.currentTree;
  }

  findNode(nodeId: number): ViewNode | null {
    if (!this.currentTree) return null;
    return findNodeInTree(this.currentTree, nodeId);
  }

  private applyPatch(patch: ViewPatch): void {
    switch (patch.type) {
      case 'FullTree':
        this.currentTree = patch.root;
        this.container.replaceChildren();
        if (patch.root) {
          this.container.appendChild(this.renderNode(patch.root, null, true));
        } else {
          const empty = document.createElement('div');
          empty.className = 'tree-empty';
          empty.textContent = 'No structure available';
          this.container.appendChild(empty);
        }
        break;

      case 'ReplaceNode': {
        const el = this.container.querySelector(`[data-node-id="${patch.node_id}"]`);
        if (el && el.parentElement) {
          const isRoot = el === this.container.firstElementChild;
          // Derive edge label from parent context
          const parentViewNode = this.currentTree
            ? findParentInTree(this.currentTree, patch.node_id)
            : null;
          const edgeLabel = deriveEdgeLabel(this.container, el, parentViewNode);
          const newEl = this.renderNode(patch.node, edgeLabel, isRoot);
          el.parentElement.replaceChild(newEl, el);
        }
        // Update currentTree
        if (this.currentTree) {
          this.currentTree = replaceNodeInTree(this.currentTree, patch.node_id, patch.node);
        }
        break;
      }

      case 'InsertChild': {
        const parentEl = this.container.querySelector(`[data-node-id="${patch.parent_id}"]`);
        if (parentEl) {
          const childrenEl = parentEl.querySelector(':scope > .node-children') ?? parentEl;
          const newChild = this.renderNode(patch.child, null, false);
          // .node-children contains only tree-node children (no .node-row offset)
          const refChild = childrenEl.children[patch.index] ?? null;
          childrenEl.insertBefore(newChild, refChild);
        }
        // Update currentTree
        if (this.currentTree) {
          this.currentTree = insertChildInTree(this.currentTree, patch.parent_id, patch.index, patch.child);
        }
        break;
      }

      case 'RemoveChild': {
        const el = this.container.querySelector(`[data-node-id="${patch.child_id}"]`);
        if (el) el.remove();
        // Update currentTree
        if (this.currentTree) {
          this.currentTree = removeChildInTree(this.currentTree, patch.parent_id, patch.child_id);
        }
        break;
      }

      case 'UpdateNode': {
        const el = this.container.querySelector(`[data-node-id="${patch.node_id}"]`);
        if (el) {
          const labelEl = el.querySelector(':scope > .node-row > .node-tag') ??
                          el.querySelector(':scope > .node-tag');
          if (labelEl) labelEl.textContent = patch.label;
          if (patch.css_class) {
            const classes = el.className.split(/\s+/).filter(c => !c.startsWith('kind-'));
            classes.push(`kind-${patch.css_class}`);
            el.className = classes.join(' ');
          }
        }
        // Update currentTree
        if (this.currentTree) {
          this.currentTree = updateNodeInTree(this.currentTree, patch.node_id, patch.label, patch.css_class, patch.text ?? undefined);
        }
        break;
      }

      case 'SetDiagnostics':
        if (this.diagnosticsEl) this.renderDiagnostics(patch.diagnostics);
        break;

      case 'SelectNode':
        this.selectNode(patch.node_id);
        break;

      case 'TextChange':
      case 'SetDecorations':
      case 'SetSelection':
        break;
    }
  }

  private renderNode(node: ViewNode, edgeLabel: string | null, isRoot: boolean): HTMLElement {
    // Formatted text display (pretty-printer output)
    if (node.kind_tag === 'formatted-text') {
      return this.renderFormattedText(node, isRoot);
    }
    if (node.text != null) {
      return this.renderTextLine(node);
    }

    const hasChildren = node.children.length > 0;
    const kindClass = node.kind_tag.toLowerCase();

    if (!hasChildren) {
      const wrapper = document.createElement('div');
      wrapper.className = isRoot ? 'tree-node root' : 'tree-node';
      wrapper.setAttribute('data-node-id', String(node.id));

      const row = document.createElement('div');
      row.className = 'node-row';
      if (node.id === this.selectedNodeId) row.classList.add('selected');
      row.addEventListener('click', (e) => {
        e.stopPropagation();
        this.selectNode(node.id);
      });

      if (edgeLabel !== null) {
        const keyEl = document.createElement('span');
        keyEl.className = 'node-key';
        keyEl.textContent = `${edgeLabel}:`;
        row.appendChild(keyEl);
      }

      const tagEl = document.createElement('span');
      tagEl.className = `node-tag ${kindClass}`;
      tagEl.textContent = node.label;
      row.appendChild(tagEl);

      const idEl = document.createElement('span');
      idEl.className = 'node-id';
      idEl.textContent = ` #${node.id}`;
      row.appendChild(idEl);

      wrapper.appendChild(row);
      return wrapper;
    }

    const container = document.createElement('div');
    container.className = isRoot ? 'tree-node root' : 'tree-node';
    container.setAttribute('data-node-id', String(node.id));

    const row = document.createElement('div');
    row.className = 'node-row';
    if (node.id === this.selectedNodeId) row.classList.add('selected');

    row.addEventListener('click', (e) => {
      e.stopPropagation();
      this.selectNode(node.id);
    });

    if (edgeLabel !== null) {
      const keyEl = document.createElement('span');
      keyEl.className = 'node-key';
      keyEl.textContent = `${edgeLabel}:`;
      row.appendChild(keyEl);
    }

    const displayLabel = (node.kind_tag === 'Object' || node.kind_tag === 'Array')
      ? node.kind_tag
      : node.label;

    const tagEl = document.createElement('span');
    tagEl.className = `node-tag ${kindClass}`;
    tagEl.textContent = displayLabel;
    row.appendChild(tagEl);

    const countEl = document.createElement('span');
    countEl.className = 'node-id';
    countEl.textContent = ` (${node.children.length})`;
    row.appendChild(countEl);

    const idEl = document.createElement('span');
    idEl.className = 'node-id';
    idEl.textContent = ` #${node.id}`;
    row.appendChild(idEl);

    container.appendChild(row);

    // Wrap children in .node-children so InsertChild indexing works correctly
    const childrenContainer = document.createElement('div');
    childrenContainer.className = 'node-children';
    for (let i = 0; i < node.children.length; i++) {
      const childEdge = edgeLabelFor(node, i);
      childrenContainer.appendChild(this.renderNode(node.children[i], childEdge, false));
    }
    container.appendChild(childrenContainer);

    return container;
  }

  private renderFormattedText(node: ViewNode, isRoot: boolean): HTMLElement {
    const pre = document.createElement('pre');
    pre.className = isRoot ? 'formatted-text root' : 'formatted-text';
    pre.setAttribute('data-node-id', String(node.id));
    for (let i = 0; i < node.children.length; i++) {
      pre.appendChild(this.renderNode(node.children[i], null, false));
    }
    return pre;
  }

  private renderTextLine(node: ViewNode): HTMLElement {
    const div = document.createElement('div');
    div.className = 'line';
    div.setAttribute('data-node-id', String(node.id));
    const text = node.text ?? '';
    const spans = [...node.token_spans].sort((a, b) => a.start - b.start);
    let pos = 0;
    for (const span of spans) {
      // Gap before this span: unstyled text
      if (span.start > pos) {
        div.appendChild(document.createTextNode(text.slice(pos, span.start)));
      }
      // Styled span
      const el = document.createElement('span');
      el.className = span.role;
      el.textContent = text.slice(span.start, span.end);
      div.appendChild(el);
      pos = span.end;
    }
    // Trailing unstyled text
    if (pos < text.length) {
      div.appendChild(document.createTextNode(text.slice(pos)));
    }
    return div;
  }

  private renderDiagnostics(diagnostics: Diagnostic[]): void {
    if (!this.diagnosticsEl) return;
    this.diagnosticsEl.replaceChildren();

    if (diagnostics.length === 0) {
      const item = document.createElement('li');
      item.className = 'error-empty';
      item.textContent = 'No parse errors';
      this.diagnosticsEl.appendChild(item);
      return;
    }

    for (const d of diagnostics) {
      const item = document.createElement('li');
      item.className = `error-item severity-${d.severity}`;
      item.textContent = d.message;
      this.diagnosticsEl.appendChild(item);
    }
  }

  private selectNode(nodeId: number): void {
    const prev = this.container.querySelector('.node-row.selected');
    if (prev) prev.classList.remove('selected');

    this.selectedNodeId = nodeId;

    const el = this.container.querySelector(`[data-node-id="${nodeId}"]`);
    if (el) {
      const row = el.querySelector(':scope > .node-row');
      if (row) row.classList.add('selected');
    }

    if (this.intentCallback) {
      this.intentCallback({ type: 'SelectNode', node_id: nodeId });
    }
  }
}

// --- ViewNode tree mutation helpers (keep currentTree in sync with DOM) ---

function findNodeInTree(node: ViewNode, nodeId: number): ViewNode | null {
  if (node.id === nodeId) return node;
  for (const child of node.children) {
    const found = findNodeInTree(child, nodeId);
    if (found) return found;
  }
  return null;
}

function findParentInTree(node: ViewNode, childId: number): ViewNode | null {
  for (const child of node.children) {
    if (child.id === childId) return node;
    const found = findParentInTree(child, childId);
    if (found) return found;
  }
  return null;
}

function replaceNodeInTree(tree: ViewNode, nodeId: number, replacement: ViewNode): ViewNode {
  if (tree.id === nodeId) return replacement;
  return {
    ...tree,
    children: tree.children.map(c => replaceNodeInTree(c, nodeId, replacement)),
  };
}

function insertChildInTree(tree: ViewNode, parentId: number, index: number, child: ViewNode): ViewNode {
  if (tree.id === parentId) {
    const newChildren = [...tree.children];
    newChildren.splice(index, 0, child);
    return { ...tree, children: newChildren };
  }
  return {
    ...tree,
    children: tree.children.map(c => insertChildInTree(c, parentId, index, child)),
  };
}

function removeChildInTree(tree: ViewNode, parentId: number, childId: number): ViewNode {
  if (tree.id === parentId) {
    return { ...tree, children: tree.children.filter(c => c.id !== childId) };
  }
  return {
    ...tree,
    children: tree.children.map(c => removeChildInTree(c, parentId, childId)),
  };
}

function updateNodeInTree(tree: ViewNode, nodeId: number, label: string, cssClass: string, text?: string): ViewNode {
  if (tree.id === nodeId) {
    return { ...tree, label, css_class: cssClass, ...(text !== undefined ? { text } : {}) };
  }
  return {
    ...tree,
    children: tree.children.map(c => updateNodeInTree(c, nodeId, label, cssClass, text)),
  };
}
