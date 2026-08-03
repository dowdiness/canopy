import { LifecycleLink } from '../../../shared/route-lifecycle/browser/lifecycle-link';

export async function MemoRoute() {
  if (import.meta.env.PROD) {
    return (
      <main className="route-state" data-memo-production-unavailable>
        <p className="route-state__label">Local-only demo</p>
        <h1 tabIndex={-1} data-route-heading>Canopy Memo</h1>
        <p>
          This demo is available only in local development because it sends
          provider requests directly from the browser. Production requires a
          server-side provider proxy.
        </p>
        <LifecycleLink className="route-state__action" to="/">
          Back to demos
        </LifecycleLink>
      </main>
    );
  }

  const { MemoClient } = await import('./memo-client');
  return (
    <MemoClient>
      <div>
        <div className="container">
          <h1 data-route-heading tabIndex={-1}>Canopy Memo</h1>
          <p className="subtitle">AI-powered text editor — typo correction &amp; structured edits</p>
          <div className="memo-app" inert data-memo-ready="false">
            <div style={{ background: '#2a1a1a', border: '1px solid #ff537044', borderRadius: 6, padding: '10px 14px', marginBottom: 16, fontSize: 12, color: '#ff8a80' }}>
              <strong>Local demo only.</strong> API key is sent directly from your browser to Google.
              Do not deploy this page publicly. Production use requires a server-side proxy.
            </div>
            <div className="config-section">
              <label htmlFor="api-key">Gemini API Key:</label>
              <input type="password" id="api-key" placeholder="Enter your API key (stored in memory only)" />
            </div>
            <div className="editor-area">
              <textarea id="memo" data-route-focus="memo" placeholder="Type or paste your text here..."></textarea>
              <div className="toolbar">
                <button id="fix-typos-btn" className="btn btn-primary">Fix Typos</button>
              </div>
              <div className="instruction-row">
                <input type="text" id="instruction" data-route-focus="instruction" placeholder="Edit instruction (e.g. 3行目をもっと丁寧にして)" />
                <button id="edit-btn" className="btn btn-secondary">Edit</button>
              </div>
              <div className="status-bar" id="status"></div>
            </div>
            <div className="diff-section" id="diff-section">
              <h2>Suggested Changes</h2>
              <div className="diff-content">
                <div className="diff-pane">
                  <h3>Original</h3>
                  <pre id="diff-original"></pre>
                </div>
                <div className="diff-pane">
                  <h3>Corrected</h3>
                  <pre id="diff-fixed"></pre>
                </div>
              </div>
              <div className="diff-actions">
                <button id="accept-btn" className="btn btn-primary">Accept</button>
                <button id="reject-btn" className="btn btn-secondary">Reject</button>
              </div>
            </div>
          </div>
        </div>
      </div>
    </MemoClient>
  );
}
