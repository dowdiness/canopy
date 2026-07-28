import { JsonClient } from './json-client';

export function JsonRoute() {
  return (
    <JsonClient>
      <div>
        <div className="container">
          <h1 data-route-heading tabIndex={-1}>{'{}'} JSON CRDT Editor</h1>
          <p className="subtitle">Structural JSON editing with CRDT collaboration</p>

          <div className="json-app" inert data-json-ready="false">
            <div className="examples-bar">
              <span className="examples-label">Examples:</span>
              <button className="example-btn" data-example='{"hello": "world"}'>Simple</button>
              <button className="example-btn" data-example='{"name":"Canopy","enabled":true,"count":3}'>Object</button>
              <button className="example-btn" data-example='["alpha", 42, false, null]'>Array</button>
              <button className="example-btn" data-example='{"user":{"name":"Ada","roles":["admin","editor"]},"meta":{"active":true,"visits":12}}'>Nested</button>
            </div>

            <div className="layout">
              <section className="panel">
                <div className="panel-header" style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
                  <h2>JSON Text</h2>
                  <button id="format-btn" className="toolbar-btn" type="button">Format</button>
                  <button id="struct-toggle-btn" className="toolbar-btn" type="button" style={{ marginLeft: 'auto' }} data-route-focus="structure-toggle">▦ Structured</button>
                </div>
                <div className="editor-shell">
                  <div className="editor-wrapper">
                    <div id="json-gutter" className="editor-gutter"></div>
                    <div id="json-input" contentEditable="plaintext-only" spellCheck={false} className="json-editor-raw" data-route-focus="editor"></div>
                    <div id="json-editor-view" className="json-editor-view" style={{ display: 'none' }}></div>
                  </div>

                  <div className="errors-panel" id="errors-panel">
                    <div className="errors-header">Parse Errors</div>
                    <ul id="parse-errors" className="error-list"></ul>
                  </div>
                </div>
                <section className="panel patch-log-panel" id="patch-log-panel" style={{ border: 'none', marginTop: 0, borderTop: '1px solid #3c3c3c' }}>
                  <div className="panel-header patch-log-header" id="patch-log-header">
                    <h2>Edit Log <span id="patch-log-count" className="patch-log-count">0</span></h2>
                    <span id="patch-log-toggle" className="patch-log-toggle">▾</span>
                  </div>
                  <div id="patch-log-body" className="patch-log-body">
                    <div id="patch-log-empty" className="patch-log-empty">No edits yet.</div>
                  </div>
                </section>
              </section>
              <div id="tree-view" style={{ display: 'none' }}></div>
            </div>
          </div>
        </div>
      </div>
    </JsonClient>
  );
}
