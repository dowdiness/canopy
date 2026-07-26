import type { LocalPost } from '../core/posts';
import type { RankingReason, RelatedPost } from '../core/post-retrieval';

export type RelatedPanelMode = 'writing' | 'ask';
type StatusTone = 'idle' | 'success' | 'error';

interface RelatedPanelCopy {
  readonly kicker: string;
  readonly title: string;
  readonly formatCount: (count: number) => string;
  readonly openButtonText: string;
  readonly openLabelPrefix: string;
}

interface PostsViewHandlers {
  readonly submitDraft: () => void;
  readonly askDraft: () => void;
  readonly updateDraft: () => void;
}

export interface PostsView {
  draftText(): string;
  setDraftText(text: string): void;
  clearDraft(): void;
  focusDraft(): void;
  restoreFocus(token: string): boolean;
  syncSubmitState(): void;
  setStatus(message: string, tone?: StatusTone): void;
  renderTimeline(posts: readonly LocalPost[], highlightedPostId: string | null): void;
  renderRelated(
    relatedPosts: readonly RelatedPost[],
    mode: RelatedPanelMode,
    openRelatedPost: (result: RelatedPost) => void,
  ): number;
  focusTimelinePost(postId: string): void;
  bind(handlers: PostsViewHandlers): () => void;
}

const RELATED_PANEL_COPY: Record<RelatedPanelMode, RelatedPanelCopy> = {
  writing: {
    kicker: 'Returning while writing',
    title: 'Related posts',
    formatCount: pluralizeRelated,
    openButtonText: 'Open',
    openLabelPrefix: 'Open related post',
  },
  ask: {
    kicker: 'Asked from your posts',
    title: 'Source posts',
    formatCount: pluralizeSources,
    openButtonText: 'Open source',
    openLabelPrefix: 'Open source post',
  },
};

export function createPostsView(root: Document | HTMLElement, window: Window): PostsView {
  const document = root instanceof Document ? root : root.ownerDocument;
  const form = root.querySelector<HTMLFormElement>('#post-form')!;
  const draft = root.querySelector<HTMLTextAreaElement>('#post-input')!;
  const askButton = root.querySelector<HTMLButtonElement>('#post-ask')!;
  const submitButton = root.querySelector<HTMLButtonElement>('#post-submit')!;
  const statusEl = root.querySelector<HTMLParagraphElement>('#post-status')!;
  const countEl = root.querySelector<HTMLSpanElement>('#post-count')!;
  const listEl = root.querySelector<HTMLUListElement>('#post-list')!;
  const emptyEl = root.querySelector<HTMLDivElement>('#empty-state')!;
  const relatedPanelEl = root.querySelector<HTMLElement>('#related-panel')!;
  const relatedKickerEl = root.querySelector<HTMLParagraphElement>('#related-kicker')!;
  const relatedTitleEl = root.querySelector<HTMLHeadingElement>('#related-title')!;
  const relatedCountEl = root.querySelector<HTMLSpanElement>('#related-count')!;
  const relatedEmptyEl = root.querySelector<HTMLParagraphElement>('#related-empty')!;
  const relatedListEl = root.querySelector<HTMLUListElement>('#related-list')!;
  const dateTimeFormat = new Intl.DateTimeFormat(undefined, {
    month: 'short',
    day: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  });
  let focusFrame: number | null = null;
  let renderedRelatedPosts: readonly RelatedPost[] = [];
  let openRenderedRelatedPost: ((result: RelatedPost) => void) | null = null;

  function formatTimestamp(value: string): string {
    return dateTimeFormat.format(new Date(value));
  }

  function renderPost(post: LocalPost, highlightedPostId: string | null): HTMLLIElement {
    const item = document.createElement('li');
    item.className = 'post-item';
    item.dataset.postId = post.id;
    item.tabIndex = -1;
    item.dataset.highlighted = post.id === highlightedPostId ? 'true' : 'false';
    item.dataset.routeFocus = `timeline:${post.id}`;

    const article = document.createElement('article');
    const time = document.createElement('time');
    time.dateTime = post.createdAt;
    time.textContent = formatTimestamp(post.createdAt);

    const text = document.createElement('p');
    text.textContent = post.text;
    article.append(time, text);
    item.append(article);
    return item;
  }

  function renderRankingReason(reason: RankingReason): HTMLSpanElement {
    const item = document.createElement('span');
    item.className = 'related-reason';
    item.dataset.kind = reason.kind;
    item.textContent = reason.label;
    return item;
  }

  function renderRelatedPost(
    result: RelatedPost,
    mode: RelatedPanelMode,
  ): HTMLLIElement {
    const copy = RELATED_PANEL_COPY[mode];
    const item = document.createElement('li');
    item.className = 'related-item';
    const article = document.createElement('article');
    const meta = document.createElement('div');
    meta.className = 'related-meta';

    const time = document.createElement('time');
    time.dateTime = result.post.createdAt;
    time.textContent = formatTimestamp(result.post.createdAt);
    const reasons = document.createElement('div');
    reasons.className = 'related-reasons';
    reasons.append(...result.reasons.map(renderRankingReason));
    const text = document.createElement('p');
    text.className = 'related-text';
    text.textContent = result.post.text;
    const openButton = document.createElement('button');
    openButton.type = 'button';
    openButton.className = 'related-open';
    openButton.dataset.postId = result.post.id;
    openButton.textContent = copy.openButtonText;
    openButton.setAttribute('aria-label', `${copy.openLabelPrefix}: ${result.post.text.slice(0, 80)}`);

    meta.append(time, reasons);
    article.append(meta, text, openButton);
    item.append(article);
    return item;
  }

  return {
    draftText: () => draft.value,
    setDraftText: (text) => { draft.value = text; },
    clearDraft: () => { draft.value = ''; },
    focusDraft: () => draft.focus(),
    restoreFocus(token): boolean {
      const target = token === 'draft'
        ? draft
        : Array.from(listEl.querySelectorAll<HTMLLIElement>('.post-item')).find(
          candidate => candidate.dataset.routeFocus === token,
        );
      if (target === undefined) return false;
      target.focus({ preventScroll: true });
      return document.activeElement === target;
    },
    syncSubmitState(): void {
      const isEmpty = draft.value.trim().length === 0;
      askButton.disabled = isEmpty;
      submitButton.disabled = isEmpty;
    },
    setStatus(message: string, tone: StatusTone = 'idle'): void {
      statusEl.textContent = message;
      statusEl.dataset.tone = tone;
    },
    renderTimeline(posts, highlightedPostId): void {
      countEl.textContent = pluralizePosts(posts.length);
      listEl.replaceChildren(...posts.map(post => renderPost(post, highlightedPostId)));
      listEl.hidden = posts.length === 0;
      emptyEl.hidden = posts.length !== 0;
    },
    renderRelated(relatedPosts, mode, openRelatedPost): number {
      renderedRelatedPosts = relatedPosts;
      openRenderedRelatedPost = openRelatedPost;
      const copy = RELATED_PANEL_COPY[mode];
      const isAskMode = mode === 'ask';
      const hasResults = relatedPosts.length > 0;
      relatedKickerEl.textContent = copy.kicker;
      relatedTitleEl.textContent = copy.title;
      relatedCountEl.textContent = copy.formatCount(relatedPosts.length);
      relatedListEl.replaceChildren(
        ...relatedPosts.map(result => renderRelatedPost(result, mode)),
      );
      relatedEmptyEl.hidden = !(isAskMode && !hasResults);
      relatedPanelEl.hidden = !isAskMode && !hasResults;
      return relatedPosts.length;
    },
    focusTimelinePost(postId): void {
      if (focusFrame !== null) window.cancelAnimationFrame(focusFrame);
      focusFrame = window.requestAnimationFrame(() => {
        focusFrame = null;
        const item = Array.from(listEl.querySelectorAll<HTMLLIElement>('.post-item')).find(
          candidate => candidate.dataset.postId === postId,
        );
        item?.focus({ preventScroll: true });
        item?.scrollIntoView({ block: 'center', behavior: 'smooth' });
      });
    },
    bind({ submitDraft, askDraft, updateDraft }): () => void {
      const handleSubmit = (event: SubmitEvent) => {
        event.preventDefault();
        submitDraft();
      };
      const handleDraftKeydown = (event: KeyboardEvent) => {
        if (event.key === 'Enter' && (event.ctrlKey || event.metaKey)) {
          event.preventDefault();
          submitDraft();
        }
      };
      const handleAsk = () => askDraft();
      const handleDraftInput = () => updateDraft();
      const handleRelatedOpen = (event: MouseEvent) => {
        const target = event.target;
        if (!(target instanceof Element)) return;
        const button = target.closest<HTMLButtonElement>('.related-open');
        const postId = button?.dataset.postId;
        if (postId === undefined) return;
        const result = renderedRelatedPosts.find(candidate => candidate.post.id === postId);
        if (result !== undefined) openRenderedRelatedPost?.(result);
      };

      form.addEventListener('submit', handleSubmit);
      draft.addEventListener('keydown', handleDraftKeydown);
      askButton.addEventListener('click', handleAsk);
      draft.addEventListener('input', handleDraftInput);
      relatedListEl.addEventListener('click', handleRelatedOpen);
      form.inert = false;
      form.dataset.postsReady = 'true';

      let disposed = false;
      return () => {
        if (disposed) return;
        disposed = true;
        form.inert = true;
        form.dataset.postsReady = 'false';
        if (focusFrame !== null) {
          window.cancelAnimationFrame(focusFrame);
          focusFrame = null;
        }
        form.removeEventListener('submit', handleSubmit);
        draft.removeEventListener('keydown', handleDraftKeydown);
        askButton.removeEventListener('click', handleAsk);
        draft.removeEventListener('input', handleDraftInput);
        relatedListEl.removeEventListener('click', handleRelatedOpen);
        renderedRelatedPosts = [];
        openRenderedRelatedPost = null;
      };
    },
  };
}

function pluralizePosts(count: number): string {
  return count === 1 ? '1 post' : `${count} posts`;
}

function pluralizeRelated(count: number): string {
  return count === 1 ? '1 related post' : `${count} related posts`;
}

function pluralizeSources(count: number): string {
  return count === 1 ? '1 source post' : `${count} source posts`;
}
