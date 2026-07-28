import { PostsClient } from './posts-client';

export function PostsRoute() {
  return (
    <PostsClient>
      <div>
        <main className="shell">
          <header>
            <p className="eyebrow">Local-first prototype</p>
            <h1 data-route-heading tabIndex={-1}>Post to yourself.</h1>
            <p className="lede">One field, no folders, no API key. As you write, a few old posts return quietly underneath; the stream stays newest-first when you just want chronology.</p>
          </header>

          <form className="composer" id="post-form" inert data-posts-ready="false">
            <label htmlFor="post-input">
              Write
              <textarea id="post-input" name="post" placeholder="A thought, reminder, note, or question for future you…" autoComplete="off" data-route-focus="draft"></textarea>
            </label>

            <div className="composer-actions">
              <p className="hint"><kbd>Ctrl</kbd>/<kbd>⌘</kbd> + <kbd>Enter</kbd> posts. Plain <kbd>Enter</kbd> keeps writing.</p>
              <div className="composer-buttons">
                <button className="ask-button" id="post-ask" type="button">Ask</button>
                <button className="post-button" id="post-submit" type="submit">Post</button>
              </div>
            </div>

            <div className="status-row" aria-live="polite">
              <p id="post-status"></p>
              <span id="post-count">0 posts</span>
            </div>
          </form>

          <section className="related-panel" id="related-panel" aria-labelledby="related-title" hidden>
            <div className="related-heading">
              <div>
                <p className="related-kicker" id="related-kicker">Returning while writing</p>
                <h2 id="related-title">Related posts</h2>
              </div>
              <span id="related-count">0 related posts</span>
            </div>
            <p className="related-empty" id="related-empty" hidden>No matching source posts yet. Try words you remember from the post.</p>
            <ul className="related-list" id="related-list"></ul>
          </section>

          <section className="timeline" aria-labelledby="timeline-title">
            <h2 id="timeline-title">Chronological fallback · newest first</h2>
            <div className="empty-state" id="empty-state">
              <p>No posts yet. Write the smallest thing worth remembering and reload the page to prove it stays.</p>
            </div>
            <ul className="post-list" id="post-list"></ul>
          </section>
        </main>
      </div>
    </PostsClient>
  );
}
