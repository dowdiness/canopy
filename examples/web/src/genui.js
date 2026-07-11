const EXAMPLES = [
  `<div class="bg-gray-800 text-white p-6 rounded-xl shadow-lg max-w-lg">\n  <h1 class="text-2xl font-bold text-emerald-400 mb-2">Hello, World!</h1>\n  <p class="text-gray-300">This is JSX parsed incrementally with Tailwind.</p>\n</div>`,
  `<article class="bg-gray-800 text-white p-6 rounded-xl max-w-lg">\n  <h2 class="text-xl font-bold text-sky-400 mb-3">Generative UI</h2>\n  <p class="text-gray-300 mb-2">Streaming JSX content with Tailwind styling.</p>\n  <a href="/next" class="text-sky-400 underline hover:text-sky-300">Continue reading</a>\n</article>`,
  `<div class="bg-gray-800 text-white p-6 rounded-xl max-w-lg space-y-3">\n  <section class="bg-gray-700 rounded-lg p-4">\n    <header>\n      <h1 class="text-xl font-bold text-amber-400">Deep Nesting</h1>\n    </header>\n    <main class="mt-3">\n      <p class="text-gray-300 mb-2">Level 3 content with Tailwind.</p>\n      <ul class="list-disc list-inside text-gray-300 space-y-1">\n        <li class="text-emerald-400">Item A</li>\n        <li class="text-rose-400">Item B</li>\n      </ul>\n    </main>\n  </section>\n</div>`,
  `<div class="bg-gray-800 text-white p-6 rounded-xl max-w-lg space-y-3">\n  <p class="text-gray-300">Hello, <span class="text-emerald-400 font-bold">{user.name}</span>!</p>\n  <span class="bg-amber-500/20 text-amber-300 px-3 py-1 rounded-full text-sm inline-block">Dynamic</span>\n  <p class="text-gray-300">Score: <span class="text-emerald-400 font-bold">{count}</span> / <span class="text-emerald-400 font-bold">{total}</span></p>\n</div>`,
  `<div class="bg-gray-800 text-white p-6 rounded-xl max-w-lg space-y-4">\n  <header class="border-b border-gray-600 pb-3">\n    <h1 class="text-2xl font-bold text-cyan-400">Dashboard</h1>\n    <nav class="flex gap-4 mt-2">\n      <a href="/home" class="text-gray-300 hover:text-cyan-400">Home</a>\n      <a href="/about" class="text-gray-300 hover:text-cyan-400">About</a>\n    </nav>\n  </header>\n  <section class="space-y-2">\n    <p class="text-gray-300">Welcome back, <strong class="text-amber-400">{username}</strong>!</p>\n    <p class="text-gray-300">You have <strong class="text-rose-400">{count}</strong> notifications.</p>\n  </section>\n</div>`,
  `<div class="bg-gradient-to-br from-indigo-500 to-purple-600 text-white p-6 rounded-xl shadow-lg max-w-md">\n  <h1 class="text-2xl font-bold mb-4">Tailwind CSS</h1>\n  <p class="text-indigo-100 mb-3">Classes from input JSX are applied to rendered DOM.</p>\n  <div class="flex gap-2">\n    <span class="bg-white/20 px-3 py-1 rounded-full text-sm">Active</span>\n    <span class="bg-white/10 px-3 py-1 rounded-full text-sm">Pending</span>\n  </div>\n  <p class="mt-4 text-indigo-200 text-sm">Gradient card via Tailwind utilities.</p>\n</div>`,
];

var sourceInput = document.getElementById('source-input');
var streamBtn = document.getElementById('stream-btn');
var clearBtn = document.getElementById('clear-btn');
var treeOutput = document.getElementById('tree-output');
var htmlPreview = document.getElementById('html-preview');
var errorsList = document.getElementById('errors-list');
var stepNum = document.getElementById('step-num');
var htmlStepNum = document.getElementById('html-step-num');
var htmlNodeCount = document.getElementById('html-node-count');
var streamProgress = document.getElementById('stream-progress');
var statusBar = document.getElementById('status-bar');

var isStreaming = false;
var abortStream = false;
var previousNodeIds = new Set();

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
    var view = tab.dataset.view;
    tab.parentElement.querySelectorAll('.view-tab').forEach(function(t) { t.classList.remove('active'); });
    tab.classList.add('active');
    tab.parentElement.parentElement.querySelectorAll('.view-panel').forEach(function(p) { p.classList.remove('active'); });
    var panel = document.getElementById('view-' + view);
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
  previousNodeIds = new Set();
  var ids = new Set();
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
  var nodeId = node.node_id;
  var isStable = prevIds.has(nodeId);
  var idClass = isStable ? 'stable' : 'new';
  var kind = node.kind;
  var kindTag = node.kind_tag;
  var headerLabel = '';
  switch (kindTag) {
    case 'Root': headerLabel = '<span class="text-canopy-blue">Root</span>'; break;
    case 'Element':
      headerLabel = '<span class="text-canopy-blue">Element</span> <span class="text-canopy-purple">&lt;' + esc(kind.tag) + '&gt;</span>';
      if (kind.attrs && kind.attrs.length > 0) {
        var a = kind.attrs.map(function(a) { return '<span class="text-canopy-cyan text-[10px]">' + esc(a.name) + '=</span>' + renderAttrValue(a.value); }).join(' ');
        headerLabel += ' <span class="text-[10px] text-canopy-muted">[' + a + ']</span>';
      }
      break;
    case 'Fragment': headerLabel = '<span class="text-canopy-blue">Fragment</span>'; break;
    case 'Text': headerLabel = '<span class="text-canopy-blue">Text</span> <span class="text-[#c3e88d]">"' + esc(kind.value) + '"</span>'; break;
    case 'ExprSpan': headerLabel = '<span class="text-canopy-blue">ExprSpan</span> <span class="text-canopy-yellow">{' + esc(kind.value) + '}</span>'; break;
    case 'Error': headerLabel = '<span class="text-canopy-red">Error</span> <span class="text-canopy-red">"' + esc(kind.value) + '"</span>'; break;
    default: headerLabel = '<span class="text-canopy-blue">' + kindTag + '</span>';
  }
  var hasChildren = node.children && node.children.length > 0;
  var toggle = hasChildren ? '<span class="tree-toggle">\u25BC</span>' : '<span class="tree-toggle"> </span>';
  var countStr = hasChildren ? ' <span class="text-[10px] text-canopy-muted">(' + node.children.length + ')</span>' : '';
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

function collectNodeIds(root) {
  var ids = new Set();
  function walk(n) { if (n && n.node_id != null) ids.add(n.node_id); if (n && n.children) { for (var ci = 0; ci < n.children.length; ci++) { walk(n.children[ci]); } } }
  walk(root);
  return ids;
}

// ── Streaming (MoonBit render via jsx_parse_and_render) ──
streamBtn.addEventListener('click', async function() {
  if (isStreaming) { abortStream = true; return; }
  var fullText = sourceInput.value;
  if (!fullText.trim()) { statusBar.textContent = 'Please enter JSX text.'; return; }
  isStreaming = true; abortStream = false;
  streamBtn.textContent = '\u25A0 Stop'; streamBtn.className = 'btn-primary';
  previousNodeIds = new Set();
  var ids = new Set();
  htmlPreview.innerHTML = '<div class="text-center py-8 text-canopy-muted text-xs">Stream JSX to see rendered output.</div>';
  statusBar.textContent = 'Loading MoonBit JSX module...';

  var CHUNK = 15;
  var prefixes = [];
  for (var i = CHUNK; i <= fullText.length; i += CHUNK) prefixes.push(fullText.slice(0, i));
  if (prefixes[prefixes.length - 1] !== fullText) prefixes.push(fullText);

  try {
    var JsxMod = await import('@moonbit/crdt-jsx');
    JsxMod.reset_jsx_state();
    statusBar.textContent = 'Streaming ' + prefixes.length + ' steps...';
    var existingIds = '[]';
    for (var si = 0; si < prefixes.length; si++) {
      if (abortStream) break;
      stepNum.textContent = (si + 1) + ' / ' + prefixes.length;
      htmlStepNum.textContent = (si + 1) + ' / ' + prefixes.length;
      streamProgress.innerHTML = '<span class="text-canopy-muted">Step ' + (si + 1) + ':</span> ' + esc(prefixes[si]);

      // MoonBit: parse → reconcile → apply patches in one call
      existingIds = JsxMod.jsx_parse_and_render(prefixes[si], existingIds);
      var ids = JSON.parse(existingIds);
      htmlNodeCount.textContent = ids.length;

      // Tree view from batch parse
      var batchResult = JsxMod.jsx_parse_to_json(prefixes[si]);
      var batch = JSON.parse(batchResult);
      if (batch.success && batch.root) {
        var currentIds = collectNodeIds(batch.root);
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
    var finalIds = JSON.parse(existingIds);
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
