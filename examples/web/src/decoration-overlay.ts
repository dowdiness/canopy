import type { Decoration } from '@canopy/editor-adapter/types';

export type WidgetClickHandler = (widgetId: string) => void;

export class DecorationOverlay {
  private readonly overlay: HTMLDivElement;
  private bgDecorations: Decoration[] = [];
  private widgetDecorations: Decoration[] = [];
  private resizeObserver: ResizeObserver;
  private frame: number | null = null;
  private readonly onWidgetClick?: WidgetClickHandler;

  constructor(
    private readonly editorEl: HTMLElement,
    onWidgetClick?: WidgetClickHandler,
  ) {
    this.onWidgetClick = onWidgetClick;
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
    this.bgDecorations = decorations.filter(
      deco => deco.to > deco.from && !deco.widget,
    );
    this.widgetDecorations = decorations.filter(
      deco => deco.widget && deco.data !== null,
    );
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

    // Render background marks (non-widget decorations)
    for (const decoration of this.bgDecorations) {
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

    // Render widget decorations (interactive elements at text positions)
    for (const decoration of this.widgetDecorations) {
      const range = this.rangeForOffsets(
        decoration.from,
        Math.min(decoration.from + 1, decoration.to),
      );
      if (!range) continue;
      const rects = Array.from(range.getClientRects());
      range.detach();
      if (rects.length === 0) continue;

      const rect = rects[0];
      const btn = document.createElement('button');
      btn.className = `widget-btn ${decoration.css_class}`;
      btn.setAttribute('data-widget-id', decoration.data!);
      btn.setAttribute('aria-label', decoration.css_class.replace('widget-', '') + ' in text editor');
      btn.type = 'button';
      btn.textContent = '+';
      Object.assign(btn.style, {
        position: 'absolute',
        left: `${rect.left - editorRect.left + this.editorEl.scrollLeft + rect.width + 2}px`,
        top: `${rect.top - editorRect.top + this.editorEl.scrollTop}px`,
      });
      if (this.onWidgetClick) {
        btn.addEventListener('click', (e) => {
          e.stopPropagation();
          this.onWidgetClick!(decoration.data!);
        });
      }
      this.overlay.appendChild(btn);
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

    for (
      let node = walker.nextNode() as Text | null;
      node;
      node = walker.nextNode() as Text | null
    ) {
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
