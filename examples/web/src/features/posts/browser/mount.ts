import { createPostsApp } from './app';
import { LocalPostEventStore } from './post-events';
import { LocalPostStore } from './post-store';
import { createPostsView } from './view';

export function mountPosts(): void {
  createPostsApp({
    store: new LocalPostStore(window.localStorage),
    eventStore: new LocalPostEventStore(window.localStorage),
    view: createPostsView(document, window),
  }).mount();
}
