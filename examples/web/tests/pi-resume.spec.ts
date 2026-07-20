import path from 'node:path';
import { test, expect } from '@playwright/test';

async function loadFixture(page: import('@playwright/test').Page): Promise<string> {
  const result = await page.evaluate(async () => {
    const response = await fetch('/tests/fixtures/pi-session-v3.jsonl');
    return { ok: response.ok, text: await response.text() };
  });
  expect(result.ok).toBe(true);
  return result.text;
}

test.beforeEach(async ({ page }) => {
  await page.goto('/resume.html');
  await expect(page.locator('.pilot-workbench')).toBeVisible();
});

test.describe('PKE workbench', () => {
  test('synchronizes Timeline, Conversation, and Evidence without provider or storage access', async ({ page }) => {
    await page.goto('/resume.html');

    await expect(page.locator('.pilot-condition-gate')).toHaveCount(0);
    await expect(page.locator('.pilot-wordmark, .pilot-topbar, .pilot-session-header')).toHaveCount(0);
    await expect(page.locator('.pilot-session-toolbar')).toBeVisible();
    await expect(page.getByRole('button', { name: 'Assign extractive Resume' })).toHaveCount(0);
    await expect(page.locator('#session-file')).toBeEnabled();
    await expect(page.locator('#branch-select')).toBeEnabled();
    await expect(page.locator('#branch-select')).toHaveValue('0000000f');
    await expect(page.locator('.pilot-workbench')).toBeVisible();
    await expect(page.locator('.pilot-session-status')).toContainText('Example');
    await expect(page.locator('#prepare-analysis')).toHaveCount(0);
    await expect(page.getByRole('heading', { name: 'Use the local extractive Resume first' })).toHaveCount(0);

    await page.getByLabel('Open session file').setInputFiles(
      path.resolve('tests/fixtures/pi-session-v3.jsonl'),
    );
    await expect(page.locator('#session-file')).toBeEnabled();
    await expect(page.locator('#branch-select')).toBeEnabled();
    await expect(page.locator('#branch-select')).toHaveValue('');
    await expect(page.locator('.pilot-shell')).toBeVisible();
    await expect(page.locator('.pilot-workbench-empty')).toBeVisible();
    await expect(page.getByText('No path selected')).toBeVisible();
    await expect(page.locator('.pilot-resume-empty')).toHaveCount(0);

    await page.locator('#branch-select').selectOption('0000000f');
    await expect(page.locator('#branch-select')).toHaveValue('0000000f');
    await expect(page.locator('.pilot-workbench-empty')).toHaveCount(0);
    await expect(page.getByRole('heading', { name: 'canopy session', exact: true })).toHaveClass(
      /visually-hidden/,
    );
    await expect(page.locator('#pilot-resume-view, .pilot-question')).toHaveCount(0);
    for (const label of ['Current direction', 'Return point', 'Latest observation', 'Needs inspection']) {
      await expect(page.getByText(label, { exact: true })).toHaveCount(0);
    }
    await expect(page.locator('.pilot-workbench-heading')).toHaveCount(0);
    await expect(page.getByText('Selection—not scrolling—keeps Timeline, Conversation, and Evidence synchronized.')).toHaveCount(0);
    const sessionDetails = page.getByText('Details', { exact: true });
    await expect(sessionDetails).toBeVisible();
    await expect(page.getByText('Working directory', { exact: true })).toBeHidden();
    await sessionDetails.click();
    await expect(page.getByText('Working directory', { exact: true })).toBeVisible();
    await sessionDetails.click();
    await expect(page.getByRole('heading', { name: 'Resume view' })).toHaveCount(0);
    await expect(page.getByRole('heading', { name: 'Timeline' })).toBeVisible();
    await expect(page.getByRole('heading', { name: 'Conversation', exact: true })).toBeVisible();
    const inspectorHeading = page.getByRole('heading', { name: 'Evidence', exact: true });
    await expect(inspectorHeading).toBeVisible();
    await expect(page.locator('.pilot-conversation-list > li')).toHaveCount(16);
    await expect(page.locator('.pilot-conversation-list > li[data-role="user"]')).toHaveCount(3);
    await expect(page.locator('.pilot-conversation-list > li[data-role="assistant"]')).toHaveCount(4);
    await expect(page.locator('.pilot-conversation-list > li[data-role="tool"]')).toHaveCount(4);
    await expect(page.locator('.pilot-conversation-list > li[data-role="checkpoint"]')).toHaveCount(4);
    const firstUserMessage = page.locator('[data-entry-id="00000001"] .pilot-chat-bubble');
    await expect(firstUserMessage).toHaveCSS('background-color', 'rgb(240, 227, 243)');
    await expect(firstUserMessage).toHaveCSS('color', 'rgb(91, 32, 104)');
    const firstAssistantMessage = page.locator('[data-entry-id="00000002"]');
    await expect(firstAssistantMessage.locator('.pilot-chat-bubble')).toHaveCSS(
      'background-color',
      'rgb(255, 255, 255)',
    );
    await expect(firstAssistantMessage.locator('.pilot-chat-tool-call')).toContainText('read');
    await expect(firstAssistantMessage.locator('.pilot-chat-tool-call')).toContainText('Result recorded');
    const firstToolResult = page.locator('[data-entry-id="00000003"] .pilot-chat-bubble');
    await expect(firstToolResult).toHaveCSS('background-color', 'rgb(255, 246, 184)');
    await expect(firstToolResult).toContainText('Result for read requested in source 00000002');
    const failedToolResult = page.locator('[data-entry-id="0000000b"] .pilot-chat-bubble');
    await expect(failedToolResult).toHaveCSS('background-color', 'rgb(243, 192, 217)');
    await expect(failedToolResult).toHaveCSS('color', 'rgb(123, 36, 78)');
    await expect(page.locator('.pilot-conversation-scope')).toHaveCount(0);
    await expect(page.locator('.pilot-phase')).toHaveCount(3);
    const phaseToggles = page.locator('.pilot-phase-toggle');
    await expect(phaseToggles.nth(0).locator('i')).toHaveText('−');
    await expect(phaseToggles.nth(1).locator('i')).toHaveText('+');
    await expect(phaseToggles.nth(2).locator('i')).toHaveText('+');
    await expect(page.evaluate(() => {
      const toggles = [...document.querySelectorAll<HTMLElement>('.pilot-phase-toggle')];
      const indicators = toggles.map(toggle => {
        const indicator = toggle.querySelector<HTMLElement>('i');
        const time = toggle.querySelector<HTMLElement>('time');
        if (indicator === null || time === null) return undefined;
        const toggleBox = toggle.getBoundingClientRect();
        const indicatorBox = indicator.getBoundingClientRect();
        const timeBox = time.getBoundingClientRect();
        return {
          left: indicatorBox.left,
          inside: indicatorBox.left >= timeBox.right &&
            indicatorBox.right <= toggleBox.right &&
            indicatorBox.top >= toggleBox.top &&
            indicatorBox.bottom <= toggleBox.bottom,
          trailingGap: toggleBox.right - indicatorBox.right,
        };
      });
      if (indicators.some(indicator => indicator === undefined)) return false;
      const defined = indicators.filter(indicator => indicator !== undefined);
      return defined.every(indicator => indicator.inside && indicator.trailingGap <= 16) &&
        defined.every(indicator => Math.abs(indicator.left - defined[0]!.left) <= 1);
    })).resolves.toBe(true);
    const conversation = page.getByRole('listbox', { name: 'Recorded conversation' });
    const toolResultOption = conversation.locator('[data-entry-id="00000003"]');
    await toolResultOption.click();
    await expect(toolResultOption).toBeFocused();
    await expect(toolResultOption).toHaveAttribute('aria-selected', 'true');
    await expect(page.locator('#source-00000003')).toHaveAttribute('aria-current', 'true');
    await page.locator('.pilot-inspector-tabs').getByRole('tab', { name: 'Evidence' }).click();
    await expect(page.locator('.pilot-evidence-copy')).toContainText('read completed');
    await toolResultOption.press('ArrowDown');
    const nextAssistantOption = conversation.locator('[data-entry-id="00000004"]');
    await expect(nextAssistantOption).toBeFocused();
    await expect(nextAssistantOption).toHaveAttribute('aria-selected', 'true');
    await nextAssistantOption.press('Home');
    await expect(conversation.locator('[data-entry-id="00000001"]')).toBeFocused();
    await page.getByRole('tab', { name: 'Normalized record' }).click();
    await expect(page.locator('.pilot-evidence-normalized')).toContainText('"id": "00000001"');
    await page.getByRole('tab', { name: 'Readable' }).click();
    await page.getByRole('button', { name: /Phase 02/ }).click();
    await page.locator('#source-0000000b button').click();
    await expect(page.locator('#source-0000000b')).toHaveAttribute('aria-current', 'true');
    await expect(page.locator('.pilot-evidence-copy')).toContainText('test failed');
    await expect(page.locator('.pilot-operation-relation')).toContainText(
      'Result for test requested by source entry 0000000a',
    );
    await expect(page.locator('.pilot-conversation-list > li[data-selected="true"]')).toContainText(
      'The first comparison fixture was incomplete',
    );
    await expect(page.evaluate(async () => ({
      local: Object.keys(localStorage),
      session: Object.keys(sessionStorage),
      databases: (await indexedDB.databases()).map(database => database.name),
    }))).resolves.toEqual({ local: [], session: [], databases: [] });

    await page.getByRole('button', { name: 'Forget session' }).click();
    await expect(page.getByRole('button', { name: 'Forget session' })).toHaveCount(0);
    await expect(page.locator('#session-file')).toBeEnabled();
    await expect(page.locator('.pilot-workbench')).toBeVisible();
    await expect(page.locator('.pilot-session-status')).toContainText('Example restored');
    await page.reload();
    await expect(page.locator('.pilot-workbench')).toBeVisible();
    await expect(page.getByRole('button', { name: 'Assign exactly one first view' })).toHaveCount(0);
  });

  test('supports ordinary chat without attaching activity history', async ({ page }) => {
    const postedRequests: unknown[] = [];
    page.on('request', request => {
      if (new URL(request.url()).pathname !== '/api/pi-resume-chat' || request.method() !== 'POST') return;
      postedRequests.push(request.postDataJSON());
    });
    await page.goto('/resume.html');
    const chat = page.locator('.pilot-source-chat');
    const prompt = chat.getByLabel('Chat message');
    await expect(prompt).toBeEnabled();
    await expect(chat.getByRole('button', { name: 'No history' })).toHaveAttribute(
      'aria-pressed',
      'true',
    );
    await expect(chat).toContainText('No activity history will be sent');
    await prompt.fill('What is a projectional editor?');
    await chat.getByText('Outbound request preview').click();
    await expect(chat.locator('.pilot-chat-payload pre')).toContainText('"scope": "none"');
    await chat.getByRole('button', { name: 'Send' }).click();
    const assistantMessage = chat.locator('.ai-message[data-role="assistant"]');
    await expect(assistantMessage).toContainText('without attached activity history');
    await expect(assistantMessage.locator('strong')).toHaveText('Context:');
    await expect(assistantMessage.locator('li')).toHaveCount(2);
    await expect(assistantMessage).not.toContainText('**Context:**');
    expect(postedRequests).toHaveLength(1);
    expect(postedRequests[0]).toMatchObject({
      context: { scope: 'none' },
      sources: [],
    });

    await prompt.fill('Can I ask a follow-up?');
    await chat.getByText('Outbound request preview').click();
    await expect(chat.locator('.pilot-chat-payload pre')).not.toContainText('step-start');
    await chat.getByRole('button', { name: 'Send' }).click();
    await expect(chat.locator('.ai-message[data-role="assistant"]').last()).toContainText(
      'Can I ask a follow-up?',
    );
    expect(postedRequests).toHaveLength(2);
    expect(JSON.stringify(postedRequests[1])).not.toContain('step-start');
    expect(postedRequests[1]).toMatchObject({
      messages: [
        { role: 'user', parts: [{ type: 'text', text: 'What is a projectional editor?' }] },
        { role: 'assistant', parts: [{ type: 'text' }] },
        { role: 'user', parts: [{ type: 'text', text: 'Can I ask a follow-up?' }] },
      ],
    });
  });

  test('retains sensitive-pattern excerpts and warns before explicit egress', async ({ page }) => {
    const fixture = await loadFixture(page);
    await page.goto('/resume.html');
    const retainedText = 'api_key: fixture-only-value for the retained product direction';
    await page.getByLabel('Open session file').setInputFiles({
      name: 'sensitive-warning-session.jsonl',
      mimeType: 'application/json',
      buffer: Buffer.from(fixture.replace('restore the Canopy product direction', retainedText)),
    });
    await expect(page.locator('.pilot-session-status')).toContainText('import notes');
    await page.locator('#branch-select').selectOption('0000000f');
    const importNotes = page.locator('#diagnostics');
    await expect(importNotes).not.toHaveAttribute('open', '');
    await expect(importNotes.getByText('Import notes', { exact: true })).toBeVisible();
    await expect(page.locator('#diagnostics-list')).toBeHidden();
    await importNotes.locator('summary').click();
    await expect(importNotes).toHaveAttribute('open', '');
    await expect(page.locator('#diagnostics-list')).toContainText('egress warning');
    await page.locator('.pilot-event-list button').filter({ hasText: 'Human intent' }).click();
    await expect(page.locator('.pilot-conversation')).toContainText(retainedText);

    const chat = page.locator('.pilot-source-chat');
    await chat.getByRole('button', { name: 'Add current moment' }).click();
    await expect(chat.locator('.pilot-chat-sensitive-warning')).toContainText(
      'will be sent because this context was explicitly attached',
    );
    await chat.getByLabel('Chat message').fill('Use the explicitly attached source.');
    await chat.getByText('Outbound request preview').click();
    await expect(chat.locator('.pilot-chat-payload pre')).toContainText(retainedText);
  });

  test('attaches only selected exact sources to a chat turn', async ({ page }) => {
    const postedRequests: unknown[] = [];
    page.on('request', request => {
      if (new URL(request.url()).pathname !== '/api/pi-resume-chat' || request.method() !== 'POST') return;
      postedRequests.push(request.postDataJSON());
    });
    await page.goto('/resume.html');
    const chat = page.locator('.pilot-source-chat');
    const prompt = chat.getByLabel('Chat message');
    const question = 'What changed across these exact moments?';

    await expect(page.locator('.pilot-current-work')).toHaveCount(0);
    await expect(chat).toContainText('Test model · local relay');
    await expect(prompt).toBeEnabled();
    await chat.getByRole('button', { name: 'Add current moment' }).click();
    await page.locator('.pilot-conversation-list [data-entry-id="0000000e"]').click();
    await chat.getByRole('button', { name: 'Add current moment' }).click();
    await expect(chat).toContainText('Next message context · selected · 2 exact sources');
    await expect(chat).toContainText('source 00000001 · Human intent');
    await expect(chat).toContainText('source 0000000e · Assistant requested edit');
    await prompt.fill(question);
    await chat.getByText('Outbound request preview').click();
    await expect(chat.locator('.pilot-chat-payload pre')).toContainText(
      '"sessionId": "pke-demo-session-001"',
    );
    await expect(chat.locator('.pilot-chat-payload pre')).toContainText(
      '"kind": "assistant-claim"',
    );
    await expect(prompt).toBeEnabled();
    await chat.getByRole('button', { name: 'Send' }).click();

    const userMessage = chat.locator('.ai-message[data-role="user"]');
    const assistantMessage = chat.locator('.ai-message[data-role="assistant"]');
    await expect(userMessage).toContainText(question);
    await expect(userMessage).toHaveAttribute('data-origin', 'person-authored');
    await expect(userMessage).toHaveAttribute('data-derivation', 'recorded');
    await expect(assistantMessage).toContainText('[source:00000001]');
    await expect(assistantMessage.locator('strong')).toHaveText('Context:');
    await expect(assistantMessage.locator('li')).toHaveCount(2);
    await expect(assistantMessage).toHaveAttribute('data-origin', 'canopy-system');
    await expect(assistantMessage).toHaveAttribute('data-derivation', 'model-inference');
    await expect(assistantMessage).toHaveAttribute('data-model', 'pke-chat-fake-v1');
    const inspectorTabs = page.locator('.pilot-inspector-tabs');
    await prompt.fill('Draft survives the Evidence tab.');
    await inspectorTabs.getByRole('tab', { name: 'Evidence' }).click();
    await expect(chat).toBeHidden();
    await expect(chat.locator('.ai-message')).toHaveCount(2);
    await inspectorTabs.getByRole('tab', { name: 'Discuss' }).click();
    await expect(chat).toBeVisible();
    await expect(chat.locator('.ai-message')).toHaveCount(2);
    await expect(prompt).toHaveValue('Draft survives the Evidence tab.');
    await prompt.fill('');
    expect(postedRequests).toHaveLength(1);
    expect(postedRequests[0]).toMatchObject({
      messages: [{ role: 'user', parts: [{ type: 'text', text: question }] }],
      context: {
        scope: 'selected',
        sessionId: 'pke-demo-session-001',
        leafId: '0000000f',
      },
      sources: [
        { source: { sessionId: 'pke-demo-session-001', entryId: '00000001' } },
        { source: { sessionId: 'pke-demo-session-001', entryId: '0000000e' } },
      ],
    });
    expect(JSON.stringify(postedRequests[0])).not.toContain('00000003');

    await expect(assistantMessage.getByRole('button', {
      name: 'Open cited source 00000001',
    })).toBeVisible();
    await assistantMessage.getByRole('button', { name: 'Open cited source 00000001' }).click();
    await expect(page.locator('.pilot-conversation-list > li[data-selected="true"]')).toHaveAttribute(
      'data-entry-id',
      '00000001',
    );
    await chat.getByText('Next message context · selected · 2 exact sources').click();
    await chat.getByRole('button', {
      name: 'Remove Assistant requested edit from chat context',
    }).click();
    await expect(chat).toContainText('Next message context · selected · 1 exact source');
    await expect(chat.getByRole('button', {
      name: 'Remove Assistant requested edit from chat context',
    })).toHaveCount(0);
    await expect(page.evaluate(async () => ({
      local: Object.keys(localStorage),
      session: Object.keys(sessionStorage),
      databases: (await indexedDB.databases()).map(database => database.name),
    }))).resolves.toEqual({ local: [], session: [], databases: [] });

    await prompt.fill('Unsaved source-bound draft.');
    await page.locator('.pilot-conversation-list [data-entry-id="00000004"]').click();
    await chat.getByRole('button', { name: 'Add current moment' }).click();
    await expect(chat.locator('.ai-message')).toHaveCount(2);
    await expect(prompt).toHaveValue('Unsaved source-bound draft.');

    await page.locator('#branch-select').selectOption({ index: 2 });
    await expect(chat.locator('.ai-message')).toHaveCount(2);
    await expect(prompt).toHaveValue('Unsaved source-bound draft.');
    await expect(chat).toContainText('No activity history will be sent');

    await page.getByLabel('Open session file').setInputFiles(
      path.resolve('tests/fixtures/pi-session-v3.jsonl'),
    );
    await page.locator('#branch-select').selectOption('0000000f');
    await chat.getByRole('button', { name: 'Add current moment' }).click();
    await prompt.fill('Keep this conversation in tab memory only.');
    await chat.getByRole('button', { name: 'Send' }).click();
    await expect(chat.locator('.ai-message[data-role="assistant"]')).toBeVisible();
    await page.getByRole('button', { name: 'Forget session' }).click();
    await expect(chat.locator('.ai-message')).toHaveCount(0);
    await expect(chat).toContainText('No activity history will be sent');
  });

  test('explicitly attaches the whole current terminal path', async ({ page }) => {
    const postedRequests: unknown[] = [];
    page.on('request', request => {
      if (new URL(request.url()).pathname !== '/api/pi-resume-chat' || request.method() !== 'POST') return;
      postedRequests.push(request.postDataJSON());
    });
    await page.goto('/resume.html');
    const chat = page.locator('.pilot-source-chat');
    await chat.getByRole('button', { name: /Current path/ }).click();
    await chat.getByLabel('Chat message').fill('Look across the whole current path.');
    await chat.getByRole('button', { name: 'Send' }).click();
    await expect(chat.locator('.ai-message[data-role="assistant"]')).toContainText(
      'attached terminal path',
    );
    expect(postedRequests).toHaveLength(1);
    const request = postedRequests[0] as {
      context: { scope: string; leafId: string };
      sources: unknown[];
    };
    expect(request.context).toMatchObject({ scope: 'path', leafId: '0000000f' });
    expect(request.sources.length).toBeGreaterThan(8);
  });

  test('snapshots an in-flight turn when context for the next turn changes', async ({ page }) => {
    const postedRequests: unknown[] = [];
    page.on('request', request => {
      if (new URL(request.url()).pathname !== '/api/pi-resume-chat' || request.method() !== 'POST') return;
      postedRequests.push(request.postDataJSON());
    });
    await page.goto('/resume.html');
    const chat = page.locator('.pilot-source-chat');
    await chat.getByRole('button', { name: 'Add current moment' }).click();
    await chat.getByLabel('Chat message').fill('Finish with the context attached to this turn.');
    await chat.getByRole('button', { name: 'Send' }).click();
    await expect(chat.locator('.ai-message[data-role="user"]')).toContainText('Selected · 1 sources');

    await page.locator('.pilot-conversation-list [data-entry-id="0000000e"]').click();
    await chat.getByRole('button', { name: 'Add current moment' }).click();
    await expect(chat.locator('.ai-message[data-role="user"]')).toContainText('Selected · 1 sources');
    await expect(chat.locator('.ai-message[data-role="assistant"]')).toContainText('[source:00000001]');
    expect(postedRequests).toHaveLength(1);
    expect(postedRequests[0]).toMatchObject({
      context: { scope: 'selected', leafId: '0000000f' },
      sources: [{ source: { entryId: '00000001' } }],
    });
    await expect(chat.locator('.pilot-chat-error')).toHaveCount(0);
  });

  test('continues after a response is stopped without replaying abandoned context', async ({ page }) => {
    const postedRequests: unknown[] = [];
    page.on('request', request => {
      if (new URL(request.url()).pathname !== '/api/pi-resume-chat' || request.method() !== 'POST') return;
      postedRequests.push(request.postDataJSON());
    });
    await page.goto('/resume.html');
    const chat = page.locator('.pilot-source-chat');
    const prompt = chat.getByLabel('Chat message');
    await chat.getByRole('button', { name: 'Add current moment' }).click();
    await prompt.fill('Stop this source-bound response.');
    await chat.getByRole('button', { name: 'Send' }).click();
    await expect(chat.locator('.ai-message[data-role="user"]')).toBeVisible();
    await chat.getByRole('button', { name: 'Stop' }).click();
    await expect(chat.locator('.ai-message')).toHaveCount(0);
    await expect(prompt).toHaveValue('Stop this source-bound response.');
    await chat.getByRole('button', { name: 'No history' }).click();
    await prompt.fill('Answer this next message.');
    await chat.getByRole('button', { name: 'Send' }).click();
    await expect(chat.locator('.ai-message[data-role="assistant"]')).toContainText(
      'Answer this next message.',
    );
    expect(postedRequests).toHaveLength(2);
    expect(postedRequests[1]).toMatchObject({
      messages: [{ role: 'user', parts: [{ type: 'text', text: 'Answer this next message.' }] }],
      context: { scope: 'none' },
      sources: [],
    });
  });

  test('restores an unanswered message after a relay failure', async ({ page }) => {
    let failNextRequest = true;
    await page.route('**/api/pi-resume-chat', async route => {
      if (route.request().method() !== 'POST' || !failNextRequest) {
        await route.continue();
        return;
      }
      failNextRequest = false;
      await route.fulfill({
        status: 502,
        contentType: 'application/json',
        body: JSON.stringify({ message: 'Fixture relay failure.' }),
      });
    });
    await page.goto('/resume.html');
    const chat = page.locator('.pilot-source-chat');
    const prompt = chat.getByLabel('Chat message');
    await prompt.fill('Restore this failed message.');
    await chat.getByRole('button', { name: 'Send' }).click();
    await expect(chat.locator('.pilot-chat-error')).toBeVisible();
    await expect(chat.locator('.ai-message')).toHaveCount(0);
    await expect(prompt).toHaveValue('Restore this failed message.');
    await chat.getByRole('button', { name: 'Dismiss' }).click();
    await chat.getByRole('button', { name: 'Send' }).click();
    await expect(chat.locator('.ai-message[data-role="assistant"]')).toContainText(
      'Restore this failed message.',
    );
  });

  test('clears and aborts chat as soon as a new import starts', async ({ page }) => {
    await page.goto('/resume.html');
    const chat = page.locator('.pilot-source-chat');
    await chat.getByLabel('Chat message').fill('Do not survive a new import.');
    await chat.getByRole('button', { name: 'Send' }).click();
    await expect(chat.locator('.ai-message[data-role="user"]')).toBeVisible();
    await page.getByLabel('Open session file').setInputFiles(
      path.resolve('tests/fixtures/pi-session-v3.jsonl'),
    );
    await expect(chat).toHaveCount(0);
    await page.locator('#branch-select').selectOption('0000000f');
    await expect(page.locator('.pilot-source-chat .ai-message')).toHaveCount(0);
    await page.waitForTimeout(500);
    await expect(page.locator('.pilot-source-chat .ai-message')).toHaveCount(0);
  });

  test('fails closed at the local source-chat relay boundary', async ({ page }) => {
    await page.goto('/resume.html');
    const status = await page.request.get('/api/pi-resume-chat/status');
    expect(status.status()).toBe(200);
    await expect(status.json()).resolves.toMatchObject({
      available: true,
      provider: 'fake',
      model: 'pke-chat-fake-v1',
      localRelay: true,
    });
    expect((await page.request.get('/api/pi-resume-chat')).status()).toBe(405);
    expect((await page.request.post('/api/pi-resume-chat', {
      headers: { origin: 'https://example.invalid' },
      data: { messages: [], sources: [] },
    })).status()).toBe(403);
    const invalid = await page.evaluate(async () => {
      const response = await fetch('/api/pi-resume-chat', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ messages: [], sources: [] }),
      });
      return { status: response.status, cache: response.headers.get('cache-control') };
    });
    expect(invalid).toEqual({ status: 400, cache: 'no-store' });
  });

  test('adapts the synchronized workbench to mobile view tabs without losing context', async ({ page }) => {
    await page.setViewportSize({ width: 390, height: 844 });
    await page.goto('/resume.html');
    await page.getByLabel('Open session file').setInputFiles(
      path.resolve('tests/fixtures/pi-session-v3.jsonl'),
    );
    await page.locator('#branch-select').selectOption('0000000f');

    const timeline = page.locator('.pilot-timeline');
    const conversation = page.locator('.pilot-conversation');
    const evidence = page.locator('.pilot-evidence');
    await expect(conversation).toBeVisible();
    await expect(timeline).toBeHidden();
    await expect(evidence).toBeHidden();
    await expect(page.locator('.pilot-workbench')).toBeVisible();
    await expect(page.locator('#pilot-resume-view, .pilot-question')).toHaveCount(0);

    await page.getByRole('button', { name: 'Timeline', exact: true }).click();
    await expect(timeline).toBeVisible();
    await page.locator('#source-00000002 button').click();
    await expect(page.locator('.pilot-conversation-list [data-entry-id="00000002"]'))
      .toHaveAttribute('aria-selected', 'true');
    await page.getByRole('button', { name: 'Timeline', exact: true }).click();
    await page.getByRole('button', { name: /Phase 03/ }).click();
    await page.locator('#source-0000000e button').click();
    await page.getByRole('button', { name: 'Evidence', exact: true }).click();
    await expect(evidence).toBeVisible();
    await evidence.locator('.pilot-inspector-tabs').getByRole('tab', { name: 'Evidence' }).click();
    await expect(evidence.getByText('0000000e', { exact: true })).toBeVisible();
    await expect(page.evaluate(() => document.documentElement.scrollWidth)).resolves.toBeLessThanOrEqual(390);
  });

  test('fully frames desktop scrollers and removes nested scrolling on narrow screens', async ({ page }) => {
    await page.setViewportSize({ width: 1024, height: 768 });
    await page.goto('/resume.html');

    const desktopShell = await page.locator('.pilot-shell').boundingBox();
    const desktopToolbar = await page.locator('.pilot-session-toolbar').boundingBox();
    expect(desktopShell).toEqual({ x: 0, y: 0, width: 1024, height: 768 });
    expect(desktopToolbar?.height ?? Number.POSITIVE_INFINITY).toBeLessThanOrEqual(52);
    await expect(page.evaluate(() => ({
      width: document.documentElement.scrollWidth,
      height: document.documentElement.scrollHeight,
    }))).resolves.toEqual({ width: 1024, height: 768 });

    const desktopBounds = await page.locator('.pilot-workbench-grid').boundingBox();
    expect(desktopBounds).not.toBeNull();
    expect((desktopBounds?.y ?? 0) + (desktopBounds?.height ?? Number.POSITIVE_INFINITY))
      .toBeLessThanOrEqual(768);
    expect(desktopBounds?.height ?? 0).toBeGreaterThanOrEqual(590);
    await expect(page.locator('.pilot-timeline')).toBeVisible();
    await expect(page.locator('.pilot-conversation')).toBeVisible();
    await expect(page.locator('.pilot-evidence')).toBeVisible();
    await expect(page.locator('.pilot-conversation')).toHaveCSS('overflow-y', 'auto');

    await page.setViewportSize({ width: 390, height: 844 });
    const mobileShell = await page.locator('.pilot-shell').boundingBox();
    const mobileToolbar = await page.locator('.pilot-session-toolbar').boundingBox();
    expect(mobileShell?.x).toBe(0);
    expect(mobileShell?.width).toBe(390);
    expect(mobileToolbar?.height ?? Number.POSITIVE_INFINITY).toBeLessThanOrEqual(120);
    await expect(page.locator('.pilot-conversation')).toBeVisible();
    await expect(page.locator('.pilot-conversation')).toHaveCSS('overflow-y', 'visible');
    await expect(page.evaluate(() => {
      const conversation = document.querySelector<HTMLElement>('.pilot-conversation');
        if (conversation === null) return false;
      return conversation.scrollHeight <= conversation.clientHeight + 1 &&
        document.documentElement.scrollWidth <= window.innerWidth;
    })).resolves.toBe(true);

    await page.getByRole('button', { name: 'Timeline', exact: true }).click();
    await page.locator('#source-00000001 button').click();
    const revealedSource = page.locator('[data-entry-id="00000001"]');
    await expect(revealedSource).toBeVisible();
    await expect(page.evaluate(() => {
      const toolbar = document.querySelector<HTMLElement>('.pilot-session-toolbar');
      const source = document.querySelector<HTMLElement>('[data-entry-id="00000001"]');
      if (toolbar === null || source === null) return false;
      const toolbarBox = toolbar.getBoundingClientRect();
      const sourceBox = source.getBoundingClientRect();
      return sourceBox.top >= toolbarBox.bottom && sourceBox.bottom <= window.innerHeight;
    })).resolves.toBe(true);
  });

  test('keeps every conversation role contained and non-overlapping across widths', async ({ page }) => {
    for (const viewport of [
      { width: 1440, height: 1000 },
      { width: 901, height: 768 },
      { width: 390, height: 844 },
      { width: 320, height: 700 },
    ]) {
      await page.setViewportSize(viewport);
      await page.goto('/resume.html');
      await expect(page.evaluate(() => {
        const panel = document.querySelector<HTMLElement>('.pilot-conversation');
        const heading = panel?.querySelector<HTMLElement>('.pilot-panel-heading');
        const list = panel?.querySelector<HTMLOListElement>('.pilot-conversation-list');
        const selected = list?.querySelector<HTMLElement>('[data-selected="true"]');
        const bodyText = list?.querySelector<HTMLElement>('.pilot-chat-bubble > p');
        const author = list?.querySelector<HTMLElement>('.pilot-chat-author');
        const metadata = list?.querySelector<HTMLElement>('.pilot-chat-meta > div > span');
        const time = list?.querySelector<HTMLElement>('.pilot-chat-meta time');
        const footer = list?.querySelector<HTMLElement>('.pilot-chat-bubble > footer');
        if (
          panel === null || heading === null || list === null || selected === null ||
          bodyText === null || author === null || metadata === null || time === null || footer === null
        ) return false;
        const listBox = list.getBoundingClientRect();
        const items = [...list.children] as HTMLElement[];
        const contained = items.every(item => {
          const turn = item.querySelector<HTMLElement>('.pilot-chat-turn');
          const bubble = item.querySelector<HTMLElement>('.pilot-chat-bubble');
          if (turn === null || bubble === null) return false;
          return [turn, bubble].every(element => {
            const box = element.getBoundingClientRect();
            return box.left >= listBox.left - 1 && box.right <= listBox.right + 1 &&
              element.scrollWidth <= element.clientWidth + 1;
          }) && window.getComputedStyle(item).contentVisibility === 'visible';
        });
        const nonOverlapping = items.slice(0, -1).every((item, index) =>
          item.getBoundingClientRect().bottom <= items[index + 1]!.getBoundingClientRect().top + 1
        );
        const bodySize = Number.parseFloat(window.getComputedStyle(bodyText).fontSize);
        const authorSize = Number.parseFloat(window.getComputedStyle(author).fontSize);
        const metadataSize = Number.parseFloat(window.getComputedStyle(metadata).fontSize);
        const footerSize = Number.parseFloat(window.getComputedStyle(footer).fontSize);
        const restrainedHierarchy = bodySize >= 16 && bodySize <= 17 &&
          bodySize - authorSize >= 4 && metadataSize >= 10 && footerSize >= 10 &&
          window.getComputedStyle(time).fontFamily.includes('monospace');
        const visibleTurns = items.filter(item => {
          const box = item.getBoundingClientRect();
          return box.top < window.innerHeight && box.bottom > heading.getBoundingClientRect().bottom;
        }).length;
        const adequateDensity = window.innerWidth < 1400 || visibleTurns >= 5;
        return contained && nonOverlapping && restrainedHierarchy && adequateDensity &&
          list.scrollWidth <= list.clientWidth + 1 &&
          selected.getBoundingClientRect().top >= heading.getBoundingClientRect().bottom - 1 &&
          document.documentElement.scrollWidth <= window.innerWidth;
      })).resolves.toBe(true);
      if (viewport.width <= 900) {
        await expect(page.locator('.pilot-session-toolbar')).toHaveCSS('position', 'static');
      }
    }
  });

  test('validates bounded source-chat context without promoting model output', async ({ page }) => {
    const fixture = await loadFixture(page);
    const result = await page.evaluate(async ({ fixture }) => {
      const core = await import('/src/pi-resume-core.ts');
      const chat = await import('/src/pi-resume-chat-protocol.ts');
      const reduced = core.reducePiSession(core.parsePiSessionJsonl(fixture));
      const projection = core.projectResume(reduced, '0000000f');
      const human = projection.chronology.find(item => item.source.entryId === '00000001');
      const tool = projection.chronology.find(item => item.source.entryId === '00000003');
      if (human === undefined || tool === undefined) throw new Error('Missing chat fixtures.');
      const sources = [
        chat.pkeChatSourceFromActivity(human),
        chat.pkeChatSourceFromActivity(tool),
      ];
      const messages = [{
        id: 'user-1',
        role: 'user' as const,
        parts: [{ type: 'text' as const, text: 'What happened here?' }],
      }];
      const context = {
        scope: 'selected' as const,
        sessionId: projection.sessionId,
        leafId: projection.leafId,
      };
      const envelope = chat.parsePkeChatEnvelope({ messages, context, sources });
      const opaqueToolCallId = 'provider.call|segment$=fixture';
      const opaqueToolEnvelope = chat.parsePkeChatEnvelope({
        messages,
        context,
        sources: [
          sources[0],
          {
            ...sources[1],
            origin: { ...sources[1].origin, toolCallId: opaqueToolCallId },
          },
        ],
      });
      const noHistoryEnvelope = chat.parsePkeChatEnvelope({
        messages,
        context: { scope: 'none' },
        sources: [],
      });
      const validatedMessages = chat.validatePkeChatMessages(messages);
      const prompt = chat.buildPkeChatSystemPrompt(envelope.context, envelope.sources);
      const noHistoryPrompt = chat.buildPkeChatSystemPrompt(
        noHistoryEnvelope.context,
        noHistoryEnvelope.sources,
      );
      const textOnlyHistory = chat.pkeChatTextMessages([
        messages[0],
        {
          id: 'assistant-1',
          role: 'assistant',
          metadata: { provider: 'must-not-egress' },
          parts: [
            { type: 'step-start' },
            { type: 'text', text: 'Rendered answer.', state: 'done' },
          ],
        },
        {
          id: 'user-2',
          role: 'user',
          parts: [{ type: 'text', text: 'Follow-up.' }],
        },
      ]);
      const capture = (action: () => unknown): string => {
        try {
          action();
          return '';
        } catch (error) {
          return error instanceof Error ? error.message : String(error);
        }
      };
      return {
        sourceIds: envelope.sources.map(source => source.source.entryId),
        sourceOrigins: envelope.sources.map(source => source.origin),
        opaqueToolCallId: opaqueToolEnvelope.sources[1]?.origin.kind === 'observed-tool'
          ? opaqueToolEnvelope.sources[1].origin.toolCallId
          : undefined,
        promptHasCitationContract: prompt.includes('[source:ENTRY_ID]'),
        promptHasQuotedSources:
          prompt.includes('[source:00000001]') && prompt.includes('[source:00000003]'),
        noHistoryAccepted:
          noHistoryEnvelope.sources.length === 0 &&
          noHistoryPrompt.includes('No activity history is attached'),
        normalizedHistory: textOnlyHistory,
        messagesPreserved: validatedMessages === messages,
        providerOptions: chat.PKE_CHAT_DEEPSEEK_PROVIDER_OPTIONS,
        immutable:
          Object.isFrozen(envelope) &&
          Object.isFrozen(envelope.context) &&
          Object.isFrozen(envelope.sources) &&
          envelope.sources.every(source =>
            Object.isFrozen(source) &&
            Object.isFrozen(source.source) &&
            Object.isFrozen(source.origin) &&
            Object.isFrozen(source.derivation)),
        noSources: capture(() => chat.parsePkeChatEnvelope({
          messages,
          context,
          sources: [],
        })),
        duplicates: capture(() => chat.parsePkeChatEnvelope({
          messages,
          context,
          sources: [sources[0], sources[0]],
        })),
        modelSource: capture(() => chat.parsePkeChatEnvelope({
          messages,
          context,
          sources: [{
            ...sources[0],
            origin: { kind: 'canopy-system' },
            derivation: {
              kind: 'model-inference',
              modelIdentity: 'fixture-model',
              analysisVersion: '1',
            },
          }],
        })),
        controlToolCallId: capture(() => chat.parsePkeChatEnvelope({
          messages,
          context,
          sources: [
            sources[0],
            {
              ...sources[1],
              origin: { ...sources[1].origin, toolCallId: 'provider-call\nforged' },
            },
          ],
        })),
        consecutiveUsersAccepted: capture(() => chat.validatePkeChatMessages([
          ...messages,
          {
            id: 'user-2',
            role: 'user',
            parts: [{ type: 'text', text: 'Another user turn.' }],
          },
        ])),
        consecutiveAssistants: capture(() => chat.validatePkeChatMessages([
          ...messages,
          {
            id: 'assistant-1',
            role: 'assistant',
            parts: [{ type: 'text', text: 'First answer.' }],
          },
          {
            id: 'assistant-2',
            role: 'assistant',
            parts: [{ type: 'text', text: 'Second answer.' }],
          },
          {
            id: 'user-2',
            role: 'user',
            parts: [{ type: 'text', text: 'Continue.' }],
          },
        ])),
      };
    }, { fixture });

    expect(result).toEqual({
      sourceIds: ['00000001', '00000003'],
      sourceOrigins: [
        { kind: 'recorded-human' },
        { kind: 'observed-tool', outcome: 'success', toolCallId: 'call-read-docs' },
      ],
      opaqueToolCallId: 'provider.call|segment$=fixture',
      promptHasCitationContract: true,
      promptHasQuotedSources: true,
      noHistoryAccepted: true,
      normalizedHistory: [
        {
          id: 'user-1',
          role: 'user',
          parts: [{ type: 'text', text: 'What happened here?' }],
        },
        {
          id: 'assistant-1',
          role: 'assistant',
          parts: [{ type: 'text', text: 'Rendered answer.' }],
        },
        {
          id: 'user-2',
          role: 'user',
          parts: [{ type: 'text', text: 'Follow-up.' }],
        },
      ],
      messagesPreserved: true,
      providerOptions: { deepseek: { thinking: { type: 'disabled' } } },
      immutable: true,
      noSources: 'Selected context needs between 1 and 8 exact sources.',
      duplicates: 'Chat sources must be unique.',
      modelSource: 'Model-inferred content cannot be sent as selected source evidence in this slice.',
      controlToolCallId: 'tool call identity is invalid.',
      consecutiveUsersAccepted: '',
      consecutiveAssistants: 'Assistant chat messages cannot be consecutive.',
    });
  });

  test('preserves deterministic core and fails closed on invalid input', async ({ page }) => {
    const fixture = await loadFixture(page);
    const result = await page.evaluate(async ({ fixture }) => {
      const core = await import('/src/pi-resume-core.ts');
      const parsed = core.parsePiSessionJsonl(fixture);
      const reduced = core.reducePiSession(parsed);
      const projection = core.projectResume(reduced, '0000000f');
      const replay = core.reducePiSession({
        ...parsed,
        entries: [...parsed.entries, parsed.entries[0]],
      });

      const throws = (action: () => unknown): string => {
        try {
          action();
          return '';
        } catch (error) {
          if (error instanceof core.PiSessionFormatError) {
            return `${error.code}: ${error.message}`;
          }
          return error instanceof Error ? error.message : String(error);
        }
      };

      const altered = { ...parsed.entries[0], timestamp: '2026-07-17T07:00:00.000Z' };
      const disallowedBash = core.parsePiSessionJsonl(
        fixture.replace('moon test --target js', 'curl https://example.invalid/upload'),
      );
      const uncorrelatedToolResult = core.parsePiSessionJsonl(
        fixture.replace('"toolCallId":"call-read-docs"', '"toolCallId":"missing-call"'),
      );
      const human = projection.chronology.find(item => item.kind === 'human');
      const assistant = projection.chronology.find(item => item.kind === 'assistant-claim');
      const tool = projection.chronology.find(item => item.source.entryId === '00000003');
      const failedTool = projection.chronology.find(item => item.source.entryId === '0000000b');
      const checkpoint = projection.anchors[0];
      if (
        human === undefined ||
        assistant === undefined ||
        tool === undefined ||
        failedTool === undefined ||
        checkpoint === undefined
      ) {
        throw new Error('Fixture is missing epistemic boundary examples.');
      }
      const personAuthored = core.createThinkingItem({
        id: 'person-meaning-1',
        text: 'Carry this evidence into current work.',
        origin: { kind: 'person-authored' },
        derivation: { kind: 'recorded' },
        review: { kind: 'unreviewed' },
        sources: [tool.source],
      });
      const epistemicSignature = (item: typeof human) => core.stableSerialize({
        origin: item.origin,
        derivation: item.derivation,
        sources: item.sources,
      });
      const initialSignature = epistemicSignature(human);
      const accepted = core.reduceThinkingItemReview(human, { kind: 'accept' });
      const corrected = core.reduceThinkingItemReview(accepted, {
        kind: 'correct',
        text: 'Use the exact source while continuing this work.',
      });
      const dismissed = core.reduceThinkingItemReview(corrected, { kind: 'dismiss' });
      const reset = core.reduceThinkingItemReview(dismissed, { kind: 'reset' });
      return {
        deterministic:
          core.stableSerialize(projection) ===
          core.stableSerialize(core.projectResume(reduced, '0000000f')),
        replayPathEqual:
          core.stableSerialize(replay.terminalPaths) === core.stableSerialize(reduced.terminalPaths),
        replayDiagnostic: replay.diagnostics.some(item => item.code === 'replay_noop'),
        mismatch: throws(() =>
          core.reducePiSession({ ...parsed, entries: [...parsed.entries, altered] }),
        ),
        unsupportedVersion: throws(() =>
          core.parsePiSessionJsonl(fixture.replace('"version":3', '"version":2')),
        ),
        missingParent: throws(() =>
          core.parsePiSessionJsonl(fixture.replace('"parentId":"00000001"', '"parentId":"deadbeef"')),
        ),
        cycle: throws(() =>
          core.parsePiSessionJsonl(fixture.replace('"parentId":"00000001"', '"parentId":"00000002"')),
        ),
        duplicate: throws(() => core.parsePiSessionJsonl(`${fixture.trimEnd()}\n${fixture.split('\n')[1]}`)),
        invalidJson: throws(() => core.parsePiSessionJsonl('{')),
        bounded: throws(() =>
          core.parsePiSessionJsonl(fixture, { ...core.DEFAULT_LIMITS, maxFileBytes: 10 }),
        ),
        sensitiveWarning: core.parsePiSessionJsonl(
          fixture.replace(
            'restore the Canopy product direction',
            'api_key: withheld product direction',
          ),
        ).diagnostics.some(item => item.code === 'excerpt_contains_sensitive_pattern'),
        sensitiveTextRetained: core.parsePiSessionJsonl(
          fixture.replace(
            'restore the Canopy product direction',
            'api_key: retained product direction',
          ),
        ).entries.some(entry =>
          entry.id === '00000001' &&
          entry.kind === 'message' &&
          entry.text?.includes('api_key: retained product direction') === true,
        ),
        authorizationWarning: core.parsePiSessionJsonl(
          fixture.replace(
            'restore the Canopy product direction',
            'Authorization: Bearer fixture-token-value',
          ),
        ).diagnostics.some(item => item.code === 'excerpt_contains_sensitive_pattern'),
        urlCredentialWarning: core.parsePiSessionJsonl(
          fixture.replace(
            'restore the Canopy product direction',
            'Open https://fixture-user:fixture-pass@example.invalid/path',
          ),
        ).diagnostics.some(item => item.code === 'excerpt_contains_sensitive_pattern'),
        toolOutputWarning: core.parsePiSessionJsonl(
          fixture.replace('"toolName":"read"', '"toolName":"upload"'),
        ).diagnostics.some(item => item.code === 'tool_output_requires_explicit_egress'),
        disallowedBashOutputRetained: disallowedBash.entries.some(
          entry =>
            entry.id === '00000006' &&
            entry.kind === 'bashExecution' &&
            entry.output !== undefined &&
            entry.automaticOutputAllowed === false,
        ),
        uncorrelatedToolOutputRetained: uncorrelatedToolResult.entries.some(
          entry =>
            entry.id === '00000003' &&
            entry.kind === 'message' &&
            entry.text !== undefined &&
            entry.automaticOutputAllowed === false,
        ),
        uncorrelatedToolWarning: uncorrelatedToolResult.diagnostics.some(
          item => item.code === 'tool_output_requires_explicit_egress',
        ),
        epistemic: {
          human: { origin: human.origin, derivation: human.derivation, review: human.review },
          assistant: assistant.origin,
          tool: tool.origin,
          failedTool: failedTool.origin,
          checkpoint: checkpoint.origin,
          personAuthored: {
            origin: personAuthored.origin,
            derivation: personAuthored.derivation,
          },
          sourcesMirrorCanonicalSource:
            human.sources.length === 1 &&
            core.stableSerialize(human.sources[0]) === core.stableSerialize(human.source),
        },
        review: {
          preserved:
            [accepted, corrected, dismissed, reset]
              .every(item => epistemicSignature(item) === initialSignature),
          accepted: accepted.review.kind,
          corrected: corrected.review,
          dismissed: dismissed.review.kind,
          reset: reset.review.kind,
          idempotent:
            core.stableSerialize(core.reduceThinkingItemReview(accepted, { kind: 'accept' })) ===
            core.stableSerialize(accepted),
          immutable:
            Object.isFrozen(corrected) &&
            Object.isFrozen(corrected.review) &&
            corrected.review.kind === 'corrected' &&
            Object.isFrozen(corrected.review.replacement) &&
            Object.isFrozen(corrected.review.replacement.origin) &&
            Object.isFrozen(corrected.review.replacement.derivation),
        },
        invalidThinkingItem: {
          sourceLess: throws(() => core.createThinkingItem({
            id: 'source-less',
            text: 'No source.',
            origin: { kind: 'person-authored' },
            derivation: { kind: 'recorded' },
            review: { kind: 'unreviewed' },
            sources: [],
          })),
          invalidCombination: throws(() => core.createThinkingItem({
            id: 'invalid-combination',
            text: 'System output without a named derivation.',
            origin: { kind: 'canopy-system' },
            derivation: { kind: 'recorded' },
            review: { kind: 'unreviewed' },
            sources: [human.source],
          })),
          reviewBypass: throws(() => core.reduceThinkingItemReview({
            id: 'source-less-review-bypass',
            text: 'Invalid caller-supplied item.',
            origin: { kind: 'person-authored' },
            derivation: { kind: 'recorded' },
            review: { kind: 'accepted' },
            sources: [],
          }, { kind: 'accept' })),
          modelInference: throws(() => core.createThinkingItem({
            id: 'unauthorized-model-inference',
            text: 'A model-generated hypothesis.',
            origin: { kind: 'canopy-system' },
            derivation: {
              kind: 'model-inference',
              modelIdentity: 'fixture-model',
              analysisVersion: '1',
            },
            review: { kind: 'unreviewed' },
            sources: [human.source],
          })),
          emptyCorrection: throws(() => core.reduceThinkingItemReview(human, {
            kind: 'correct',
            text: '   ',
          })),
        },
        overview: {
          activeTask: projection.overview.activeTask?.source.entryId,
          latestOutcome: projection.overview.latestOutcome?.source.entryId,
          attention: projection.overview.attention?.source.entryId,
          nextAction: projection.overview.nextAction?.source.entryId,
          landmarks: projection.overview.landmarks.map(item => item.source.entryId),
        },
        immutable:
          Object.isFrozen(projection) &&
          Object.isFrozen(projection.chronology) &&
          Object.isFrozen(projection.overview) &&
          Object.isFrozen(projection.overview.landmarks) &&
          projection.chronology.every(item =>
            Object.isFrozen(item) &&
            Object.isFrozen(item.source) &&
            Object.isFrozen(item.origin) &&
            Object.isFrozen(item.derivation) &&
            Object.isFrozen(item.review) &&
            Object.isFrozen(item.sources) &&
            item.sources.every(source => Object.isFrozen(source))) &&
          Object.isFrozen(projection.diagnostics) &&
          projection.diagnostics.every(item => Object.isFrozen(item)),
      };
    }, { fixture });

    expect(result.deterministic).toBe(true);
    expect(result.replayPathEqual).toBe(true);
    expect(result.replayDiagnostic).toBe(true);
    expect(result.mismatch).toContain('different content');
    expect(result.unsupportedVersion).toContain('version 3');
    expect(result.missingParent).toContain('missing parent');
    expect(result.cycle).toContain('cycle');
    expect(result.duplicate).toContain('more than once');
    expect(result.invalidJson).toContain('invalid_json');
    expect(result.bounded).toContain('file_too_large');
    expect(result.sensitiveWarning).toBe(true);
    expect(result.sensitiveTextRetained).toBe(true);
    expect(result.authorizationWarning).toBe(true);
    expect(result.urlCredentialWarning).toBe(true);
    expect(result.toolOutputWarning).toBe(true);
    expect(result.disallowedBashOutputRetained).toBe(true);
    expect(result.uncorrelatedToolOutputRetained).toBe(true);
    expect(result.uncorrelatedToolWarning).toBe(true);
    expect(result.epistemic).toEqual({
      human: {
        origin: { kind: 'recorded-human' },
        derivation: { kind: 'recorded' },
        review: { kind: 'unreviewed' },
      },
      assistant: { kind: 'assistant-claim' },
      tool: { kind: 'observed-tool', outcome: 'success', toolCallId: 'call-read-docs' },
      failedTool: { kind: 'observed-tool', outcome: 'failure', toolCallId: 'call-check-baseline' },
      checkpoint: { kind: 'human-accepted-source' },
      personAuthored: {
        origin: { kind: 'person-authored' },
        derivation: { kind: 'recorded' },
      },
      sourcesMirrorCanonicalSource: true,
    });
    expect(result.review).toEqual({
      preserved: true,
      accepted: 'accepted',
      corrected: {
        kind: 'corrected',
        replacement: {
          text: 'Use the exact source while continuing this work.',
          origin: { kind: 'person-authored' },
          derivation: { kind: 'recorded' },
        },
      },
      dismissed: 'dismissed',
      reset: 'unreviewed',
      idempotent: true,
      immutable: true,
    });
    expect(result.invalidThinkingItem.sourceLess).toContain('at least one source');
    expect(result.invalidThinkingItem.invalidCombination).toContain('Recorded origins');
    expect(result.invalidThinkingItem.reviewBypass).toContain('at least one source');
    expect(result.invalidThinkingItem.modelInference).toContain('not authorized');
    expect(result.invalidThinkingItem.emptyCorrection).toContain('cannot be empty');
    expect(result.overview).toEqual({
      activeTask: '00000007',
      latestOutcome: '00000006',
      attention: '0000000c',
      nextAction: '0000000f',
      landmarks: [
        '00000006', '00000007', '00000008', '00000009',
        '0000000b', '0000000c', '0000000d', '0000000f',
      ],
    });
    expect(result.immutable).toBe(true);
  });
});
