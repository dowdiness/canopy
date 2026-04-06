// MarkdownPreview: Read-only semantic HTML renderer for ViewPatch streams.

import type { EditorAdapter } from './adapter';
import type { ViewNode, ViewPatch, UserIntent } from './types';

/** Extract heading level from kind_tag like "H2" → 2, or 0 if not a heading */
function headingLevel(kindTag: string): number {
  const m = kindTag.match(/^H(\d)$/);
  return m ? Math.min(Math.max(Number(m[1]), 1), 6) : 0;
}

/** Create the appropriate semantic element for a ViewNode based on kind_tag */
function semanticTag(node: ViewNode): HTMLElement {
  // Headings: kind_tag is "H1"–"H6"
  const hLevel = headingLevel(node.kind_tag);
  if (hLevel > 0) {
    return document.createElement(`h${hLevel}`);
  }
  switch (node.kind_tag) {
    case 'Paragraph':
      return document.createElement('p');
    case 'List':
      return document.createElement('ul');
    case 'ListItem':
      return document.createElement('li');
    default:
      // Code blocks: kind_tag is "Code" or "Code(lang)"
      if (node.kind_tag.startsWith('Code')) {
        const pre = document.createElement('pre');
        const code = document.createElement('code');
        pre.appendChild(code);
        return pre;
      }
      return document.createElement('div');
  }
}

function renderNode(node: ViewNode): HTMLElement {
  const el = semanticTag(node);
  el.setAttribute('data-node-id', String(node.id));
  if (node.css_class) el.className = node.css_class;

  // For code blocks (kind_tag "Code" or "Code(lang)"), text goes inside the <code> child
  const textTarget = node.kind_tag.startsWith('Code')
    ? (el.querySelector('code') ?? el)
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

function updateInTree(tree: ViewNode, id: number, label: string, cssClass: string, text: string | null): ViewNode {
  if (tree.id === id) {
    return { ...tree, label, css_class: cssClass, text };
  }
  return { ...tree, children: tree.children.map(c => updateInTree(c, id, label, cssClass, text)) };
}

function findInTree(tree: ViewNode, id: number): ViewNode | null {
  if (tree.id === id) return tree;
  for (const child of tree.children) {
    const found = findInTree(child, id);
    if (found) return found;
  }
  return null;
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
            // Code blocks: insert into <code> child, not <pre> wrapper
            const target = parentEl.tagName === 'PRE'
              ? (parentEl.querySelector('code') ?? parentEl)
              : parentEl;
            const ref = target.children[patch.index] ?? null;
            target.insertBefore(renderNode(patch.child), ref);
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
          if (this.currentTree) this.currentTree = updateInTree(this.currentTree, patch.node_id, patch.label, patch.css_class, patch.text);
          const el = this.container.querySelector(`[data-node-id="${patch.node_id}"]`);
          if (el) {
            // Check if the semantic tag needs to change (e.g., h1 → h2 on heading level change)
            const updatedNode = this.currentTree ? findInTree(this.currentTree, patch.node_id) : null;
            if (updatedNode) {
              const requiredTag = semanticTag(updatedNode).tagName;
              if (el.tagName !== requiredTag) {
                // Tag changed — re-render the full node
                const newEl = renderNode(updatedNode);
                el.parentElement?.replaceChild(newEl, el);
                break;
              }
            }
            // Tag unchanged — update text in place
            const text = patch.text ?? patch.label;
            if (el.tagName === 'PRE') {
              // Code block: update the <code> child, not the <pre> wrapper
              const code = el.querySelector('code');
              if (code) code.textContent = text;
            } else if (el.children.length === 0) {
              el.textContent = text;
            }
            el.className = patch.css_class;
          }
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
