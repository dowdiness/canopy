import { PostRetrievalIndex, type RelatedPost } from '../core/post-retrieval';
import type { LocalPost } from '../core/posts';
import type { LocalPostEventStore } from './post-events';
import type { LocalPostStore } from './post-store';
import type { PostsView, RelatedPanelMode } from './view';

interface PostsAppDependencies {
  readonly store: LocalPostStore;
  readonly eventStore: LocalPostEventStore;
  readonly view: PostsView;
}

export function createPostsApp({ store, eventStore, view }: PostsAppDependencies) {
  let posts: LocalPost[] = [];
  let highlightedPostId: string | null = null;
  let relatedMode: RelatedPanelMode = 'writing';
  let retrievalIndex = new PostRetrievalIndex(posts, eventStore.engagementByPost());

  function pluralizePosts(count: number): string {
    return count === 1 ? '1 post' : `${count} posts`;
  }

  function pluralizeSources(count: number): string {
    return count === 1 ? '1 source post' : `${count} source posts`;
  }

  function replacePosts(nextPosts: LocalPost[]): void {
    posts = nextPosts;
    retrievalIndex = new PostRetrievalIndex(posts, eventStore.engagementByPost());
  }

  function renderRelated(): number {
    return view.renderRelated(
      retrievalIndex.query(view.draftText(), { limit: 5 }),
      relatedMode,
      openRelatedPost,
    );
  }

  function render(): void {
    view.renderTimeline(posts, highlightedPostId);
    renderRelated();
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
    view.focusTimelinePost(result.post.id);
    const openedLabel = relatedMode === 'ask' ? 'source post' : 'related post';
    view.setStatus(
      recorded
        ? `Opened a ${openedLabel}. Revisited posts get a small ranking boost.`
        : `Opened a ${openedLabel}, but could not save its revisit signal.`,
      recorded ? 'success' : 'error',
    );
  }

  function loadPosts(): void {
    try {
      replacePosts(store.all());
      render();
      view.setStatus(`${pluralizePosts(posts.length)} stored locally on this device.`);
    } catch (error) {
      replacePosts([]);
      render();
      view.setStatus(
        `Could not read saved posts: ${error instanceof Error ? error.message : String(error)}`,
        'error',
      );
    }
  }

  function submitDraft(): void {
    const text = view.draftText().trim();
    if (text.length === 0) {
      view.setStatus('Write something before posting.', 'error');
      view.focusDraft();
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
      view.clearDraft();
      view.syncSubmitState();
      render();
      view.setStatus('Posted. It will still be here after reload.', 'success');
      view.focusDraft();
    } catch (error) {
      view.setStatus(
        `Could not save this post: ${error instanceof Error ? error.message : String(error)}`,
        'error',
      );
    }
  }

  function askDraft(): void {
    if (view.draftText().trim().length === 0) {
      view.setStatus('Write a question before asking.', 'error');
      view.focusDraft();
      return;
    }

    relatedMode = 'ask';
    const sourceCount = renderRelated();
    view.setStatus(
      sourceCount === 0
        ? 'No source posts matched that question. Nothing was posted.'
        : `Found ${pluralizeSources(sourceCount)}. Nothing was posted.`,
      sourceCount === 0 ? 'idle' : 'success',
    );
    view.focusDraft();
  }

  return {
    mount(): void {
      view.bind({
        submitDraft,
        askDraft,
        updateDraft(): void {
          relatedMode = 'writing';
          view.syncSubmitState();
          renderRelated();
        },
      });
      loadPosts();
      view.syncSubmitState();
      view.focusDraft();
    },
  };
}
