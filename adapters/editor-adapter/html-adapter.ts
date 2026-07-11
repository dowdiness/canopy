// HTMLAdapter: Vanilla DOM renderer for ViewPatch streams.

import type { EditorAdapter } from './adapter';
import type { ViewNode, ViewPatch, UserIntent, Diagnostic } from './types';

function parseObjectKeys(label: string): string[] | null {
  if (!label.startsWith('{') || !label.endsWith('}')) return null;
  const inner = label.slice(1, -1).trim();
  if (!inner) return [];
  return inner.split(',').map(k => k.trim());
}

/** Append annotation badges to a node row */
function renderAnnotations(row: HTMLElement, node: ViewNode): void {
  if (!node.annotations || node.annotations.length === 0) return;
  for (const ann of node.annotations) {
    const badge = document.createElement('span');
    badge.className = `annotation-${ann.kind} severity-${ann.severity}`;
    badge.textContent = ann.label;
    row.appendChild(badge);
  }
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
/** CSS classes referenced by language-specific stylesheets. */
const CSS = {
  TOGGLE: 'node-toggle',
  COLLAPSED: 'collapsed',
  VALUE_NODE: 'value-node',
  COUNT_BADGE: 'node-count',
} as const;

export class HTMLAdapter implements EditorAdapter {
  private container: HTMLElement;
  private diagnosticsEl: HTMLElement | null;
  private intentCallback: ((intent: UserIntent) => void) | null = null;
  private selectedNodeId: number | null = null;
  private currentTree: ViewNode | null = null;
  private collapsedNodes = new Set<number>();
  private enableToggles: boolean;

  constructor(container: HTMLElement, diagnosticsEl?: HTMLElement, enableToggles = false) {
    this.container = container;
    this.diagnosticsEl = diagnosticsEl ?? null;
    this.enableToggles = enableToggles;
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
    this.collapsedNodes.clear();
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

  /** Clear collapse state and expand all rendered nodes. */
  resetCollapseState(): void {
    this.collapsedNodes.clear();
    for (const el of this.container.querySelectorAll(`.${CSS.COLLAPSED}`)) {
      el.classList.remove(CSS.COLLAPSED);
      const btn = el.querySelector<HTMLButtonElement>(`:scope > .node-row > .${CSS.TOGGLE}`);
      if (btn) {
        btn.textContent = '▼';
        btn.setAttribute('aria-expanded', 'true');
      }
    }
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
        // Update currentTree first so the parent has the child on re-render
        if (this.currentTree) {
          this.currentTree = insertChildInTree(this.currentTree, patch.parent_id, patch.index, patch.child);
        }
        const parentEl = this.container.querySelector(`[data-node-id="${patch.parent_id}"]`) as HTMLElement | null;
        if (parentEl) {
          const hasContainerChrome = parentEl.querySelector(':scope > .node-children') !== null;
          if (hasContainerChrome) {
            // Normal incremental insert
            const childrenEl = parentEl.querySelector(':scope > .node-children')!;
            const newChild = this.renderNode(patch.child, null, false);
            const refChild = childrenEl.children[patch.index] ?? null;
            childrenEl.insertBefore(newChild, refChild);
            this.updateCountBadge(parentEl, childrenEl.children.length);
          } else {
            // Parent was a leaf — re-render with full container chrome
            const parentNode = this.currentTree
              ? findNodeInTree(this.currentTree, patch.parent_id)
              : null;
            if (parentNode) {
              const parentViewNode = this.currentTree
                ? findParentInTree(this.currentTree, patch.parent_id)
                : null;
              const edgeLabel = deriveEdgeLabel(this.container, parentEl, parentViewNode);
              const isRoot = parentEl === this.container.firstElementChild;
              const newEl = this.renderNode(parentNode, edgeLabel, isRoot);
              parentEl.parentElement?.replaceChild(newEl, parentEl);
            }
          }
        }
        break;
      }

      case 'RemoveChild': {
        const el = this.container.querySelector(`[data-node-id="${patch.child_id}"]`);
        if (el) {
          const parentEl = el.parentElement?.parentElement;
          el.remove();
          if (parentEl) {
            const childrenEl = parentEl.querySelector(':scope > .node-children');
            if (childrenEl) this.updateCountBadge(parentEl, childrenEl.children.length);
          }
        }
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
            const kindClass = patch.css_class;
            classes.push(`kind-${kindClass}`);
            el.className = classes.join(' ');
            // Keep data-node-kind in sync so refreshInlineControls reads the current type
            const kindTag = kindClass.charAt(0).toUpperCase() + kindClass.slice(1);
            el.setAttribute('data-node-kind', kindTag);
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
      wrapper.classList.add(`kind-${kindClass}`);
      wrapper.setAttribute('data-node-id', String(node.id));
      wrapper.setAttribute('data-node-kind', node.kind_tag);

      const row = document.createElement('div');
      row.className = 'node-row value-node';
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

      renderAnnotations(row, node);

      wrapper.appendChild(row);
      return wrapper;
    }
    const container = document.createElement('div');
    container.className = isRoot ? 'tree-node root' : 'tree-node';
    container.classList.add(`kind-${kindClass}`);
    container.setAttribute('data-node-id', String(node.id));
    container.setAttribute('data-node-kind', node.kind_tag);

    const row = document.createElement('div');
    row.className = 'node-row';
    if (node.id === this.selectedNodeId) row.classList.add('selected');

    row.addEventListener('click', (e) => {
      e.stopPropagation();
      this.selectNode(node.id);
    });

    // Expand/collapse toggle (only when opt-in)
    const toggle = this.enableToggles
      ? this.createToggle(container, node.id)
      : null;
    if (toggle) row.appendChild(toggle);

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
    countEl.className = CSS.COUNT_BADGE;
    countEl.textContent = String(node.children.length);
    row.appendChild(countEl);

    const idEl = document.createElement('span');
    idEl.className = 'node-id';
    idEl.textContent = ` #${node.id}`;
    row.appendChild(idEl);

    renderAnnotations(row, node);

    container.appendChild(row);

    // Wrap children in .node-children so InsertChild indexing works correctly
    const childrenContainer = document.createElement('div');
    childrenContainer.className = 'node-children';
    for (let i = 0; i < node.children.length; i++) {
      const childEdge = edgeLabelFor(node, i);
      childrenContainer.appendChild(this.renderNode(node.children[i], childEdge, false));
    }
    container.appendChild(childrenContainer);

    // Restore collapse state after rendering (only when toggles enabled)
    if (this.enableToggles && this.collapsedNodes.has(node.id)) {
      container.classList.add(CSS.COLLAPSED);
      if (toggle) {
        toggle.textContent = '▶';
        toggle.setAttribute('aria-expanded', 'false');
      }
    }
    return container;
  }

  /** Create an accessible expand/collapse toggle button for a container. */
  private createToggle(container: HTMLElement, nodeId: number): HTMLButtonElement {
    const btn = document.createElement('button');
    btn.type = 'button';
    btn.className = CSS.TOGGLE;
    btn.setAttribute('aria-expanded', 'true');
    btn.textContent = '▼';
    btn.addEventListener('click', (e) => {
      e.stopPropagation();
      const wasCollapsed = container.classList.toggle(CSS.COLLAPSED);
      if (wasCollapsed) {
        this.collapsedNodes.add(nodeId);
        btn.setAttribute('aria-expanded', 'false');
        btn.textContent = '▶';
      } else {
        this.collapsedNodes.delete(nodeId);
        btn.setAttribute('aria-expanded', 'true');
        btn.textContent = '▼';
      }
    });
    return btn;
  }

  /** Update the .node-count badge on a container element. */
  private updateCountBadge(container: HTMLElement, count: number): void {
    const badge = container.querySelector(`:scope > .node-row > .${CSS.COUNT_BADGE}`);
    if (badge) badge.textContent = String(count);
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
