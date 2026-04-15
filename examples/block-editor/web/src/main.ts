import * as ed from '@moonbit/canopy-block-editor';

// ── Types ──────────────────────────────────────────────────────────────
interface Block {
  id: string;
  block_type: string;
  level: string;
  list_style: string;
  checked: boolean;
  index: number;
  parent_id: string;
  text: string;
}

interface RenderState {
  block_count: number;
  blocks: Block[];
}

type DropPosition = 'Before' | 'After' | 'Inside';

// ── State ──────────────────────────────────────────────────────────────
const handle = ed.create_editor('local');
const container = document.getElementById('editor-blocks')!;
const blockDivs = new Map<string, HTMLDivElement>();
let suppressNextInput = false;

// Drag state — tracked outside DOM to avoid stale closures
let dragSourceId: string | null = null;
let currentDropTarget: HTMLDivElement | null = null;
let currentDropPosition: DropPosition | null = null;

// Seed
ed.editor_import_markdown(handle, '# Welcome\n\nStart typing here.\n');

// ── Render ─────────────────────────────────────────────────────────────
function render() {
  const state: RenderState = JSON.parse(ed.get_render_state(handle));
  const liveIds = new Set<string>();

  for (const block of state.blocks) {
    liveIds.add(block.id);
    let div = blockDivs.get(block.id);

    if (!div) {
      div = document.createElement('div');
      div.classList.add('block');
      div.contentEditable = 'true';
      div.dataset.blockId = block.id;

      // Drag handle — a non-editable grip that makes the block draggable
      const grip = document.createElement('span');
      grip.className = 'drag-handle';
      grip.contentEditable = 'false';
      grip.draggable = true;
      grip.textContent = '\u2847'; // braille dots for grip icon
      grip.addEventListener('dragstart', (e) => {
        dragSourceId = block.id;
        e.dataTransfer!.effectAllowed = 'move';
        e.dataTransfer!.setData('text/plain', block.id);
        div!.classList.add('dragging');
      });
      grip.addEventListener('dragend', () => {
        div!.classList.remove('dragging');
        clearDropIndicators();
        dragSourceId = null;
      });
      div.prepend(grip);

      wireDragTarget(div);
      wireEvents(div);
      container.appendChild(div);
      blockDivs.set(block.id, div);
    }

    // Data attributes drive CSS styling and structural context for drop targeting
    div.dataset.type = block.block_type;
    div.dataset.level = block.level;
    div.dataset.listStyle = block.list_style;
    div.dataset.checked = String(block.checked);
    div.dataset.index = String(block.index);
    div.dataset.parentId = block.parent_id;
    div.contentEditable = block.block_type === 'divider' ? 'false' : 'true';
    applyAriaRoles(div, block);

    // Only update text if not focused (avoid clobbering cursor)
    if (document.activeElement !== div && div.textContent !== block.text) {
      div.textContent = block.text;
    }
  }

  // Remove stale divs
  for (const [id, div] of blockDivs) {
    if (!liveIds.has(id)) {
      div.remove();
      blockDivs.delete(id);
    }
  }

  // Reorder divs to match state order
  let prev: Element | null = null;
  for (const block of state.blocks) {
    const div = blockDivs.get(block.id);
    if (!div) continue;
    const expected: Element | null = prev ? prev.nextElementSibling : container.firstElementChild;
    if (div !== expected) {
      if (prev) {
        prev.after(div);
      } else {
        container.prepend(div);
      }
    }
    prev = div;
  }
}

// ── ARIA roles ─────────────────────────────────────────────────────────
function applyAriaRoles(div: HTMLDivElement, block: Block) {
  // Clear previous roles
  div.removeAttribute('role');
  div.removeAttribute('aria-level');

  switch (block.block_type) {
    case 'heading':
      div.setAttribute('role', 'heading');
      div.setAttribute('aria-level', block.level || '1');
      break;
    case 'list_item':
      // No role — role="listitem" requires a parent role="list" wrapper,
      // which conflicts with flat contenteditable block layout.
      break;
    case 'quote':
      div.setAttribute('role', 'blockquote');
      break;
    case 'divider':
      div.setAttribute('role', 'separator');
      break;
  }
}

// ── Drag targeting ──────────────────────────────────────────────────���─
function computeDropPosition(e: DragEvent, div: HTMLDivElement): DropPosition {
  const rect = div.getBoundingClientRect();
  const y = e.clientY - rect.top;
  const ratio = y / rect.height;
  if (ratio < 0.5) return 'Before';
  return 'After';
}

function clearDropIndicators() {
  if (currentDropTarget) {
    currentDropTarget.classList.remove('drop-before', 'drop-after');
    currentDropTarget = null;
  }
  currentDropPosition = null;
}

function wireDragTarget(div: HTMLDivElement) {
  div.addEventListener('dragover', (e) => {
    e.preventDefault();
    const id = div.dataset.blockId!;
    if (id === dragSourceId) return;

    e.dataTransfer!.dropEffect = 'move';
    const position = computeDropPosition(e, div);

    if (currentDropTarget !== div || currentDropPosition !== position) {
      clearDropIndicators();
      currentDropTarget = div;
      currentDropPosition = position;
      div.classList.add(position === 'Before' ? 'drop-before' : 'drop-after');
    }
  });

  div.addEventListener('dragleave', (e) => {
    // Only clear if leaving the block entirely (not entering a child)
    if (!div.contains(e.relatedTarget as Node)) {
      if (currentDropTarget === div) clearDropIndicators();
    }
  });

  div.addEventListener('drop', (e) => {
    e.preventDefault();
    const targetId = div.dataset.blockId!;
    if (dragSourceId && dragSourceId !== targetId && currentDropPosition) {
      ed.editor_move_block(handle, dragSourceId, targetId, currentDropPosition);
      render();
    }
    clearDropIndicators();
    dragSourceId = null;
  });
}

// ── Events ─────────────────────────────────────────────────────────────
function wireEvents(div: HTMLDivElement) {
  div.addEventListener('paste', (e: ClipboardEvent) => {
    e.preventDefault();
    const text = e.clipboardData?.getData('text/plain') || '';
    document.execCommand('insertText', false, text);
  });

  div.addEventListener('input', () => {
    if (suppressNextInput) {
      suppressNextInput = false;
      return;
    }
    const id = div.dataset.blockId!;
    ed.editor_set_block_text(handle, id, div.textContent || '');
  });

  div.addEventListener('keydown', (e: KeyboardEvent) => {
    const id = div.dataset.blockId!;

    // Enter → insert block after
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault();
      const newId = ed.editor_insert_block_after(handle, id, 'paragraph');
      render();
      const newDiv = blockDivs.get(newId);
      if (newDiv) newDiv.focus();
      return;
    }

    // Backspace on empty → delete block, focus neighbor (keep at least one block)
    if (e.key === 'Backspace' && (div.textContent || '') === '') {
      const prev = div.previousElementSibling as HTMLDivElement | null;
      const next = div.nextElementSibling as HTMLDivElement | null;
      if (!prev && !next) return; // Don't delete the only block
      e.preventDefault();
      ed.editor_delete_block(handle, id);
      render();
      const target = prev || next;
      if (target) {
        target.focus();
        const sel = window.getSelection();
        if (sel && target.childNodes.length > 0) {
          sel.selectAllChildren(target);
          sel.collapseToEnd();
        }
      }
      return;
    }

    // Space → check autoformat
    if (e.key === ' ') {
      const text = div.textContent || '';
      const fmt = detectAutoformat(text);
      if (fmt) {
        e.preventDefault();
        ed.editor_set_block_type(handle, id, fmt.type, fmt.level, fmt.listStyle);
        ed.editor_set_block_text(handle, id, '');
        suppressNextInput = true;
        div.textContent = '';
        render();
        const updated = blockDivs.get(id);
        if (updated) updated.focus();
        dismissShortcutHints();
      }
    }
  });
}

// ── Autoformat ─────────────────────────────────────────────────────────
function detectAutoformat(
  text: string,
): { type: string; level: number; listStyle: string } | null {
  const headingMatch = text.match(/^(#{1,6})$/);
  if (headingMatch)
    return { type: 'heading', level: headingMatch[1].length, listStyle: '' };

  if (text === '- [ ]' || text === '- [x]')
    return { type: 'list_item', level: 0, listStyle: 'todo' };

  if (text === '-' || text === '*')
    return { type: 'list_item', level: 0, listStyle: 'bullet' };

  if (/^\d+\.$/.test(text))
    return { type: 'list_item', level: 0, listStyle: 'numbered' };

  if (text === '>')
    return { type: 'quote', level: 0, listStyle: '' };

  return null;
}

// ── Shortcut hints (dismiss after first autoformat) ───────────────────
function dismissShortcutHints() {
  const hints = document.getElementById('shortcut-hints');
  if (hints && !hints.classList.contains('hidden')) {
    hints.classList.add('hidden');
  }
}

// ── Toolbar ────────────────────────────────────────────────────────────
document.getElementById('btn-download')!.addEventListener('click', () => {
  const md = ed.editor_export_markdown(handle);
  const blob = new Blob([md], { type: 'text/markdown' });
  const a = document.createElement('a');
  a.href = URL.createObjectURL(blob);
  a.download = 'document.md';
  a.click();
  URL.revokeObjectURL(a.href);
});

document.getElementById('btn-upload')!.addEventListener('click', () => {
  document.getElementById('file-input')!.click();
});

document.getElementById('file-input')!.addEventListener('change', (e) => {
  const input = e.target as HTMLInputElement;
  const file = input.files?.[0];
  if (!file) return;
  const reader = new FileReader();
  reader.onload = () => {
    ed.editor_import_markdown(handle, reader.result as string);
    blockDivs.clear();
    container.innerHTML = '';
    render();
  };
  reader.readAsText(file);
  input.value = ''; // Reset so re-uploading same file triggers change
});

// ── Boot ───────────────────────────────────────────────────────────────
render();
