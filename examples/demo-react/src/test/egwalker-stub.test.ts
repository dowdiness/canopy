import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { stubCrdtModule } from '../features/editor/crdt-stub';
import { EditorHandle } from '../features/editor/crdt-api';

describe('EditorHandle with stub module', () => {
  let editor: EditorHandle;

  beforeEach(() => {
    editor = new EditorHandle(stubCrdtModule, 'test-agent', true);
  });

  afterEach(() => {
    editor.destroy();
  });

  describe('basic operations', () => {
    it('should create an editor with initial empty state', () => {
      expect(editor.getText()).toBe('');
    });

    it('should update text when setting text', () => {
      editor.setText('Hello');
      expect(editor.getText()).toBe('Hello');
    });

    it('should set text and record for undo', () => {
      editor.setTextAndRecord('Hello');
      expect(editor.getText()).toBe('Hello');
    });
  });

  describe('undo/redo', () => {
    it('should track changes in undo stack', () => {
      expect(editor.canUndo()).toBe(false);

      editor.setTextAndRecord('a');
      expect(editor.canUndo()).toBe(true);
    });

    it('should undo changes', () => {
      editor.setTextAndRecord('Hello');
      editor.undo();
      expect(editor.getText()).toBe('');
    });

    it('should redo undone changes', () => {
      editor.setTextAndRecord('Hello');
      editor.undo();
      expect(editor.getText()).toBe('');

      editor.redo();
      expect(editor.getText()).toBe('Hello');
    });

    it('should clear redo stack on new changes', () => {
      editor.setTextAndRecord('Hello');
      editor.undo();
      expect(editor.canRedo()).toBe(true);

      editor.setTextAndRecord('World');
      expect(editor.canRedo()).toBe(false);
    });

    it('should not track changes when tracking is disabled', () => {
      editor.setTracking(false);
      editor.setText('Hello');
      editor.setTracking(true);

      expect(editor.canUndo()).toBe(false);
    });
  });

  describe('multiple undo/redo', () => {
    it('should handle multiple undos', () => {
      editor.setTextAndRecord('a');
      editor.setTextAndRecord('ab');
      editor.setTextAndRecord('abc');

      expect(editor.canUndo()).toBe(true);

      editor.undo();
      expect(editor.getText()).toBe('ab');

      editor.undo();
      expect(editor.getText()).toBe('a');

      editor.undo();
      expect(editor.getText()).toBe('');
    });
  });
});

describe('EditorHandle without undo manager', () => {
  it('should not track undo when disabled', () => {
    const editor = new EditorHandle(stubCrdtModule, 'test-agent', false);

    editor.setText('Hello');
    // Undo should be a no-op
    editor.undo();
    expect(editor.getText()).toBe('Hello');

    editor.destroy();
  });
});

describe('sync operations', () => {
  it('should export and apply sync messages', () => {
    const editor1 = new EditorHandle(stubCrdtModule, 'agent-1', true);
    const editor2 = new EditorHandle(stubCrdtModule, 'agent-2', true);

    editor1.setTextAndRecord('Hello');
    const syncMsg = editor1.exportAllJson();

    const result = editor2.applySyncJson(syncMsg);
    expect(result).toBe('ok');
    expect(editor2.getText()).toBe('Hello');

    editor1.destroy();
    editor2.destroy();
  });

  it('should return version json', () => {
    const editor = new EditorHandle(stubCrdtModule, 'test-agent', true);
    const version = editor.getVersionJson();
    expect(version).toBeTruthy();
    editor.destroy();
  });
});
