import { LocalPostEventStore } from './post-events';
import { PostRetrievalIndex, type RelatedPost, type RankingReason } from './post-retrieval';
import { type LocalPost, LocalPostStore } from './post-store';

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

const store = new LocalPostStore(window.localStorage);
const eventStore = new LocalPostEventStore(window.localStorage);
const dateTimeFormat = new Intl.DateTimeFormat(undefined, {
  month: 'short',
  day: 'numeric',
  hour: '2-digit',
  minute: '2-digit',
});

type RelatedPanelMode = 'writing' | 'ask';

interface RelatedPanelCopy {
  readonly kicker: string;
  readonly title: string;
  readonly formatCount: (count: number) => string;
  readonly openButtonText: string;
  readonly openLabelPrefix: string;
  readonly openedLabel: string;
}

const RELATED_PANEL_COPY: Record<RelatedPanelMode, RelatedPanelCopy> = {
  writing: {
    kicker: 'Returning while writing',
    title: 'Related posts',
    formatCount: pluralizeRelated,
    openButtonText: 'Open',
    openLabelPrefix: 'Open related post',
    openedLabel: 'related post',
  },
  ask: {
    kicker: 'Asked from your posts',
    title: 'Source posts',
    formatCount: pluralizeSources,
    openButtonText: 'Open source',
    openLabelPrefix: 'Open source post',
    openedLabel: 'source post',
  },
};

let posts: LocalPost[] = [];
let highlightedPostId: string | null = null;
let relatedMode: RelatedPanelMode = 'writing';
let retrievalIndex = new PostRetrievalIndex(posts, eventStore.engagementByPost());

function pluralizePosts(count: number): string {
  return count === 1 ? '1 post' : `${count} posts`;
}

function pluralizeRelated(count: number): string {
  return count === 1 ? '1 related post' : `${count} related posts`;
}

function pluralizeSources(count: number): string {
  return count === 1 ? '1 source post' : `${count} source posts`;
}

function setStatus(message: string, tone: 'idle' | 'success' | 'error' = 'idle'): void {
  statusEl.textContent = message;
  statusEl.dataset.tone = tone;
}

function formatTimestamp(value: string): string {
  return dateTimeFormat.format(new Date(value));
}

function syncSubmitState(): void {
  const isEmpty = draft.value.trim().length === 0;
  askButton.disabled = isEmpty;
  submitButton.disabled = isEmpty;
}

function renderPost(post: LocalPost): HTMLLIElement {
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

function renderRelatedPost(result: RelatedPost, mode: RelatedPanelMode): HTMLLIElement {
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
  openButton.setAttribute(
    'aria-label',
    `${copy.openLabelPrefix}: ${result.post.text.slice(0, 80)}`,
  );
  openButton.addEventListener('click', () => openRelatedPost(result));

  meta.append(time, reasons);
  article.append(meta, text, openButton);
  item.append(article);
  return item;
}

function renderRelated(): number {
  const relatedPosts = retrievalIndex.query(draft.value, { limit: 5 });
  const copy = RELATED_PANEL_COPY[relatedMode];
  const isAskMode = relatedMode === 'ask';
  const hasResults = relatedPosts.length > 0;

  relatedKickerEl.textContent = copy.kicker;
  relatedTitleEl.textContent = copy.title;
  relatedCountEl.textContent = copy.formatCount(relatedPosts.length);
  relatedListEl.replaceChildren(
    ...relatedPosts.map(result => renderRelatedPost(result, relatedMode)),
  );
  relatedEmptyEl.hidden = !(isAskMode && !hasResults);
  relatedPanelEl.hidden = !isAskMode && !hasResults;

  return relatedPosts.length;
}

function replacePosts(nextPosts: LocalPost[]): void {
  posts = nextPosts;
  retrievalIndex = new PostRetrievalIndex(posts, eventStore.engagementByPost());
}

function focusTimelinePost(postId: string): void {
  window.requestAnimationFrame(() => {
    const item = Array.from(listEl.querySelectorAll<HTMLLIElement>('.post-item')).find(
      candidate => candidate.dataset.postId === postId,
    );
    item?.focus({ preventScroll: true });
    item?.scrollIntoView({ block: 'center', behavior: 'smooth' });
  });
}

function openRelatedPost(result: RelatedPost): void {
  let recorded = true;
  try {
    eventStore.recordRelatedOpened(result.post.id);
  } catch {
    recorded = false;
  }

  highlightedPostId = result.post.id;
  replacePosts(posts);
  render();
  focusTimelinePost(result.post.id);
  const openedLabel = RELATED_PANEL_COPY[relatedMode].openedLabel;
  setStatus(
    recorded
      ? `Opened a ${openedLabel}. Revisited posts get a small ranking boost.`
      : `Opened a ${openedLabel}, but could not save its revisit signal.`,
    recorded ? 'success' : 'error',
  );
}

function render(): void {
  countEl.textContent = pluralizePosts(posts.length);
  listEl.replaceChildren(...posts.map(renderPost));
  listEl.hidden = posts.length === 0;
  emptyEl.hidden = posts.length !== 0;
  renderRelated();
}

function loadPosts(): void {
  try {
    replacePosts(store.all());
    render();
    setStatus(`${pluralizePosts(posts.length)} stored locally on this device.`);
  } catch (error) {
    replacePosts([]);
    render();
    setStatus(
      `Could not read saved posts: ${error instanceof Error ? error.message : String(error)}`,
      'error',
    );
  }
}

function submitDraft(): void {
  const text = draft.value.trim();
  if (text.length === 0) {
    setStatus('Write something before posting.', 'error');
    draft.focus();
    return;
  }

  try {
    const post = store.add(text);
    try {
      eventStore.recordPostCreated(post.id);
    } catch {
      // Event tracking is best-effort; the post itself is the durable user data.
    }
    highlightedPostId = null;
    relatedMode = 'writing';
    replacePosts([post, ...posts]);
    draft.value = '';
    syncSubmitState();
    render();
    setStatus('Posted. It will still be here after reload.', 'success');
    draft.focus();
  } catch (error) {
    setStatus(
      `Could not save this post: ${error instanceof Error ? error.message : String(error)}`,
      'error',
    );
  }
}

function askDraft(): void {
  const queryText = draft.value.trim();
  if (queryText.length === 0) {
    setStatus('Write a question before asking.', 'error');
    draft.focus();
    return;
  }

  relatedMode = 'ask';
  const sourceCount = renderRelated();
  setStatus(
    sourceCount === 0
      ? 'No source posts matched that question. Nothing was posted.'
      : `Found ${pluralizeSources(sourceCount)}. Nothing was posted.`,
    sourceCount === 0 ? 'idle' : 'success',
  );
  draft.focus();
}

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

draft.addEventListener('input', () => {
  relatedMode = 'writing';
  syncSubmitState();
  renderRelated();
});

loadPosts();
syncSubmitState();
draft.focus();
