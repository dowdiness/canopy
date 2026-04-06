// BlockInput — Canopy-owned thin input layer for block-mode editing.
// Follows the Excalidraw textarea overlay pattern: a single <textarea>
// is positioned over the active block div, matching its computed font.

import type { EditorAdapter } from './adapter';
import type { ViewNode, ViewPatch, UserIntent } from './types';

// ---------------------------------------------------------------------------
// BlockInput
// ---------------------------------------------------------------------------

export class BlockInput implements EditorAdapter {
  private container: HTMLElement;
  private currentTree: ViewNode | null = null;
  private activeBlockId: number | null = null;
  private textarea: HTMLTextAreaElement | null = null;
  private blurBound = false;
  private composing = false;
  private intentCb: ((intent: UserIntent) => void) | null = null;

  constructor(container: HTMLElement) {
    this.container = container;
    this.container.classList.add('block-editor');
    this.onContainerClick = this.onContainerClick.bind(this);
    this.container.addEventListener('click', this.onContainerClick);
  }

  // --- EditorAdapter interface ---------------------------------------------

  applyPatches(patches: ViewPatch[]): void {
    for (const p of patches) {
      switch (p.type) {
        case 'FullTree':
          this.currentTree = p.root;
          this.renderAll();
          break;
        case 'ReplaceNode':
          this.replaceNode(p.node_id, p.node);
          break;
        case 'InsertChild':
          this.insertChild(p.parent_id, p.index, p.child);
          break;
        case 'RemoveChild':
          this.removeChild(p.parent_id, p.child_id);
          break;
        case 'UpdateNode':
          this.updateNode(p.node_id, p.label, p.css_class, p.text);
          break;
        case 'SelectNode':
          this.activateBlock(p.node_id);
          break;
        // TextChange, SetDecorations, etc. are not applicable to block mode
      }
    }
  }

  onIntent(callback: (intent: UserIntent) => void): void {
    this.intentCb = callback;
  }

  destroy(): void {
    this.deactivate();
    this.container.removeEventListener('click', this.onContainerClick);
    this.container.innerHTML = '';
    this.currentTree = null;
    if (this.textarea) {
      this.textarea.remove();
      this.textarea = null;
    }
  }

  // --- Rendering -----------------------------------------------------------

  private renderAll(): void {
    this.container.innerHTML = '';
    if (!this.currentTree) return;
    for (const block of this.collectEditableBlocks(this.currentTree)) {
      this.container.appendChild(this.createBlockDiv(block));
    }
    if (this.activeBlockId !== null) this.positionTextarea();
  }

  /** Recursively collect editable leaf blocks (flattens containers like UnorderedList) */
  private collectEditableBlocks(node: ViewNode): ViewNode[] {
    const result: ViewNode[] = [];
    for (const child of node.children) {
      if (child.editable) {
        result.push(child);
      } else if (child.children.length > 0) {
        // Container (e.g., UnorderedList) — descend into children
        result.push(...this.collectEditableBlocks(child));
      }
    }
    return result;
  }

  /** Create a semantic block element based on kind_tag. */
  private createBlockDiv(node: ViewNode): HTMLElement {
    const el = this.semanticBlockElement(node.kind_tag);
    el.className = 'block' + (node.id === this.activeBlockId ? ' active' : '');
    if (node.css_class) el.className += ' ' + node.css_class;
    el.dataset.nodeId = String(node.id);
    el.dataset.kind = node.kind_tag;

    const textSpan = document.createElement('span');
    textSpan.className = 'block-text';
    // Strip ZWSP placeholder so empty blocks show as truly empty
    textSpan.textContent = (node.text ?? '').replace(/\u200B/g, '');
    el.appendChild(textSpan);

    el.addEventListener('click', (e) => {
      e.stopPropagation();
      this.activateBlock(node.id);
    });

    return el;
  }

  /** Map kind_tag to the appropriate semantic HTML element. */
  private semanticBlockElement(kindTag: string): HTMLElement {
    const hLevel = this.headingLevelFromTag(kindTag);
    if (hLevel > 0) return document.createElement(`h${hLevel}`);
    switch (kindTag) {
      case 'Paragraph': return document.createElement('p');
      case 'ListItem': return document.createElement('p');
      default:
        if (kindTag.startsWith('Code'))
          return document.createElement('pre');
        return document.createElement('div');
    }
  }

  /** Extract heading level from kind_tag like "H1" → 1, or 0 if not a heading. */
  private headingLevelFromTag(kindTag: string): number {
    const m = kindTag.match(/^H(\d)$/);
    return m ? parseInt(m[1], 10) : 0;
  }

  // --- Patch helpers -------------------------------------------------------

  private findNode(id: number, node: ViewNode | null = this.currentTree): ViewNode | null {
    if (!node) return null;
    if (node.id === id) return node;
    for (const c of node.children) {
      const found = this.findNode(id, c);
      if (found) return found;
    }
    return null;
  }

  private replaceNode(nodeId: number, replacement: ViewNode): void {
    if (!this.currentTree) return;
    const parent = this.findParent(nodeId, this.currentTree);
    if (parent) {
      const idx = parent.children.findIndex(c => c.id === nodeId);
      if (idx !== -1) parent.children[idx] = replacement;
    }
    this.renderAll();
  }

  private insertChild(parentId: number, index: number, child: ViewNode): void {
    const parent = this.findNode(parentId);
    if (parent) parent.children.splice(index, 0, child);
    this.renderAll();
  }

  private removeChild(parentId: number, childId: number): void {
    const parent = this.findNode(parentId);
    if (parent) {
      const idx = parent.children.findIndex(c => c.id === childId);
      if (idx !== -1) parent.children.splice(idx, 1);
    }
    if (this.activeBlockId === childId) this.activeBlockId = null;
    this.renderAll();
  }

  private updateNode(nodeId: number, label: string, cssClass: string, text: string | null): void {
    const node = this.findNode(nodeId);
    if (node) {
      node.label = label;
      node.css_class = cssClass;
      node.text = text;
    }
    // Skip DOM re-render during IME composition to avoid caret disruption
    if (!this.composing) this.renderAll();
  }

  private findParent(childId: number, node: ViewNode): ViewNode | null {
    for (const c of node.children) {
      if (c.id === childId) return node;
      const found = this.findParent(childId, c);
      if (found) return found;
    }
    return null;
  }

  // --- Textarea overlay (Excalidraw pattern) -------------------------------

  private activateBlock(blockId: number): void {
    // Detach blur handler before renderAll — otherwise innerHTML='' removes
    // the textarea from DOM, triggers blur → deactivate(), resetting state
    // before positionTextarea() can reattach it.
    if (this.textarea) this.textarea.onblur = null;
    this.activeBlockId = blockId;
    this.blurBound = false;
    this.renderAll();
    this.ensureTextarea();
    this.positionTextarea();
    this.emit({ type: 'SelectNode', node_id: blockId });
  }

  private ensureTextarea(): void {
    if (this.textarea) return;
    const ta = document.createElement('textarea');
    ta.className = 'block-textarea';
    ta.addEventListener('pointerdown', (e) => e.stopPropagation());
    ta.addEventListener('input', () => this.onInput());
    ta.addEventListener('keydown', (e) => this.onKeydown(e));
    ta.addEventListener('compositionstart', () => { this.composing = true; });
    ta.addEventListener('compositionend', () => {
      this.composing = false;
      this.onInput();
    });
    this.textarea = ta;
  }

  private positionTextarea(): void {
    const ta = this.textarea;
    if (!ta || this.activeBlockId === null) return;

    const node = this.findNode(this.activeBlockId);
    const div = this.container.querySelector<HTMLElement>(
      `[data-node-id="${this.activeBlockId}"]`,
    );
    if (!node || !div) return;

    div.appendChild(ta);
    // Strip ZWSP placeholder (inserted by InsertBlockAfter for empty blocks)
    ta.value = (node.text ?? '').replace(/\u200B/g, '');

    // Match font from the block div
    const style = getComputedStyle(div);
    ta.style.font = style.font;
    ta.style.padding = style.padding;
    ta.style.lineHeight = style.lineHeight;
    // 1.05x height buffer (Excalidraw technique)
    ta.style.height = div.offsetHeight * 1.05 + 'px';

    ta.focus();

    // Deferred blur: bind onblur only after pointerup, skip if target is toolbar
    if (!this.blurBound) {
      const handler = (e: PointerEvent) => {
        // Don't bind blur if click was on toolbar/menu — keeps textarea active
        if ((e.target as Element)?.closest?.('[data-no-blur]')) return;
        if (ta) ta.onblur = () => this.deactivate();
        this.blurBound = true;
      };
      document.addEventListener('pointerup', handler as EventListener, { once: true });
    }
  }

  private deactivate(): void {
    if (this.activeBlockId === null) return;
    this.activeBlockId = null;
    this.blurBound = false;
    const ta = this.textarea;
    if (ta) {
      ta.onblur = null;
      ta.remove();
    }
    this.renderAll();
  }

  // --- Input handling ------------------------------------------------------

  private onInput(): void {
    const ta = this.textarea;
    if (!ta || this.composing || this.activeBlockId === null) return;

    // Save caret
    const selStart = ta.selectionStart;
    const selEnd = ta.selectionEnd;

    this.emit({
      type: 'CommitEdit',
      node_id: this.activeBlockId,
      value: ta.value.replace(/\u200B/g, ''),
    });

    // Re-sync text span under the textarea
    const div = this.container.querySelector<HTMLElement>(
      `[data-node-id="${this.activeBlockId}"]`,
    );
    if (div) {
      const textSpan = div.querySelector('.block-text');
      if (textSpan) textSpan.textContent = ta.value;
      ta.style.height = div.offsetHeight * 1.05 + 'px';
    }

    // Restore caret
    ta.selectionStart = selStart;
    ta.selectionEnd = selEnd;
  }

  private onKeydown(e: KeyboardEvent): void {
    if (e.isComposing || e.keyCode === 229) return;
    const ta = this.textarea;
    if (!ta || this.activeBlockId === null) return;

    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault();
      const pos = ta.selectionStart;
      const atEnd = pos === ta.value.length;
      if (atEnd) {
        this.emit({
          type: 'StructuralEdit',
          node_id: this.activeBlockId,
          op: 'insert_block_after',
          params: {},
        });
      } else {
        this.emit({
          type: 'StructuralEdit',
          node_id: this.activeBlockId,
          op: 'split_block',
          params: { offset: String(pos) },
        });
      }
      return;
    }

    if (e.key === 'Backspace' && ta.selectionStart === 0 && ta.selectionEnd === 0) {
      e.preventDefault();
      this.emit({
        type: 'StructuralEdit',
        node_id: this.activeBlockId,
        op: 'merge_with_previous',
        params: {},
      });
      return;
    }

    if (e.key === 'ArrowUp' && ta.selectionStart === 0) {
      e.preventDefault();
      this.moveFocus(-1);
      return;
    }

    if (e.key === 'ArrowDown' && ta.selectionStart === ta.value.length) {
      e.preventDefault();
      this.moveFocus(1);
      return;
    }
  }

  // --- Block navigation ----------------------------------------------------

  private moveFocus(direction: -1 | 1): void {
    if (this.activeBlockId === null || !this.currentTree) return;
    const siblings = this.collectEditableBlocks(this.currentTree);
    const idx = siblings.findIndex(c => c.id === this.activeBlockId);
    const next = siblings[idx + direction];
    if (next) this.activateBlock(next.id);
  }

  // --- Helpers -------------------------------------------------------------

  private emit(intent: UserIntent): void {
    if (this.intentCb) this.intentCb(intent);
  }

  private onContainerClick(e: MouseEvent): void {
    const target = e.target as HTMLElement;
    if (!target.closest('.block')) {
      this.deactivate();
    }
  }
}
