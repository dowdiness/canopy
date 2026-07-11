// Main entry point for Lambda Calculus CRDT Editor

import { createEditor } from './editor';

const agentId = `user-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`;
const editor = createEditor(agentId);

// Example buttons
document.querySelectorAll('.example-btn').forEach(btn => {
  btn.addEventListener('click', () => {
    const example = btn.getAttribute('data-example');
    if (example) editor.setText(example);
  });
});

const statusEl = document.getElementById('status')!;
statusEl.textContent = `Ready! ID: ${agentId}`;
statusEl.className = 'status success';
