// CollaborativeDemo — orchestrates the per-agent undo/redo demo.
//
// Uses protocol-based CRDT editors.

import { useState, useEffect, useCallback, useSyncExternalStore } from 'react';
import {
  getOperations,
  subscribeOperations,
  getSharedText,
  subscribeSharedText,
  setSharedText,
  clearOperations,
  resetSharedState,
  WS_URL,
} from './store';
import { EditorPanel } from './EditorPanel';

export function CollaborativeDemo() {
  const [useWebSocket, setUseWebSocket] = useState(false);
  const [wsStatus, setWsStatus] = useState<'unknown' | 'connected' | 'disconnected'>('unknown');

  const operations = useSyncExternalStore(subscribeOperations, getOperations, getOperations);
  const sharedText = useSyncExternalStore(subscribeSharedText, getSharedText, getSharedText);

  // Check WebSocket server availability with timeout
  useEffect(() => {
    let ws: WebSocket | null = null;
    let timeoutId: ReturnType<typeof setTimeout>;

    const checkServer = () => {
      ws = new WebSocket(WS_URL);

      timeoutId = setTimeout(() => {
        if (ws && ws.readyState !== WebSocket.OPEN) {
          ws.close();
          setWsStatus('disconnected');
        }
      }, 2000);

      ws.onopen = () => {
        clearTimeout(timeoutId);
        setWsStatus('connected');
        ws?.close();
      };

      ws.onerror = () => {
        clearTimeout(timeoutId);
        setWsStatus('disconnected');
      };
    };

    checkServer();

    return () => {
      clearTimeout(timeoutId);
      ws?.close();
    };
  }, []);

  const handleReset = useCallback(() => {
    resetSharedState();
  }, []);

  const handleLoadExample = useCallback(() => {
    setSharedText('(\\x.\\y.x + y) 10 5');
    clearOperations();
  }, []);

  return (
    <div className="collaborative-demo">
      <div className="demo-header">
        <h2>Per-Agent Undo/Redo Demo</h2>
        <p className="demo-description">
          Each editor has its own undo/redo stack. Alice's undo only undoes
          Alice's changes, not Bob's. This is how real collaborative editors work.
        </p>

        <div className="sync-mode-toggle">
          <label>
            <input
              type="checkbox"
              checked={useWebSocket}
              onChange={(e) => setUseWebSocket(e.target.checked)}
              disabled={wsStatus === 'disconnected'}
            />
            {' '}Use WebSocket Sync
            {wsStatus === 'connected' && <span className="ws-status connected"> (Server Online)</span>}
            {wsStatus === 'disconnected' && <span className="ws-status disconnected"> (Server Offline - run `npm run server`)</span>}
          </label>
        </div>

        <div className="demo-controls">
          <button className="demo-btn" onClick={handleLoadExample}>
            Load Example
          </button>
          <button className="demo-btn demo-btn-secondary" onClick={handleReset}>
            Reset
          </button>
        </div>
      </div>

      <div className="shared-doc-info">
        <span className="shared-label">
          {useWebSocket ? 'Sync Mode: WebSocket' : 'Sync Mode: Local'}
        </span>
        <code className="shared-text">
          {sharedText || '(empty)'}
        </code>
      </div>

      <div className="editors-container" key={useWebSocket ? 'ws' : 'local'}>
        <EditorPanel agentId="Alice" color="#4ec9b0" useWebSocket={useWebSocket} />
        <EditorPanel agentId="Bob" color="#ce9178" useWebSocket={useWebSocket} />
      </div>

      <div className="operations-log">
        <h3>Operations Log</h3>
        <div className="log-container">
          {operations.length === 0 ? (
            <p className="log-empty">No operations yet. Start typing!</p>
          ) : (
            <ul className="log-list">
              {operations.slice(-10).map((op, i) => (
                <li key={i} className={`log-item log-${op.type}`}>
                  <span className="log-agent">{op.agentId}</span>
                  <span className="log-type">{op.type}</span>
                  {op.content && (
                    <span className="log-content">{op.content}</span>
                  )}
                </li>
              ))}
            </ul>
          )}
        </div>
      </div>

      <div className="demo-info">
        <h3>How Per-Agent Undo Works</h3>
        <ol className="demo-steps">
          <li>Alice types "Hello" → Alice's undo stack: [H, e, l, l, o]</li>
          <li>Bob types " World" → Bob's undo stack: [ , W, o, r, l, d]</li>
          <li>Alice presses Undo → Removes "o" (Alice's last change)</li>
          <li>Document shows "Hell World" (Bob's changes preserved)</li>
        </ol>
        <p className="demo-note">
          {useWebSocket
            ? 'WebSocket mode: Operations sync via ws://localhost:8787 relay server.'
            : 'Local mode: Operations sync via shared store (same browser tab only).'}
        </p>
      </div>
    </div>
  );
}
