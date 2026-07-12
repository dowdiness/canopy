const EXAMPLES = [
  `<div class="bg-gray-800 text-white p-6 rounded-xl shadow-lg max-w-lg">\n  <h1 class="text-2xl font-bold text-emerald-400 mb-2">Hello, World!</h1>\n  <p class="text-gray-300">This is JSX parsed incrementally with Tailwind.</p>\n</div>`,
  `<article class="bg-gray-800 text-white p-6 rounded-xl max-w-lg">\n  <h2 class="text-xl font-bold text-sky-400 mb-3">Generative UI</h2>\n  <p class="text-gray-300 mb-2">Streaming JSX content with Tailwind styling.</p>\n  <a href="/next" class="text-sky-400 underline hover:text-sky-300">Continue reading</a>\n</article>`,
  `<div class="bg-gray-800 text-white p-6 rounded-xl max-w-lg space-y-3">\n  <section class="bg-gray-700 rounded-lg p-4">\n    <header>\n      <h1 class="text-xl font-bold text-amber-400">Deep Nesting</h1>\n    </header>\n    <main class="mt-3">\n      <p class="text-gray-300 mb-2">Level 3 content with Tailwind.</p>\n      <ul class="list-disc list-inside text-gray-300 space-y-1">\n        <li class="text-emerald-400">Item A</li>\n        <li class="text-rose-400">Item B</li>\n      </ul>\n    </main>\n  </section>\n</div>`,
  `<div class="bg-gray-800 text-white p-6 rounded-xl max-w-lg space-y-3">\n  <p class="text-gray-300">Hello, <span class="text-emerald-400 font-bold">{user.name}</span>!</p>\n  <span class="bg-amber-500/20 text-amber-300 px-3 py-1 rounded-full text-sm inline-block">Dynamic</span>\n  <p class="text-gray-300">Score: <span class="text-emerald-400 font-bold">{count}</span> / <span class="text-emerald-400 font-bold">{total}</span></p>\n</div>`,
  `<div class="bg-gray-800 text-white p-6 rounded-xl max-w-lg space-y-4">\n  <header class="border-b border-gray-600 pb-3">\n    <h1 class="text-2xl font-bold text-cyan-400">Dashboard</h1>\n    <nav class="flex gap-4 mt-2">\n      <a href="/home" class="text-gray-300 hover:text-cyan-400">Home</a>\n      <a href="/about" class="text-gray-300 hover:text-cyan-400">About</a>\n    </nav>\n  </header>\n  <section class="space-y-2">\n    <p class="text-gray-300">Welcome back, <strong class="text-amber-400">{username}</strong>!</p>\n    <p class="text-gray-300">You have <strong class="text-rose-400">{count}</strong> notifications.</p>\n  </section>\n</div>`,
  `<div class="bg-gradient-to-br from-indigo-500 to-purple-600 text-white p-6 rounded-xl shadow-lg max-w-md">\n  <h1 class="text-2xl font-bold mb-4">Tailwind CSS</h1>\n  <p class="text-indigo-100 mb-3">Classes from input JSX are applied to rendered DOM.</p>\n  <div class="flex gap-2">\n    <span class="bg-white/20 px-3 py-1 rounded-full text-sm">Active</span>\n    <span class="bg-white/10 px-3 py-1 rounded-full text-sm">Pending</span>\n  </div>\n  <p class="mt-4 text-indigo-200 text-sm">Gradient card via Tailwind utilities.</p>\n</div>`,
];

const sourceInput = document.getElementById('source-input')
const streamBtn = document.getElementById('stream-btn')
const clearBtn = document.getElementById('clear-btn')
const treeOutput = document.getElementById('tree-output')
const htmlPreview = document.getElementById('html-preview')
const errorsList = document.getElementById('errors-list')
const stepNum = document.getElementById('step-num')
const htmlStepNum = document.getElementById('html-step-num')
const htmlNodeCount = document.getElementById('html-node-count')
const streamProgress = document.getElementById('stream-progress')
const statusBar = document.getElementById('status-bar')

let isStreaming = false
let abortStream = false
let previousNodeIds = new Set()
let jsxModule = null
let jsxSessionHandle = null

document.querySelectorAll('[data-example]').forEach(function(btn) {
  btn.addEventListener('click', function() {
    if (isStreaming) return;
    sourceInput.value = EXAMPLES[parseInt(btn.dataset.example)];
    resetState();
    statusBar.textContent = 'Example loaded. Click \u25B6 Stream.';
  });
});

document.querySelectorAll('.view-tab').forEach(function(tab) {
  tab.addEventListener('click', function() {
    const view = tab.dataset.view;
    tab.parentElement.querySelectorAll('.view-tab').forEach(function(t) { t.classList.remove('active'); });
    tab.classList.add('active');
    tab.parentElement.parentElement.querySelectorAll('.view-panel').forEach(function(p) { p.classList.remove('active'); });
    const panel = document.getElementById('view-' + view)
    panel.classList.add('active');
    panel.style.display = 'flex';
  });
});

clearBtn.addEventListener('click', function() {
  abortStream = true;
  isStreaming = false;
  streamBtn.disabled = false;
  streamBtn.textContent = '\u25B6 Stream';
  streamBtn.className = 'btn-primary';
  resetState();
  statusBar.textContent = 'Cleared.';
});

function resetState() {
  if (jsxModule && jsxSessionHandle !== null) {
    jsxModule.jsx_session_dispose(jsxSessionHandle)
    jsxSessionHandle = null
  }
  previousNodeIds = new Set();
  treeOutput.innerHTML = '<div class="text-center py-8 text-canopy-muted text-xs">Stream JSX to see the tree.</div>';
  htmlPreview.innerHTML = '<div class="text-center py-8 text-canopy-muted text-xs">Stream JSX to see rendered output.</div>';
  streamProgress.textContent = 'Ready.';
  stepNum.textContent = '\u2014';
  htmlStepNum.textContent = '\u2014';
  htmlNodeCount.textContent = '0';
  errorsList.innerHTML = '<div class="text-center py-8 text-canopy-muted text-xs">No errors.</div>';
}

// ── ProjNode Tree Rendering (pure JS, unchanged) ──
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
  let html = '<div class="tree-node"><div class="tree-node-header">' + toggle + '<span class="node-id ' + idClass + '">#' + nodeId + '</span> ' + headerLabel + countStr + '</div>';
  if (hasChildren) { html += '<div>'; for (let ci = 0; ci < node.children.length; ci++) { html += renderTreeNode(node.children[ci], prevIds); } html += '</div>'; }
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

function collectNodeIds(root) {
  const ids = new Set()
  function walk(n) { if (n && n.node_id != null) ids.add(n.node_id); if (n && n.children) { for (let ci = 0; ci < n.children.length; ci++) { walk(n.children[ci]); } } }
  walk(root);
  return ids;
}

// ── Streaming (MoonBit render via a stateful JSX FFI session) ──
streamBtn.addEventListener('click', async function() {
  if (isStreaming) { abortStream = true; return; }
  const fullText = sourceInput.value;
  if (!fullText.trim()) { statusBar.textContent = 'Please enter JSX text.'; return; }
  isStreaming = true; abortStream = false;
  streamBtn.textContent = '\u25A0 Stop'; streamBtn.className = 'btn-primary';
  previousNodeIds = new Set();
  htmlPreview.innerHTML = '';
  statusBar.textContent = 'Loading MoonBit JSX module...';

  // Split at JSX syntactic boundaries (after `>`) so each prefix ends at a
  // complete tag opening or closing, avoiding "truncated tag" / "unterminated
  // attribute" diagnostics from mid-attribute cuts.
  const prefixes = [];
  let lastSplit = 0;
  for (let i = 0; i < fullText.length; i++) { if (fullText[i] === '>' && i - lastSplit >= 10) {
    prefixes.push(fullText.slice(0, i + 1));
    lastSplit = i;
  } }
  if (prefixes[prefixes.length - 1] !== fullText) prefixes.push(fullText);

  try {
    const JsxMod = await import('@moonbit/crdt-jsx');
    jsxModule = JsxMod;
    if (jsxSessionHandle !== null) {
      JsxMod.jsx_session_dispose(jsxSessionHandle);
      jsxSessionHandle = null;
    }
    statusBar.textContent = 'Streaming ' + prefixes.length + ' steps...';
    let finalIds = [];
    for (let si = 0; si < prefixes.length; si++) {
      if (abortStream) break;
      stepNum.textContent = (si + 1) + ' / ' + prefixes.length;
      htmlStepNum.textContent = (si + 1) + ' / ' + prefixes.length;
      streamProgress.innerHTML = '<span class="text-canopy-muted">Step ' + (si + 1) + ':</span> ' + esc(prefixes[si]);
      
      // The first call creates and renders the session. Later calls update
      // exactly that session, so parser/projection/DOM ownership stays local.
      let renderResult;
      if (si === 0) {
        const created = JSON.parse(JsxMod.jsx_session_new(prefixes[si], 'html-preview'));
        if (!created.success || created.handle === null) {
          throw new Error(created.result?.error?.message || 'JSX session creation failed');
        }
        jsxSessionHandle = Number(created.handle);
        renderResult = created.result;
      } else {
        renderResult = JSON.parse(JsxMod.jsx_session_render(jsxSessionHandle, prefixes[si]));
      }
      if (!renderResult.success) {
        throw new Error(renderResult.error?.message || 'JSX session render failed');
      }
      const ids = renderResult.mounted_ids;
      finalIds = ids;
      htmlNodeCount.textContent = ids.length;
      
      // Tree view from batch parse
      const batchResult = JsxMod.jsx_parse_to_json(prefixes[si]);
      const batch = JSON.parse(batchResult);
      if (batch.success && batch.root) {
        const currentIds = collectNodeIds(batch.root);
        treeOutput.innerHTML = renderTreeNode(batch.root, previousNodeIds);
        previousNodeIds = currentIds;
      } else if (batch.success) {
        treeOutput.innerHTML = '<div class="text-center py-8 text-canopy-muted text-xs">No root node.</div>';
      } else {
        treeOutput.innerHTML = '<div class="text-center py-8 text-canopy-red text-xs">Error: ' + esc(batch.error || '') + '</div>';
      }
      
      if (batch.errors && batch.errors.length > 0) {
        errorsList.innerHTML = batch.errors.map(function(e) { return '<div class="error-item">' + esc(e) + '</div>'; }).join('');
      } else {
        errorsList.innerHTML = '<div class="text-center py-8 text-canopy-muted text-xs">No diagnostics.</div>';
      }
      
      statusBar.textContent = 'Step ' + (si + 1) + '/' + prefixes.length + ' \u2014 ' + ids.length + ' DOM nodes';
      if (batch.errors && batch.errors.length > 0) statusBar.textContent += ', ' + batch.errors.length + ' diagnostic(s)';
      await new Promise(function(r) { setTimeout(r, si < 5 ? 60 : 100); });
    }
    statusBar.className = 'mt-2 p-1.5 bg-canopy-bg rounded-md text-[11px] text-canopy-muted';
    statusBar.textContent = abortStream ? 'Stopped.' : 'Complete \u2014 ' + finalIds.length + ' DOM nodes rendered.';
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
