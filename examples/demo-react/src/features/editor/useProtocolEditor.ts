// useProtocolEditor — React hook for protocol-based CRDT editor.
//
// Wraps direct MoonBit CRDT calls in React state.
// State is managed via React's useState; re-renders are triggered by
// explicit setState calls after each mutation.
//
// The CRDT module is loaded synchronously (Vite alias resolves it at build time).
//
// React StrictMode compatibility: We use useRef + useEffect for editor lifecycle.
// StrictMode calls: mount effect -> cleanup effect -> mount effect again.
// The editor is created in useEffect and destroyed in cleanup. Callbacks check
// the ref and no-op if the editor is temporarily absent between cleanup/remount.

import { useState, useEffect, useCallback, useRef } from 'react';
import { EditorHandle, getCrdtModule } from './crdt-api';

interface UseProtocolEditorOptions {
  agentId: string;
  initialText?: string;
  undoEnabled?: boolean;
}

interface EditorState {
  text: string;
  cursor: number;
  canUndo: boolean;
  canRedo: boolean;
}

export interface ProtocolEditorResult {
  /** Current editor state (text, cursor, canUndo, canRedo) */
  state: EditorState;
  /** The underlying EditorHandle (null briefly during StrictMode remount) */
  editor: EditorHandle | null;
  /** Set the text content and record for undo */
  setText: (text: string) => void;
  /** Set cursor position */
  setCursor: (pos: number) => void;
  /** Set text without undo recording */
  setTextWithoutUndo: (text: string) => void;
  /** Undo last change */
  undo: () => void;
  /** Redo last undone change */
  redo: () => void;
  /** Sync state from the CRDT (call after external mutations) */
  syncFromCrdt: () => void;
}

export function useProtocolEditor(options: UseProtocolEditorOptions): ProtocolEditorResult {
  const { agentId, initialText, undoEnabled = true } = options;

  const editorRef = useRef<EditorHandle | null>(null);

  // Editor state tracked via useState for React re-renders.
  // Initial state uses initialText if provided.
  const [state, setState] = useState<EditorState>({
    text: initialText ?? '',
    cursor: initialText ? initialText.length : 0,
    canUndo: false,
    canRedo: false,
  });

  // Create editor in useEffect. Handles StrictMode correctly:
  // StrictMode: effect -> cleanup(destroy) -> effect(create new)
  // Normal: effect(create)
  useEffect(() => {
    const crdt = getCrdtModule();
    const editor = new EditorHandle(crdt, agentId, undoEnabled);
    if (initialText) {
      editor.setTracking(false);
      editor.setText(initialText);
      editor.setTracking(true);
    }
    editorRef.current = editor;

    // Sync state from the freshly created editor
    setState({
      text: editor.getText(),
      cursor: initialText ? initialText.length : 0,
      canUndo: editor.canUndo(),
      canRedo: editor.canRedo(),
    });

    return () => {
      editor.destroy();
      editorRef.current = null;
    };
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [agentId]);

  const syncFromCrdt = useCallback(() => {
    const ed = editorRef.current;
    if (!ed) return;
    setState(prev => ({
      ...prev,
      text: ed.getText(),
      canUndo: ed.canUndo(),
      canRedo: ed.canRedo(),
    }));
  }, []);

  const setText = useCallback((text: string) => {
    const ed = editorRef.current;
    if (!ed) return;
    ed.setTextAndRecord(text);
    setState(prev => ({
      ...prev,
      text: ed.getText(),
      canUndo: ed.canUndo(),
      canRedo: false,
    }));
  }, []);

  const setCursor = useCallback((pos: number) => {
    setState(prev => ({ ...prev, cursor: pos }));
  }, []);

  const setTextWithoutUndo = useCallback((text: string) => {
    const ed = editorRef.current;
    if (!ed) return;
    ed.setTracking(false);
    ed.setText(text);
    ed.setTracking(true);
    setState(prev => ({
      ...prev,
      text: ed.getText(),
      canUndo: ed.canUndo(),
      canRedo: ed.canRedo(),
    }));
  }, []);

  const undo = useCallback(() => {
    const ed = editorRef.current;
    if (!ed) return;
    ed.undo();
    setState(prev => ({
      ...prev,
      text: ed.getText(),
      canUndo: ed.canUndo(),
      canRedo: ed.canRedo(),
    }));
  }, []);

  const redo = useCallback(() => {
    const ed = editorRef.current;
    if (!ed) return;
    ed.redo();
    setState(prev => ({
      ...prev,
      text: ed.getText(),
      canUndo: ed.canUndo(),
      canRedo: ed.canRedo(),
    }));
  }, []);

  return {
    state,
    editor: editorRef.current,
    setText,
    setCursor,
    setTextWithoutUndo,
    undo,
    redo,
    syncFromCrdt,
  };
}
