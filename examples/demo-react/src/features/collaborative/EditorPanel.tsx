// EditorPanel — a single agent's editor within the collaborative demo.
//
// Uses the protocol-based CRDT editor.
// Local sync: reads/writes shared text store.
// WebSocket sync: uses CRDT export/apply for real sync (when available).

import { useEffect, useCallback, useRef, useSyncExternalStore } from 'react';
import { useProtocolEditor } from '../editor';
import {
  getSharedText,
  setSharedText,
  subscribeSharedText,
  logOperation,
  WS_URL,
  ROOM_ID,
} from './store';

interface EditorPanelProps {
  agentId: string;
  color: string;
  useWebSocket?: boolean;
}

export function EditorPanel({ agentId, color, useWebSocket = false }: EditorPanelProps) {
  const {
    state,
    editor,
    setText,
    setCursor,
    setTextWithoutUndo,
    undo,
    redo,
    syncFromCrdt,
  } = useProtocolEditor({ agentId });

  const sharedText = useSyncExternalStore(subscribeSharedText, getSharedText, getSharedText);

  // Track sync state to prevent echo loops
  const syncingRef = useRef(false);
  const lastSyncedTextRef = useRef('');

  // --- Local sync: shared text -> local editor ---
  useEffect(() => {
    if (useWebSocket) return;
    if (syncingRef.current) return;
    if (!editor) return;

    if (sharedText !== state.text && sharedText !== lastSyncedTextRef.current) {
      syncingRef.current = true;
      lastSyncedTextRef.current = sharedText;
      setTextWithoutUndo(sharedText);
      // Reset sync flag on next microtask
      queueMicrotask(() => {
        syncingRef.current = false;
      });
    }
  }, [sharedText, state.text, editor, setTextWithoutUndo, useWebSocket]);

  // --- Local sync: local editor -> shared text ---
  // We do this in handleChange rather than an effect to avoid loops.

  // --- WebSocket sync ---
  const wsRef = useRef<WebSocket | null>(null);
  const wsProcessingRemoteRef = useRef(false);

  useEffect(() => {
    if (!useWebSocket || !editor) return;

    const ws = new WebSocket(WS_URL);
    wsRef.current = ws;

    ws.onopen = () => {
      ws.send(JSON.stringify({ type: 'join', room: ROOM_ID }));
      // Send current state on join
      const syncMsg = editor.exportAllJson();
      ws.send(JSON.stringify({ type: 'sync', room: ROOM_ID, data: syncMsg }));
    };

    ws.onmessage = (event) => {
      const message = JSON.parse(event.data);
      if (message.type === 'sync' && message.data) {
        wsProcessingRemoteRef.current = true;
        editor.applySyncJson(message.data);
        syncFromCrdt();
        wsProcessingRemoteRef.current = false;
      }
    };

    return () => {
      ws.close();
      wsRef.current = null;
    };
  }, [useWebSocket, editor, syncFromCrdt]);

  const handleChange = useCallback(
    (e: React.ChangeEvent<HTMLTextAreaElement>) => {
      const newText = e.target.value;
      const oldText = state.text;

      setText(newText);
      setCursor(e.target.selectionStart || 0);

      // Log operation
      if (newText.length > oldText.length) {
        const diff = newText.length - oldText.length;
        logOperation({
          agentId,
          type: 'insert',
          content: diff <= 5 ? newText.slice(-diff) : `+${diff} chars`,
          timestamp: Date.now(),
        });
      } else if (newText.length < oldText.length) {
        logOperation({
          agentId,
          type: 'delete',
          content: `${oldText.length - newText.length} chars`,
          timestamp: Date.now(),
        });
      }

      // Propagate to shared state (local sync)
      if (!useWebSocket && !syncingRef.current) {
        lastSyncedTextRef.current = newText;
        setSharedText(newText);
      }

      // Propagate via WebSocket sync
      if (useWebSocket && editor && wsRef.current?.readyState === WebSocket.OPEN && !wsProcessingRemoteRef.current) {
        const syncMsg = editor.exportAllJson();
        wsRef.current.send(JSON.stringify({ type: 'sync', room: ROOM_ID, data: syncMsg }));
      }
    },
    [agentId, state.text, setText, setCursor, useWebSocket, editor]
  );

  const handleSelect = useCallback(
    (e: React.SyntheticEvent<HTMLTextAreaElement>) => {
      setCursor(e.currentTarget.selectionStart || 0);
    },
    [setCursor]
  );

  const handleUndo = useCallback(() => {
    undo();
    logOperation({ agentId, type: 'undo', timestamp: Date.now() });
    if (!useWebSocket && !syncingRef.current && editor) {
      const text = editor.getText();
      lastSyncedTextRef.current = text;
      setSharedText(text);
    }
  }, [agentId, undo, useWebSocket, editor]);

  const handleRedo = useCallback(() => {
    redo();
    logOperation({ agentId, type: 'redo', timestamp: Date.now() });
    if (!useWebSocket && !syncingRef.current && editor) {
      const text = editor.getText();
      lastSyncedTextRef.current = text;
      setSharedText(text);
    }
  }, [agentId, redo, useWebSocket, editor]);

  const handleKeyDown = useCallback(
    (e: React.KeyboardEvent<HTMLTextAreaElement>) => {
      if ((e.ctrlKey || e.metaKey) && e.key === 'z' && !e.shiftKey) {
        e.preventDefault();
        handleUndo();
      }
      if (
        ((e.ctrlKey || e.metaKey) && e.key === 'z' && e.shiftKey) ||
        ((e.ctrlKey || e.metaKey) && e.key === 'y')
      ) {
        e.preventDefault();
        handleRedo();
      }
    },
    [handleUndo, handleRedo]
  );

  return (
    <div className="editor-panel" style={{ borderColor: color }}>
      <div className="panel-header" style={{ backgroundColor: color }}>
        <span className="panel-title">{agentId}</span>
        <span className="panel-cursor">Cursor: {state.cursor}</span>
      </div>
      <textarea
        className="panel-textarea"
        value={state.text}
        onChange={handleChange}
        onSelect={handleSelect}
        onKeyDown={handleKeyDown}
        placeholder={`${agentId}'s editor - type here...`}
        spellCheck={false}
        autoComplete="off"
        autoCorrect="off"
        autoCapitalize="off"
      />
      <div className="panel-status">
        <span>Chars: {state.text.length}</span>
        <div className="panel-undo-controls">
          <button
            className="panel-undo-btn"
            onClick={handleUndo}
            disabled={!state.canUndo}
            title={`Undo ${agentId}'s changes`}
          >
            Undo
          </button>
          <button
            className="panel-undo-btn"
            onClick={handleRedo}
            disabled={!state.canRedo}
            title={`Redo ${agentId}'s changes`}
          >
            Redo
          </button>
        </div>
      </div>
    </div>
  );
}
