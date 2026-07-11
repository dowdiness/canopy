const EXAMPLES = [
  `<div class="bg-gray-800 text-white p-6 rounded-xl shadow-lg max-w-lg">\n  <h1 class="text-2xl font-bold text-emerald-400 mb-2">Hello, World!</h1>\n  <p class="text-gray-300">This is JSX parsed incrementally with Tailwind.</p>\n</div>`,
  `<article class="bg-gray-800 text-white p-6 rounded-xl max-w-lg">\n  <h2 class="text-xl font-bold text-sky-400 mb-3">Generative UI</h2>\n  <p class="text-gray-300 mb-2">Streaming JSX content with Tailwind styling.</p>\n  <a href="/next" class="text-sky-400 underline hover:text-sky-300">Continue reading</a>\n</article>`,
  `<div class="bg-gray-800 text-white p-6 rounded-xl max-w-lg space-y-3">\n  <section class="bg-gray-700 rounded-lg p-4">\n    <header>\n      <h1 class="text-xl font-bold text-amber-400">Deep Nesting</h1>\n    </header>\n    <main class="mt-3">\n      <p class="text-gray-300 mb-2">Level 3 content with Tailwind.</p>\n      <ul class="list-disc list-inside text-gray-300 space-y-1">\n        <li class="text-emerald-400">Item A</li>\n        <li class="text-rose-400">Item B</li>\n      </ul>\n    </main>\n  </section>\n</div>`,
  `<div class="bg-gray-800 text-white p-6 rounded-xl max-w-lg space-y-3">\n  <p class="text-gray-300">Hello, <span class="text-emerald-400 font-bold">{user.name}</span>!</p>\n  <span class="bg-amber-500/20 text-amber-300 px-3 py-1 rounded-full text-sm inline-block">Dynamic</span>\n  <p class="text-gray-300">Score: <span class="text-emerald-400 font-bold">{count}</span> / <span class="text-emerald-400 font-bold">{total}</span></p>\n</div>`,
  `<div class="bg-gray-800 text-white p-6 rounded-xl max-w-lg space-y-4">\n  <header class="border-b border-gray-600 pb-3">\n    <h1 class="text-2xl font-bold text-cyan-400">Dashboard</h1>\n    <nav class="flex gap-4 mt-2">\n      <a href="/home" class="text-gray-300 hover:text-cyan-400">Home</a>\n      <a href="/about" class="text-gray-300 hover:text-cyan-400">About</a>\n    </nav>\n  </header>\n  <section class="space-y-2">\n    <p class="text-gray-300">Welcome back, <strong class="text-amber-400">{username}</strong>!</p>\n    <p class="text-gray-300">You have <strong class="text-rose-400">{count}</strong> notifications.</p>\n  </section>\n</div>`,
  `<div class="bg-gradient-to-br from-indigo-500 to-purple-600 text-white p-6 rounded-xl shadow-lg max-w-md">\n  <h1 class="text-2xl font-bold mb-4">Tailwind CSS</h1>\n  <p class="text-indigo-100 mb-3">Classes from input JSX are applied to rendered DOM.</p>\n  <div class="flex gap-2">\n    <span class="bg-white/20 px-3 py-1 rounded-full text-sm">Active</span>\n    <span class="bg-white/10 px-3 py-1 rounded-full text-sm">Pending</span>\n  </div>\n  <p class="mt-4 text-indigo-200 text-sm">Gradient card via Tailwind utilities.</p>\n</div>`,
];

const sourceInput = document.getElementById('source-input');
const streamBtn = document.getElementById('stream-btn');
const clearBtn = document.getElementById('clear-btn');
const treeOutput = document.getElementById('tree-output');
const htmlPreview = document.getElementById('html-preview');
const errorsList = document.getElementById('errors-list');
const stepNum = document.getElementById('step-num');
const htmlStepNum = document.getElementById('html-step-num');
const htmlNodeCount = document.getElementById('html-node-count');
const streamProgress = document.getElementById('stream-progress');
const statusBar = document.getElementById('status-bar');

let isStreaming = false;
let abortStream = false;
let previousNodeIds = new Set();
let nodeElementMap = new Map();

document.querySelectorAll('[data-example]').forEach(btn => {
  btn.addEventListener('click', () => {
    if (isStreaming) return;
    sourceInput.value = EXAMPLES[parseInt(btn.dataset.example)];
    resetState();
    statusBar.textContent = 'Example loaded. Click \u25B6 Stream.';
  });
});

document.querySelectorAll('.view-tab').forEach(tab => {
  tab.addEventListener('click', () => {
    const view = tab.dataset.view;
    tab.parentElement.querySelectorAll('.view-tab').forEach(t => t.classList.remove('active'));
    tab.classList.add('active');
    tab.parentElement.parentElement.querySelectorAll('.view-panel').forEach(p => p.classList.remove('active'));
    const panel = document.getElementById('view-' + view);
    panel.classList.add('active');
    panel.style.display = 'flex';
  });
});

clearBtn.addEventListener('click', () => {
  abortStream = true;
  isStreaming = false;
  streamBtn.disabled = false;
  streamBtn.textContent = '\u25B6 Stream';
  streamBtn.className = 'btn-primary';
  resetState();
  statusBar.textContent = 'Cleared.';
});

function resetState() {
  previousNodeIds = new Set();
  nodeElementMap = new Map();
  treeOutput.innerHTML = '<div class="text-center py-8 text-canopy-muted text-xs">Stream JSX to see the tree.</div>';
  htmlPreview.innerHTML = '<div class="text-center py-8 text-canopy-muted text-xs">Stream JSX to see rendered output.</div>';
  streamProgress.textContent = 'Ready.';
  stepNum.textContent = '\u2014';
  htmlStepNum.textContent = '\u2014';
  htmlNodeCount.textContent = '0';
  errorsList.innerHTML = '<div class="text-center py-8 text-canopy-muted text-xs">No errors.</div>';
}

// ── ProjNode Tree Rendering ──
function renderTreeNode(node, prevIds) {
  const nodeId = node.node_id;
  const isStable = prevIds.has(nodeId);
  const idClass = isStable ? 'stable' : 'new';
  const kind = node.kind;
  const kindTag = node.kind_tag;
  let headerLabel = '';
  switch (kindTag) {
    case 'Root': headerLabel = '<span class="text-canopy-blue">Root</span>'; break;
    case 'Element':
      headerLabel = '<span class="text-canopy-blue">Element</span> <span class="text-canopy-purple">&lt;' + esc(kind.tag) + '&gt;</span>';
      if (kind.attrs && kind.attrs.length > 0) {
        const a = kind.attrs.map(function(a) { return '<span class="text-canopy-cyan text-[10px]">' + esc(a.name) + '=</span>' + renderAttrValue(a.value); }).join(' ');
        headerLabel += ' <span class="text-[10px] text-canopy-muted">[' + a + ']</span>';
      }
      break;
    case 'Fragment': headerLabel = '<span class="text-canopy-blue">Fragment</span>'; break;
    case 'Text': headerLabel = '<span class="text-canopy-blue">Text</span> <span class="text-[#c3e88d]">"' + esc(kind.value) + '"</span>'; break;
    case 'ExprSpan': headerLabel = '<span class="text-canopy-blue">ExprSpan</span> <span class="text-canopy-yellow">{' + esc(kind.value) + '}</span>'; break;
    case 'Error': headerLabel = '<span class="text-canopy-red">Error</span> <span class="text-canopy-red">"' + esc(kind.value) + '"</span>'; break;
    default: headerLabel = '<span class="text-canopy-blue">' + kindTag + '</span>';
  }
  const hasChildren = node.children && node.children.length > 0;
  const toggle = hasChildren ? '<span class="tree-toggle">\u25BC</span>' : '<span class="tree-toggle"> </span>';
  const countStr = hasChildren ? ' <span class="text-[10px] text-canopy-muted">(' + node.children.length + ')</span>' : '';
  var html = '<div class="tree-node"><div class="tree-node-header">' + toggle + '<span class="node-id ' + idClass + '">#' + nodeId + '</span> ' + headerLabel + countStr + '</div>';
  if (hasChildren) { html += '<div>'; for (var ci = 0; ci < node.children.length; ci++) { html += renderTreeNode(node.children[ci], prevIds); } html += '</div>'; }
  html += '</div>';
  return html;
}

function renderAttrValue(val) {
  if (typeof val === 'string') return '<span class="text-[#c3e88d]">"' + esc(val) + '"</span>';
  if (val && val.type === 'expr-span') return '<span class="text-canopy-yellow">{' + esc(val.raw) + '}</span>';
  if (val && val.type === 'bare') return '<span class="text-canopy-blue">true</span>';
  return '';
}

function esc(s) { return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;'); }

// ── DOM Building ──
function buildDomFromProjNode(node) {
  const nodeId = node.node_id;
  if (node.kind_tag === 'Error') return null;
  if (nodeElementMap.has(nodeId)) {
    const existing = nodeElementMap.get(nodeId);
    if (node.kind_tag === 'Text') {
      existing.textContent = node.kind.value || '';
    } else if (node.kind_tag === 'ExprSpan') {
      existing.textContent = '{' + (node.kind.value || '') + '}';
    } else if (node.kind_tag === 'Element' && node.kind.attrs) {
      existing.className = '';
      existing.style.cssText = '';
      for (var ai = 0; ai < node.kind.attrs.length; ai++) {
        applyAttr(existing, node.kind.attrs[ai]);
      }
    }
    updateChildren(existing, node);
    return existing;
  }
  var el = createElementForKind(node);
  if (!el) return null;
  el.dataset.nodeId = nodeId;
  if (node.kind_tag !== 'Root') el.classList.add('new');
  if (node.children) {
    for (var ci = 0; ci < node.children.length; ci++) {
      const childEl = buildDomFromProjNode(node.children[ci]);
      if (childEl) el.appendChild(childEl);
    }
  }
  nodeElementMap.set(nodeId, el);
  return el;
}

function createElementForKind(node) {
  const kt = node.kind_tag;
  const k = node.kind;
  if (kt === 'Root') { return document.createElement('div'); }
  if (kt === 'Fragment') { const d = document.createElement('div'); return d; }
  if (kt === 'Element') {
    const tag = k.tag || 'div'; const tagLower = tag.toLowerCase();
    const sem = { h1:'h1',h2:'h2',h3:'h3',h4:'h4',h5:'h5',h6:'h6', a:'a', p:'p', ul:'ul', ol:'ol', li:'li', nav:'nav', strong:'strong', em:'em', code:'code', span:'span', div:'div', section:'section', header:'header', main:'main', article:'article', footer:'footer' };
    const el = document.createElement(sem[tagLower] || 'div');
    if (k.attrs) { for (var ai = 0; ai < k.attrs.length; ai++) { applyAttr(el, k.attrs[ai]); } }
    return el;
  }
  if (kt === 'Text') { const s = document.createElement('span'); s.className = 'genui-text'; s.textContent = k.value || ''; return s; }
  const f = document.createElement('span'); f.textContent = '[' + kt + ']'; return f;
}

function applyAttr(el, attr) {
  const n = attr.name; const v = attr.value; if (!n) return;
  if (typeof v === 'string') {
    if (n === 'class') el.setAttribute('class', v);
    else if (n === 'id') el.id = v; else if (n === 'href') el.href = v;
    else if (n === 'style') el.style.cssText = v; else if (n === 'target') el.target = v;
    else el.setAttribute(n, v);
  } else if (v && v.type === 'bare') el.setAttribute(n, '');
}

function updateChildren(parent, node) {
  if (!node.children) return;
  var idx = 0;
  for (var ci = 0; ci < node.children.length; ci++) {
    const child = node.children[ci];
    if (nodeElementMap.has(child.node_id)) {
      const existing = nodeElementMap.get(child.node_id);
      if (child.kind_tag === 'Text') {
        existing.textContent = child.kind.value || '';
      } else if (child.kind_tag === 'ExprSpan') {
        existing.textContent = '{' + (child.kind.value || '') + '}';
      } else if (child.kind_tag === 'Element' && child.kind.attrs) {
        existing.className = ''; existing.style.cssText = '';
        for (var ai2 = 0; ai2 < child.kind.attrs.length; ai2++) {
          applyAttr(existing, child.kind.attrs[ai2]);
        }
      }
      existing.classList.remove('new'); existing.classList.add('stable');
      updateChildren(existing, child);
    } else {
      const childEl = buildDomFromProjNode(child);
      if (childEl) {
        const next = parent.children[idx];
        if (next) { parent.insertBefore(childEl, next); } else { parent.appendChild(childEl); }
      }
    }
    idx++;
  }
  while (idx < parent.children.length) {
    parent.children[idx].remove();
  }
}
function renderHtmlTree(data) {
  if (!data) { htmlPreview.innerHTML = '<div class="text-center py-8 text-canopy-muted text-xs">No parse result.</div>'; htmlNodeCount.textContent = '0'; return; }
  const rootEl = buildDomFromProjNode(data);
  if (htmlPreview.children.length === 0 || htmlPreview.querySelector('.no-parse')) {
    htmlPreview.innerHTML = '';
    if (data.kind_tag === 'Root' || data.kind_tag === 'Fragment') {
      for (var ci = 0; ci < data.children.length; ci++) {
        const e = nodeElementMap.get(data.children[ci].node_id);
        if (e) htmlPreview.appendChild(e);
      }
    } else { htmlPreview.appendChild(rootEl); }
  } else {
    if (data.kind_tag === 'Root' || data.kind_tag === 'Fragment') {
      for (var ci = 0; ci < data.children.length; ci++) {
        const e = nodeElementMap.get(data.children[ci].node_id);
        if (e && e.parentNode !== htmlPreview) htmlPreview.appendChild(e);
      }
    }
  }
  htmlNodeCount.textContent = nodeElementMap.size;
}

function collectNodeIds(root) {
  const ids = new Set();
  function walk(n) { if (n && n.node_id != null) ids.add(n.node_id); if (n && n.children) n.children.forEach(walk); }
  walk(root);
  return ids;
}

// ── Streaming ──
streamBtn.addEventListener('click', async function() {
  if (isStreaming) { abortStream = true; return; }
  const fullText = sourceInput.value;
  if (!fullText.trim()) { statusBar.textContent = 'Please enter JSX text.'; return; }
  isStreaming = true; abortStream = false;
  streamBtn.textContent = '\u25A0 Stop'; streamBtn.className = 'btn-primary';
  previousNodeIds = new Set(); nodeElementMap = new Map();
  htmlPreview.innerHTML = '<div class="text-center py-8 text-canopy-muted text-xs">Stream JSX to see rendered output.</div>';
  statusBar.textContent = 'Loading MoonBit JSX module...';

  const CHUNK = 15;
  const prefixes = [];
  for (var i = CHUNK; i <= fullText.length; i += CHUNK) prefixes.push(fullText.slice(0, i));
  if (prefixes[prefixes.length - 1] !== fullText) prefixes.push(fullText);

  try {
    const JsxMod = await import('@moonbit/crdt-jsx');
    statusBar.textContent = 'Streaming ' + prefixes.length + ' steps...';
    const resultJson = JsxMod.jsx_streaming_to_json(prefixes.join('\0'));
    const steps = JSON.parse(resultJson);
    for (var si = 0; si < steps.length; si++) {
      if (abortStream) break;
      const step = steps[si];
      stepNum.textContent = (si + 1) + ' / ' + steps.length;
      htmlStepNum.textContent = (si + 1) + ' / ' + steps.length;
      streamProgress.innerHTML = '<span class="text-canopy-muted">Step ' + (si + 1) + ':</span> ' + esc(prefixes[si]);
      if (step.success && step.root) {
        const currentIds = collectNodeIds(step.root);
        treeOutput.innerHTML = renderTreeNode(step.root, previousNodeIds);
        renderHtmlTree(step.root);
        previousNodeIds = currentIds;
      } else if (step.success) {
        treeOutput.innerHTML = '<div class="text-center py-8 text-canopy-muted text-xs">No root node.</div>';
      } else {
        treeOutput.innerHTML = '<div class="text-center py-8 text-canopy-red text-xs">Error: ' + esc(step.error || 'unknown') + '</div>';
      }
      if (step.errors && step.errors.length > 0) {
        errorsList.innerHTML = step.errors.map(function(e) { return '<div class="error-item">' + esc(e) + '</div>'; }).join('');
      } else { errorsList.innerHTML = '<div class="text-center py-8 text-canopy-muted text-xs">No diagnostics.</div>'; }
      statusBar.textContent = 'Step ' + (si + 1) + '/' + steps.length + ' \u2014 ' + nodeElementMap.size + ' DOM nodes';
      if (step.errors && step.errors.length > 0) statusBar.textContent += ', ' + step.errors.length + ' diagnostic(s)';
      await new Promise(function(r) { setTimeout(r, si < 5 ? 60 : 100); });
    }
    statusBar.className = 'mt-2 p-1.5 bg-canopy-bg rounded-md text-[11px] text-canopy-muted';
    statusBar.textContent = abortStream ? 'Stopped.' : 'Complete \u2014 ' + nodeElementMap.size + ' DOM nodes rendered.';
  } catch (err) {
    console.error(err);
    statusBar.className = 'mt-2 p-1.5 bg-canopy-bg rounded-md text-[11px] text-canopy-red';
    statusBar.textContent = 'Error: ' + err.message;
    treeOutput.innerHTML = '<div class="text-center py-8 text-canopy-red text-xs">Error: ' + esc(err.message) + '</div>';
  }
  isStreaming = false;
  streamBtn.textContent = '\u25B6 Stream';
  streamBtn.className = 'btn-primary';
});
