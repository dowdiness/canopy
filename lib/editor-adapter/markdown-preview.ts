// MarkdownPreview: Read-only semantic HTML renderer for ViewPatch streams.

import type { EditorAdapter } from './adapter';
import type { ViewNode, ViewPatch, UserIntent } from './types';

/** Extract heading level from css_class like "heading-2" → 2, default 1 */
function headingLevel(cssClass: string): number {
  const m = cssClass.match(/heading-(\d)/);
  return m ? Math.min(Math.max(Number(m[1]), 1), 6) : 1;
}

/** Create the appropriate semantic element for a ViewNode based on kind_tag */
function semanticTag(node: ViewNode): HTMLElement {
  switch (node.kind_tag) {
    case 'heading':
      return document.createElement(`h${headingLevel(node.css_class)}`);
    case 'paragraph':
      return document.createElement('p');
    case 'unordered_list':
      return document.createElement('ul');
    case 'list_item':
      return document.createElement('li');
    case 'code_block': {
      const pre = document.createElement('pre');
      const code = document.createElement('code');
      pre.appendChild(code);
      return pre;
    }
    case 'document':
    default:
      return document.createElement('div');
  }
}

function renderNode(node: ViewNode): HTMLElement {
  const el = semanticTag(node);
  el.setAttribute('data-node-id', String(node.id));

  // For code_block, text goes inside the <code> child
  const textTarget = node.kind_tag === 'code_block'
    ? el.querySelector('code')!
    : el;

  const text = node.text ?? node.label;
  if (text && node.children.length === 0) {
    textTarget.textContent = text;
  }

  for (const child of node.children) {
    textTarget.appendChild(renderNode(child));
  }

  return el;
}

// --- Tree mutation helpers ---

function replaceInTree(tree: ViewNode, id: number, replacement: ViewNode): ViewNode {
  if (tree.id === id) return replacement;
  return { ...tree, children: tree.children.map(c => replaceInTree(c, id, replacement)) };
}

function insertInTree(tree: ViewNode, parentId: number, index: number, child: ViewNode): ViewNode {
  if (tree.id === parentId) {
    const ch = [...tree.children];
    ch.splice(index, 0, child);
    return { ...tree, children: ch };
  }
  return { ...tree, children: tree.children.map(c => insertInTree(c, parentId, index, child)) };
}

function removeFromTree(tree: ViewNode, parentId: number, childId: number): ViewNode {
  if (tree.id === parentId) {
    return { ...tree, children: tree.children.filter(c => c.id !== childId) };
  }
  return { ...tree, children: tree.children.map(c => removeFromTree(c, parentId, childId)) };
}

function updateInTree(tree: ViewNode, id: number, label: string, cssClass: string, text?: string): ViewNode {
  if (tree.id === id) {
    return { ...tree, label, css_class: cssClass, ...(text !== undefined ? { text } : {}) };
  }
  return { ...tree, children: tree.children.map(c => updateInTree(c, id, label, cssClass, text)) };
}

export class MarkdownPreview implements EditorAdapter {
  private container: HTMLElement;
  private currentTree: ViewNode | null = null;

  constructor(container: HTMLElement) {
    this.container = container;
  }

  applyPatches(patches: ViewPatch[]): void {
    for (const patch of patches) {
      switch (patch.type) {
        case 'FullTree':
          this.currentTree = patch.root;
          this.container.replaceChildren();
          if (patch.root) this.container.appendChild(renderNode(patch.root));
          break;

        case 'ReplaceNode': {
          const el = this.container.querySelector(`[data-node-id="${patch.node_id}"]`);
          if (el?.parentElement) el.parentElement.replaceChild(renderNode(patch.node), el);
          if (this.currentTree) this.currentTree = replaceInTree(this.currentTree, patch.node_id, patch.node);
          break;
        }

        case 'InsertChild': {
          const parentEl = this.container.querySelector(`[data-node-id="${patch.parent_id}"]`);
          if (parentEl) {
            const ref = parentEl.children[patch.index] ?? null;
            parentEl.insertBefore(renderNode(patch.child), ref);
          }
          if (this.currentTree) this.currentTree = insertInTree(this.currentTree, patch.parent_id, patch.index, patch.child);
          break;
        }

        case 'RemoveChild': {
          const el = this.container.querySelector(`[data-node-id="${patch.child_id}"]`);
          if (el) el.remove();
          if (this.currentTree) this.currentTree = removeFromTree(this.currentTree, patch.parent_id, patch.child_id);
          break;
        }

        case 'UpdateNode': {
          const el = this.container.querySelector(`[data-node-id="${patch.node_id}"]`);
          if (el) {
            // Only set textContent on leaf elements — containers have child elements
            if (el.children.length === 0) {
              el.textContent = patch.text ?? patch.label;
            }
            if (patch.css_class) el.className = patch.css_class;
          }
          if (this.currentTree) this.currentTree = updateInTree(this.currentTree, patch.node_id, patch.label, patch.css_class, patch.text ?? undefined);
          break;
        }

        default:
          break;
      }
    }
  }

  onIntent(_callback: (intent: UserIntent) => void): void {
    // Read-only — no intents emitted
  }

  destroy(): void {
    this.currentTree = null;
    this.container.replaceChildren();
  }
}
