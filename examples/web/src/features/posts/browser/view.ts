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
  clearDraft(): void;
  focusDraft(): void;
  syncSubmitState(): void;
  setStatus(message: string, tone?: StatusTone): void;
  renderTimeline(posts: readonly LocalPost[], highlightedPostId: string | null): void;
  renderRelated(
    relatedPosts: readonly RelatedPost[],
    mode: RelatedPanelMode,
    openRelatedPost: (result: RelatedPost) => void,
  ): number;
  focusTimelinePost(postId: string): void;
  bind(handlers: PostsViewHandlers): void;
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

export function createPostsView(document: Document, window: Window): PostsView {
  const form = document.getElementById('post-form') as HTMLFormElement;
  const draft = document.getElementById('post-input') as HTMLTextAreaElement;
  const askButton = document.getElementById('post-ask') as HTMLButtonElement;
  const submitButton = document.getElementById('post-submit') as HTMLButtonElement;
  const statusEl = document.getElementById('post-status') as HTMLParagraphElement;
  const countEl = document.getElementById('post-count') as HTMLSpanElement;
  const listEl = document.getElementById('post-list') as HTMLUListElement;
  const emptyEl = document.getElementById('empty-state') as HTMLDivElement;
  const relatedPanelEl = document.getElementById('related-panel') as HTMLElement;
  const relatedKickerEl = document.getElementById('related-kicker') as HTMLParagraphElement;
  const relatedTitleEl = document.getElementById('related-title') as HTMLHeadingElement;
  const relatedCountEl = document.getElementById('related-count') as HTMLSpanElement;
  const relatedEmptyEl = document.getElementById('related-empty') as HTMLParagraphElement;
  const relatedListEl = document.getElementById('related-list') as HTMLUListElement;
  const dateTimeFormat = new Intl.DateTimeFormat(undefined, {
    month: 'short',
    day: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  });

  function formatTimestamp(value: string): string {
    return dateTimeFormat.format(new Date(value));
  }

  function renderPost(post: LocalPost, highlightedPostId: string | null): HTMLLIElement {
    const item = document.createElement('li');
    item.className = 'post-item';
    item.dataset.postId = post.id;
    item.tabIndex = -1;
    item.dataset.highlighted = post.id === highlightedPostId ? 'true' : 'false';

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
    openRelatedPost: (result: RelatedPost) => void,
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
    openButton.textContent = copy.openButtonText;
    openButton.setAttribute('aria-label', `${copy.openLabelPrefix}: ${result.post.text.slice(0, 80)}`);
    openButton.addEventListener('click', () => openRelatedPost(result));

    meta.append(time, reasons);
    article.append(meta, text, openButton);
    item.append(article);
    return item;
  }

  return {
    draftText: () => draft.value,
    clearDraft: () => { draft.value = ''; },
    focusDraft: () => draft.focus(),
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
      const copy = RELATED_PANEL_COPY[mode];
      const isAskMode = mode === 'ask';
      const hasResults = relatedPosts.length > 0;
      relatedKickerEl.textContent = copy.kicker;
      relatedTitleEl.textContent = copy.title;
      relatedCountEl.textContent = copy.formatCount(relatedPosts.length);
      relatedListEl.replaceChildren(
        ...relatedPosts.map(result => renderRelatedPost(result, mode, openRelatedPost)),
      );
      relatedEmptyEl.hidden = !(isAskMode && !hasResults);
      relatedPanelEl.hidden = !isAskMode && !hasResults;
      return relatedPosts.length;
    },
    focusTimelinePost(postId): void {
      window.requestAnimationFrame(() => {
        const item = Array.from(listEl.querySelectorAll<HTMLLIElement>('.post-item')).find(
          candidate => candidate.dataset.postId === postId,
        );
        item?.focus({ preventScroll: true });
        item?.scrollIntoView({ block: 'center', behavior: 'smooth' });
      });
    },
    bind({ submitDraft, askDraft, updateDraft }): void {
      form.addEventListener('submit', event => {
        event.preventDefault();
        submitDraft();
      });
      draft.addEventListener('keydown', event => {
        if (event.key === 'Enter' && (event.ctrlKey || event.metaKey)) {
          event.preventDefault();
          submitDraft();
        }
      });
      askButton.addEventListener('click', askDraft);
      draft.addEventListener('input', updateDraft);
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
