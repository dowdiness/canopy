'use client';

/**
 * THROWAWAY PROTOTYPE — answers issue “Prototype a React boundary for an
 * imperative editor demo”. React owns the host DOM, focus handoff, saved text
 * snapshot, and mount/dispose lifecycle; the imperative adapter owns one live
 * MoonBit editor session and its decorations between those boundaries.
 */
import { useEffect, useRef, useState } from 'react';
import {
  mountJsonEditor,
  type JsonEditorController,
} from '../browser/editor';
import '../browser/styles.css';

const controlStyle = {
  minHeight: 44,
  padding: '8px 14px',
  border: '1px solid #666',
  borderRadius: 3,
  background: '#3c3c3c',
  color: '#d4d4d4',
  font: 'inherit',
  cursor: 'pointer',
} as const;

export function JsonReactBoundaryPrototype() {
  const controllerRef = useRef<JsonEditorController | null>(null);
  const [mounted, setMounted] = useState(true);
  const [snapshot, setSnapshot] = useState<string | undefined>();
  const [mountCount, setMountCount] = useState(0);
  const [focusOwner, setFocusOwner] = useState('pending');
  const [decorationCount, setDecorationCount] = useState(0);

  useEffect(() => {
    if (!mounted) return;

    const controller = mountJsonEditor({ initialText: snapshot });
    controllerRef.current = controller;
    setMountCount((count) => count + 1);

    const focusFrame = requestAnimationFrame(() => {
      controller.focus();
      setFocusOwner(document.activeElement?.id ?? 'none');
      setDecorationCount(
        document.querySelectorAll('.decoration-overlay .decoration-mark').length,
      );
    });

    return () => {
      cancelAnimationFrame(focusFrame);
      const nextSnapshot = controller.getText();
      controller.dispose();
      controllerRef.current = null;
      setSnapshot(nextSnapshot);
      setFocusOwner('released');
      setDecorationCount(0);
    };
  }, [mounted]);

  const returnFocus = () => {
    controllerRef.current?.focus();
    setFocusOwner(document.activeElement?.id ?? 'none');
  };

  return (
    <main className="container">
      <header style={{ marginBottom: 20 }}>
        <p style={{ color: '#dcdcaa', marginBottom: 8 }}>
          THROWAWAY REACT BOUNDARY PROTOTYPE
        </p>
        <h1>{'{} JSON CRDT Editor'}</h1>
        <p className="subtitle">
          The editor UI is unchanged. Use these controls to exercise React-owned
          mount, disposal, state handoff, focus restoration, and decoration
          reconstruction.
        </p>
      </header>

      <section
        aria-label="Prototype lifecycle controls"
        style={{
          display: 'flex',
          flexWrap: 'wrap',
          alignItems: 'center',
          gap: 12,
          marginBottom: 20,
          padding: 14,
          border: '1px solid #665c33',
          background: '#2b2a22',
        }}
      >
        <button
          type="button"
          style={controlStyle}
          onClick={() => setMounted((value) => !value)}
        >
          {mounted ? 'Dispose editor' : 'Remount editor'}
        </button>
        <button
          type="button"
          style={controlStyle}
          disabled={!mounted}
          onClick={returnFocus}
        >
          Return focus to editor
        </button>
        <dl
          aria-live="polite"
          style={{
            display: 'grid',
            gridTemplateColumns: 'max-content minmax(8ch, 1fr)',
            gap: '4px 10px',
            marginLeft: 'auto',
            fontSize: 12,
          }}
        >
          <dt style={{ color: '#858585' }}>Boundary</dt>
          <dd>{mounted ? 'mounted' : 'disposed'}</dd>
          <dt style={{ color: '#858585' }}>Mount cycles</dt>
          <dd>{mountCount}</dd>
          <dt style={{ color: '#858585' }}>Saved text</dt>
          <dd>{snapshot === undefined ? 'not captured' : `${snapshot.length} chars`}</dd>
          <dt style={{ color: '#858585' }}>Focus owner</dt>
          <dd>{focusOwner}</dd>
          <dt style={{ color: '#858585' }}>Decorations</dt>
          <dd>{decorationCount}</dd>
        </dl>
      </section>

      {mounted ? (
        <JsonEditorSurface />
      ) : (
        <section
          aria-label="Disposed editor state"
          style={{
            display: 'grid',
            minHeight: 360,
            placeItems: 'center',
            border: '1px dashed #555',
            color: '#9d9d9d',
          }}
        >
          The React host is absent; the MoonBit handle, adapter, observers, and
          decoration overlay have been released.
        </section>
      )}
    </main>
  );
}

function JsonEditorSurface() {
  return (
    <>
      <div className="examples-bar">
        <span className="examples-label">Examples:</span>
        <button className="example-btn" data-example='{"hello": "world"}'>
          Simple
        </button>
        <button
          className="example-btn"
          data-example='{"name":"Canopy","enabled":true,"count":3}'
        >
          Object
        </button>
        <button className="example-btn" data-example='["alpha", 42, false, null]'>
          Array
        </button>
        <button
          className="example-btn"
          data-example='{"user":{"name":"Ada","roles":["admin","editor"]},"meta":{"active":true,"visits":12}}'
        >
          Nested
        </button>
      </div>

      <div className="layout">
        <section className="panel">
          <div
            className="panel-header"
            style={{ display: 'flex', alignItems: 'center', gap: 10 }}
          >
            <h2>JSON Text</h2>
            <button id="format-btn" className="toolbar-btn" type="button">
              Format
            </button>
            <button
              id="struct-toggle-btn"
              className="toolbar-btn"
              type="button"
              style={{ marginLeft: 'auto' }}
            >
              ▦ Structured
            </button>
          </div>
          <div className="editor-shell">
            <div className="editor-wrapper">
              <div id="json-gutter" className="editor-gutter" />
              <div
                id="json-input"
                contentEditable="plaintext-only"
                suppressContentEditableWarning
                spellCheck={false}
                className="json-editor-raw"
              />
              <div
                id="json-editor-view"
                className="json-editor-view"
                style={{ display: 'none' }}
              />
            </div>

            <div className="errors-panel" id="errors-panel">
              <div className="errors-header">Parse Errors</div>
              <ul id="parse-errors" className="error-list" />
            </div>
          </div>
          <section
            className="panel patch-log-panel"
            id="patch-log-panel"
            style={{ border: 'none', marginTop: 0, borderTop: '1px solid #3c3c3c' }}
          >
            <div className="panel-header patch-log-header" id="patch-log-header">
              <h2>
                Edit Log{' '}
                <span id="patch-log-count" className="patch-log-count">
                  0
                </span>
              </h2>
              <span id="patch-log-toggle" className="patch-log-toggle">
                ▾
              </span>
            </div>
            <div id="patch-log-body" className="patch-log-body">
              <div id="patch-log-empty" className="patch-log-empty">
                No edits yet.
              </div>
            </div>
          </section>
        </section>
        <div id="tree-view" style={{ display: 'none' }} />
      </div>
    </>
  );
}
