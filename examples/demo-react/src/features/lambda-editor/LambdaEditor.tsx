// LambdaEditor Component
//
// A React component that uses the MoonBit CRDT via the EditorProtocol.

import { useState, useEffect, useCallback, useRef } from 'react';
import { useProtocolEditor, Toolbar, StatusBar } from '../editor';

// Example lambda expressions
const EXAMPLES = [
  { label: 'Identity', code: '((x) => x) 42' },
  { label: 'Church 2', code: '((f, x) => f (f x)) ((n) => n + 1) 0' },
  { label: 'Add', code: '((x, y) => x + y) 10 5' },
  { label: 'Conditional', code: 'if 1 then 42 else 0' },
  { label: 'Apply', code: '((f, x) => f x) ((n) => n - 1) 10' },
];

interface LambdaEditorProps {
  /** Initial text content */
  initialText?: string;
  /** Callback when text changes */
  onTextChange?: (text: string) => void;
  /** Custom agent ID */
  agentId?: string;
}

export function LambdaEditor({
  initialText = '',
  onTextChange,
  agentId,
}: LambdaEditorProps) {
  // Stable agent ID — generated once and memoized to avoid re-creating
  // the CRDT editor on every render (critical for React StrictMode).
  const [id] = useState(() => agentId || `user-${Date.now()}-${Math.random().toString(36).slice(2, 9)}`);
  const { state, setText, setCursor, setTextWithoutUndo, undo, redo } = useProtocolEditor({
    agentId: id,
    initialText,
  });

  const editorRef = useRef<HTMLTextAreaElement>(null);

  // Notify parent of text changes
  useEffect(() => {
    onTextChange?.(state.text);
  }, [state.text, onTextChange]);

  const handleTextChange = useCallback(
    (e: React.ChangeEvent<HTMLTextAreaElement>) => {
      setText(e.target.value);
      setCursor(e.target.selectionStart || 0);
    },
    [setText, setCursor]
  );

  const handleSelect = useCallback(
    (e: React.SyntheticEvent<HTMLTextAreaElement>) => {
      setCursor(e.currentTarget.selectionStart || 0);
    },
    [setCursor]
  );

  const handleKeyDown = useCallback(
    (e: React.KeyboardEvent<HTMLTextAreaElement>) => {
      if ((e.ctrlKey || e.metaKey) && e.key === 'z' && !e.shiftKey) {
        e.preventDefault();
        undo();
      }
      if (
        ((e.ctrlKey || e.metaKey) && e.key === 'z' && e.shiftKey) ||
        ((e.ctrlKey || e.metaKey) && e.key === 'y')
      ) {
        e.preventDefault();
        redo();
      }
    },
    [undo, redo]
  );

  const handleLoadExample = useCallback(
    (code: string) => {
      setTextWithoutUndo(code);
      setCursor(code.length);
      editorRef.current?.focus();
    },
    [setTextWithoutUndo, setCursor]
  );

  const handleClear = useCallback(() => {
    setTextWithoutUndo('');
    setCursor(0);
    editorRef.current?.focus();
  }, [setTextWithoutUndo, setCursor]);

  const displayAgentId = agentId || 'local';

  return (
    <div className="lambda-editor">
      <Toolbar
        onUndo={undo}
        onRedo={redo}
        onClear={handleClear}
        canUndo={state.canUndo}
        canRedo={state.canRedo}
      />

      <div className="examples-bar">
        <span className="examples-label">Examples:</span>
        {EXAMPLES.map((example) => (
          <button
            key={example.label}
            className="example-btn"
            onClick={() => handleLoadExample(example.code)}
          >
            {example.label}
          </button>
        ))}
      </div>

      <div className="editor-container">
        <textarea
          ref={editorRef}
          className="editor-textarea"
          value={state.text}
          onChange={handleTextChange}
          onSelect={handleSelect}
          onKeyDown={handleKeyDown}
          placeholder="Type lambda calculus expressions here... (e.g., ((x) => x) 5)"
          spellCheck={false}
          autoComplete="off"
          autoCorrect="off"
          autoCapitalize="off"
        />
      </div>

      <StatusBar
        charCount={state.text.length}
        cursorPosition={state.cursor}
        agentId={displayAgentId}
        syncing={false}
      />
    </div>
  );
}
