import { PostRetrievalIndex, type RelatedPost } from './post-retrieval';
import { type LocalPost, LocalPostStore } from './post-store';

const form = document.getElementById('post-form') as HTMLFormElement;
const draft = document.getElementById('post-input') as HTMLTextAreaElement;
const submitButton = document.getElementById('post-submit') as HTMLButtonElement;
const statusEl = document.getElementById('post-status') as HTMLParagraphElement;
const countEl = document.getElementById('post-count') as HTMLSpanElement;
const listEl = document.getElementById('post-list') as HTMLUListElement;
const emptyEl = document.getElementById('empty-state') as HTMLDivElement;
const relatedPanelEl = document.getElementById('related-panel') as HTMLElement;
const relatedCountEl = document.getElementById('related-count') as HTMLSpanElement;
const relatedListEl = document.getElementById('related-list') as HTMLUListElement;

const store = new LocalPostStore(window.localStorage);
const dateTimeFormat = new Intl.DateTimeFormat(undefined, {
  month: 'short',
  day: 'numeric',
  hour: '2-digit',
  minute: '2-digit',
});

let posts: LocalPost[] = [];
let retrievalIndex = new PostRetrievalIndex(posts);

function pluralizePosts(count: number): string {
  return count === 1 ? '1 post' : `${count} posts`;
}

function pluralizeRelated(count: number): string {
  return count === 1 ? '1 related post' : `${count} related posts`;
}

function setStatus(message: string, tone: 'idle' | 'success' | 'error' = 'idle'): void {
  statusEl.textContent = message;
  statusEl.dataset.tone = tone;
}

function formatTimestamp(value: string): string {
  return dateTimeFormat.format(new Date(value));
}

function syncSubmitState(): void {
  submitButton.disabled = draft.value.trim().length === 0;
}

function renderPost(post: LocalPost): HTMLLIElement {
  const item = document.createElement('li');
  item.className = 'post-item';

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

function renderRelatedPost(result: RelatedPost): HTMLLIElement {
  const item = document.createElement('li');
  item.className = 'related-item';

  const article = document.createElement('article');

  const meta = document.createElement('div');
  meta.className = 'related-meta';

  const time = document.createElement('time');
  time.dateTime = result.post.createdAt;
  time.textContent = formatTimestamp(result.post.createdAt);

  const match = document.createElement('span');
  match.className = 'related-match';
  match.textContent = `Echoes ${result.matchedTerms.slice(0, 3).join(' · ')}`;

  const text = document.createElement('p');
  text.className = 'related-text';
  text.textContent = result.post.text;

  meta.append(time, match);
  article.append(meta, text);
  item.append(article);
  return item;
}

function renderRelated(): void {
  const relatedPosts = retrievalIndex.query(draft.value, { limit: 5 });
  relatedCountEl.textContent = pluralizeRelated(relatedPosts.length);
  relatedListEl.replaceChildren(...relatedPosts.map(renderRelatedPost));
  relatedPanelEl.hidden = relatedPosts.length === 0;
}

function replacePosts(nextPosts: LocalPost[]): void {
  posts = nextPosts;
  retrievalIndex = new PostRetrievalIndex(posts);
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

draft.addEventListener('input', () => {
  syncSubmitState();
  renderRelated();
});

loadPosts();
syncSubmitState();
draft.focus();
