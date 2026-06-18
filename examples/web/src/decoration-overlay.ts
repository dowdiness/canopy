import type { Decoration } from '@canopy/editor-adapter/types';

export class DecorationOverlay {
  private readonly overlay: HTMLDivElement;
  private decorations: Decoration[] = [];
  private resizeObserver: ResizeObserver;
  private frame: number | null = null;

  constructor(private readonly editorEl: HTMLElement) {
    const host = editorEl.parentElement ?? editorEl;
    const hostStyle = window.getComputedStyle(host);
    if (hostStyle.position === 'static') {
      host.style.position = 'relative';
    }

    this.overlay = document.createElement('div');
    this.overlay.className = 'decoration-overlay';
    this.overlay.setAttribute('aria-hidden', 'true');
    host.appendChild(this.overlay);

    this.resizeObserver = new ResizeObserver(() => this.scheduleRender());
    this.resizeObserver.observe(editorEl);
    window.addEventListener('scroll', this.handleScroll, true);
  }

  applyDecorations(decorations: Decoration[]) {
    this.decorations = decorations.filter(deco => deco.to > deco.from && !deco.widget);
    this.scheduleRender();
  }

  dispose() {
    if (this.frame !== null) cancelAnimationFrame(this.frame);
    this.resizeObserver.disconnect();
    window.removeEventListener('scroll', this.handleScroll, true);
    this.overlay.remove();
  }

  private readonly handleScroll = () => this.scheduleRender();

  private scheduleRender() {
    if (this.frame !== null) return;
    this.frame = requestAnimationFrame(() => {
      this.frame = null;
      this.render();
    });
  }

  private render() {
    this.overlay.replaceChildren();
    const host = this.overlay.parentElement;
    if (!host) return;

    const hostRect = host.getBoundingClientRect();
    const editorRect = this.editorEl.getBoundingClientRect();
    Object.assign(this.overlay.style, {
      left: `${editorRect.left - hostRect.left + host.scrollLeft}px`,
      top: `${editorRect.top - hostRect.top + host.scrollTop}px`,
      width: `${editorRect.width}px`,
      height: `${editorRect.height}px`,
    });

    for (const decoration of this.decorations) {
      const range = this.rangeForOffsets(decoration.from, decoration.to);
      if (!range) continue;
      const rects = Array.from(range.getClientRects());
      range.detach();

      for (const rect of rects) {
        if (rect.width <= 0 || rect.height <= 0) continue;
        const mark = document.createElement('div');
        mark.className = `decoration-mark ${decoration.css_class}`;
        mark.dataset.patternId = decoration.data ?? '';
        Object.assign(mark.style, {
          left: `${rect.left - editorRect.left + this.editorEl.scrollLeft}px`,
          top: `${rect.top - editorRect.top + this.editorEl.scrollTop}px`,
          width: `${rect.width}px`,
          height: `${rect.height}px`,
        });
        this.overlay.appendChild(mark);
      }
    }
  }

  private rangeForOffsets(from: number, to: number): Range | null {
    const start = this.findTextPosition(from);
    const end = this.findTextPosition(to);
    if (!start || !end) return null;

    const range = document.createRange();
    range.setStart(start.node, start.offset);
    range.setEnd(end.node, end.offset);
    return range;
  }

  private findTextPosition(offset: number): { node: Text; offset: number } | null {
    const walker = document.createTreeWalker(this.editorEl, NodeFilter.SHOW_TEXT);
    let remaining = offset;
    let lastText: Text | null = null;

    for (let node = walker.nextNode() as Text | null; node; node = walker.nextNode() as Text | null) {
      lastText = node;
      const length = node.data.length;
      if (remaining <= length) {
        return { node, offset: remaining };
      }
      remaining -= length;
    }

    if (lastText && remaining === 0) {
      return { node: lastText, offset: lastText.data.length };
    }
    return null;
  }
}
