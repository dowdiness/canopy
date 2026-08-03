import './styles.css';
import { createPostsApp } from './app';
import { LocalPostEventStore } from './post-events';
import { LocalPostStore } from './post-store';
import { createPostsView } from './view';
import type { MountedImperativeSession } from '../../../shared/route-lifecycle/browser/imperative-session';

export function mountPosts(
  root: Document | HTMLElement = globalThis.document,
  restoredSnapshot?: unknown,
): MountedImperativeSession {
  const document = root instanceof Document ? root : root.ownerDocument;
  const window = document.defaultView ?? globalThis.window;
  const app = createPostsApp({
    store: new LocalPostStore(window.localStorage),
    eventStore: new LocalPostEventStore(window.localStorage),
    view: createPostsView(root, window),
  });
  app.mount(restoredSnapshot, root instanceof Document);
  return app;
}
