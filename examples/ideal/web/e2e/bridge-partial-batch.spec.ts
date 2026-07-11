import { test, expect } from '@playwright/test';

test.describe('CrdtBridge partial batch handling', () => {
  test('broadcasts a valid prefix when a later splice in the same batch fails', async ({ page }) => {
    await page.goto('/', { waitUntil: 'domcontentloaded' });

    const result = await page.evaluate(async () => {
      const { CrdtBridge } = await import('/src/bridge.ts');
      const calls: Array<{ from: number; deleteLen: number; insert: string }> = [];
      const crdt = {
        get_source_map_json: () => JSON.stringify([{ node_id: 7, start: 10 }]),
        get_proj_node_json: () => 'null',
        handle_text_intent_checked: (
          _handle: number,
          from: number,
          deleteLen: number,
          insert: string,
          _timestampMs: number,
        ) => {
          calls.push({ from, deleteLen, insert });
          return calls.length === 1;
        },
      };
      const bridge = new CrdtBridge(123, crdt as any);
      let broadcasts = 0;
      bridge.setBroadcast(() => {
        broadcasts += 1;
      });

      bridge.handleLeafEdit(7, [
        { from: 0, to: 0, insert: 'a' },
        { from: 999, to: 1000, insert: 'b' },
      ]);
      await new Promise<void>((resolve) => requestAnimationFrame(() => resolve()));

      return { broadcasts, calls };
    });

    expect(result.broadcasts).toBe(1);
    expect(result.calls).toEqual([
      { from: 10, deleteLen: 0, insert: 'a' },
      { from: 1010, deleteLen: 1, insert: 'b' },
    ]);
  });

  test('does not broadcast when the first splice fails', async ({ page }) => {
    await page.goto('/', { waitUntil: 'domcontentloaded' });

    const result = await page.evaluate(async () => {
      const { CrdtBridge } = await import('/src/bridge.ts');
      const calls: Array<{ from: number; deleteLen: number; insert: string }> = [];
      const crdt = {
        get_source_map_json: () => JSON.stringify([{ node_id: 7, start: 10 }]),
        get_proj_node_json: () => 'null',
        handle_text_intent_checked: (
          _handle: number,
          from: number,
          deleteLen: number,
          insert: string,
          _timestampMs: number,
        ) => {
          calls.push({ from, deleteLen, insert });
          return false;
        },
      };
      const bridge = new CrdtBridge(123, crdt as any);
      let broadcasts = 0;
      bridge.setBroadcast(() => {
        broadcasts += 1;
      });

      bridge.handleLeafEdit(7, [{ from: 0, to: 1, insert: 'a' }]);
      await new Promise<void>((resolve) => requestAnimationFrame(() => resolve()));

      return { broadcasts, calls };
    });

    expect(result.broadcasts).toBe(0);
    expect(result.calls).toEqual([{ from: 10, deleteLen: 1, insert: 'a' }]);
  });
});
