import './styles.css';
import {
  ORDER_ROWS,
  ORDERS_CSV_FIXTURE,
  deriveOrderView,
  parseOrdersCsv,
  selectOrder,
  summarizeOrders,
} from '../core/data.ts';
import {
  buildLiveStudyRequest,
  recordedDemoInput,
} from '../core/genui-feasibility-demo.js';
import { runFeasibilityCandidate as executeFeasibilityCandidate } from '../core/genui-feasibility-flow.js';

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
const dataFilterInput = document.getElementById('data-filter-input')
const dataFilterClear = document.getElementById('data-filter-clear')
const dataJsonSource = document.getElementById('data-json-source')
const dataCsvSource = document.getElementById('data-csv-source')

const dataSourceLabel = document.getElementById('data-source-label')
const dataRowCount = document.getElementById('data-row-count')
const dataSummaryCount = document.getElementById('data-summary-count')
const dataSummaryTotal = document.getElementById('data-summary-total')
const dataSummaryAverage = document.getElementById('data-summary-average')
const ordersTableBody = document.getElementById('orders-table-body')
const dataSelectionStatus = document.getElementById('data-selection-status')
const dataDetailEmpty = document.getElementById('data-detail-empty')
const dataDetailContent = document.getElementById('data-detail-content')
const dataDetailId = document.getElementById('data-detail-id')
const dataDetailName = document.getElementById('data-detail-name')
const dataDetailStatus = document.getElementById('data-detail-status')
const dataDetailAmount = document.getElementById('data-detail-amount')
const feasibilityQuestion = document.getElementById('feasibility-question')
const feasibilitySource = document.getElementById('feasibility-source')
const feasibilityRunRecorded = document.getElementById('feasibility-run-recorded')
const feasibilityStatus = document.getElementById('feasibility-status')
const feasibilityClassification = document.getElementById('feasibility-classification')
const feasibilityRevision = document.getElementById('feasibility-revision')
const feasibilityKeys = document.getElementById('feasibility-keys')
const feasibilitySummary = document.getElementById('feasibility-summary')
const feasibilityRubric = document.getElementById('feasibility-rubric')
const feasibilityHash = document.getElementById('feasibility-hash')

let isStreaming = false
let abortStream = false
let previousNodeIds = new Set()
let jsxModule = null
let jsxSessionHandle = null
let jsxSessionRevision = null
let dataRows = ORDER_ROWS
let dataSource = 'JSON fixture'
let selectedOrderId = null

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

dataFilterInput.addEventListener('input', renderDataExplorer)
dataFilterClear.addEventListener('click', function() {
  dataFilterInput.value = '';
  renderDataExplorer();
  dataFilterInput.focus();
});

dataJsonSource.addEventListener('click', function() {
  setDataSource(ORDER_ROWS, 'JSON fixture');
});

dataCsvSource.addEventListener('click', function() {
  setDataSource(parseOrdersCsv(ORDERS_CSV_FIXTURE), 'CSV fixture');
});

function renderDataExplorer() {
  const view = deriveOrderView(dataRows, dataFilterInput.value, selectedOrderId);
  const summary = summarizeOrders(view.rows);
  const focusedOrderId = document.activeElement instanceof HTMLElement
    ? document.activeElement.dataset.orderId ?? null
    : null;
  dataRowCount.textContent = String(view.rows.length);
  dataSummaryCount.textContent = String(summary.count);
  dataSummaryTotal.textContent = formatOrderAmount(summary.totalAmount);
  dataSummaryAverage.textContent = formatOrderAmount(summary.averageAmount);
  dataSourceLabel.textContent = dataSource;
  ordersTableBody.replaceChildren();

  for (const row of view.rows) {
    const tr = document.createElement('tr');
    tr.className = 'order-row' + (row.id === selectedOrderId ? ' selected' : '');
    tr.dataset.orderId = row.id;
    tr.dataset.testid = 'order-row-' + row.id;
    tr.tabIndex = 0;
    tr.setAttribute('aria-selected', String(row.id === selectedOrderId));
    tr.addEventListener('click', () => selectDataRow(row.id));
    tr.addEventListener('keydown', (event) => {
      if (event.key === 'Enter' || event.key === ' ') {
        event.preventDefault();
        selectDataRow(row.id);
      }
    });

    appendOrderCell(tr, row.id, 'text-canopy-muted');
    appendOrderCell(tr, row.name, 'text-canopy-text');
    const statusCell = appendOrderCell(tr, '', '');
    const status = document.createElement('span');
    status.className = 'status-chip status-' + row.status;
    status.textContent = row.status;
    statusCell.append(status);
    appendOrderCell(tr, formatOrderAmount(row.amount), 'text-right text-canopy-text');
    ordersTableBody.append(tr);
  }

  if (focusedOrderId !== null) {
    for (const candidate of ordersTableBody.children) {
      if (candidate instanceof HTMLElement && candidate.dataset.orderId === focusedOrderId) {
        candidate.focus();
        break;
      }
    }
  }

  if (view.selected === null) {
    dataSelectionStatus.textContent = 'No row selected.';
    dataDetailEmpty.hidden = false;
    dataDetailContent.hidden = true;
  } else {
    const hiddenSuffix = view.selectedVisible ? '' : ' — hidden by filter.';
    dataSelectionStatus.textContent = 'Selected: ' + view.selected.name + ' (' + view.selected.id + ')' + hiddenSuffix;
    renderOrderDetail(view.selected);
  }
}

function setDataSource(rows, label) {
  dataRows = rows;
  dataSource = label;
  selectedOrderId = selectOrder(dataRows, selectedOrderId ?? '');
  dataJsonSource.setAttribute('aria-pressed', String(label === 'JSON fixture'));
  dataCsvSource.setAttribute('aria-pressed', String(label === 'CSV fixture'));
  renderDataExplorer();
}

function selectDataRow(id) {
  selectedOrderId = selectOrder(dataRows, id);
  renderDataExplorer();
}

function renderOrderDetail(row) {
  dataDetailEmpty.hidden = true;
  dataDetailContent.hidden = false;
  dataDetailId.textContent = row.id;
  dataDetailName.textContent = row.name;
  dataDetailStatus.textContent = row.status;
  dataDetailAmount.textContent = formatOrderAmount(row.amount);
}

function appendOrderCell(row, value, className) {
  const cell = document.createElement('td');
  cell.className = 'px-3 py-2 ' + className;
  cell.textContent = value;
  row.append(cell);
  return cell;
}

function formatOrderAmount(amount) {
  return new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD' }).format(amount);
}

let selectedFeasibilityCaseId = 'orders-pending-attention'
let feasibilitySessionHandle = null
let feasibilitySessionRevision = null
let feasibilityBusy = false
let feasibilityLastSuccessfulResult = null

function setFeasibilityCase(caseId) {
  const input = recordedDemoInput(caseId)
  selectedFeasibilityCaseId = caseId
  feasibilityQuestion.textContent = input.fixture.question
  feasibilitySource.textContent = `${input.fixture.sourceFormat} · @${input.fixture.binding} · ${input.fixture.fields.length} fields`
  document.querySelectorAll('[data-feasibility-case]').forEach((button) => {
    button.classList.toggle('active', button.dataset.feasibilityCase === caseId)
  })
  resetFeasibilitySession()
  resetFeasibilityEvidence()
}

function resetFeasibilitySession() {
  if (jsxModule && feasibilitySessionHandle !== null) {
    jsxModule.jsx_session_dispose(feasibilitySessionHandle)
  }
  feasibilitySessionHandle = null
  feasibilitySessionRevision = null
  feasibilityLastSuccessfulResult = null
  document.getElementById('feasibility-preview').innerHTML =
    '<div class="flex min-h-[180px] items-center justify-center text-center text-[11px] leading-5 text-canopy-muted">Run the recorded candidate to materialize a safe projection.</div>'
}

function resetFeasibilityEvidence() {
  feasibilityStatus.textContent = 'Ready. No provider request has been made.'
  feasibilityClassification.textContent = '—'
  feasibilityRevision.textContent = '—'
  feasibilityKeys.textContent = '—'
  feasibilitySummary.textContent = '—'
  feasibilityRubric.textContent = '—'
  feasibilityHash.textContent = '—'
}

async function ensureFeasibilityModule() {
  if (!jsxModule) jsxModule = await import('@moonbit/crdt-jsx')
}

async function ensureFeasibilitySession() {
  await ensureFeasibilityModule()
  if (feasibilitySessionHandle !== null) return
  const created = JSON.parse(jsxModule.jsx_session_new('<div>initial</div>', 'feasibility-preview'))
  if (!created.success || created.handle === null) {
    throw new Error(created.result?.error?.message || 'Could not create the dedicated feasibility session.')
  }
  feasibilitySessionHandle = Number(created.handle)
  feasibilitySessionRevision = Number(created.result.revision)
}

async function resetSlotSession() {
  resetFeasibilitySession()
  await ensureFeasibilitySession()
}

async function evaluateFeasibilityCandidate(candidateJson, input) {
  await ensureFeasibilityModule()
  return executeFeasibilityCandidate({
    mode: 'evaluate',
    candidateJson,
    fixture: input,
    evaluateCandidate: (rawCandidate, capabilitiesJson, datasetJson) =>
      jsxModule.__jsx_evaluate_feasibility_candidate_json(rawCandidate, capabilitiesJson, datasetJson),
    commitCandidate: null,
  })
}

async function commitFeasibilityCandidate(candidateJson, input) {
  await ensureFeasibilitySession()
  const result = await executeFeasibilityCandidate({
    mode: 'commit',
    candidateJson,
    fixture: input,
    evaluateCandidate: null,
    commitCandidate: (rawCandidate, capabilitiesJson, datasetJson) =>
      jsxModule.__jsx_commit_feasibility_candidate_json(
        feasibilitySessionHandle,
        feasibilitySessionRevision,
        rawCandidate,
        capabilitiesJson,
        datasetJson,
      ),
  })
  if (result.classification === 'success' && result.session?.success) {
    feasibilitySessionRevision = Number(result.session.revision)
  }
  return result
}

function renderFeasibilityAttempt(result) {
  const success = result.classification === 'success' && result.session?.success
  if (success || feasibilityLastSuccessfulResult === null) {
    renderFeasibilityEvidence(result)
  }
  if (success) {
    feasibilityLastSuccessfulResult = result
    feasibilityStatus.textContent = 'Committed after MoonBit preparation, rubric, dry-run, and DOM apply.'
  } else {
    feasibilityStatus.textContent =
      `Rejected without commit: ${result.message || result.session?.error?.message || result.classification || 'unknown error'}`
  }
}

function renderFeasibilityEvidence(result) {
  const success = result.classification === 'success' && result.session?.success
  feasibilityClassification.textContent = result.classification || 'unknown'
  feasibilityClassification.className = `mt-0.5 ${success ? 'text-canopy-green' : 'text-[#f48771]'}`
  feasibilityRevision.textContent = result.session?.revision == null ? '—' : String(result.session.revision)
  feasibilityKeys.textContent = result.evidence?.matched_stable_keys?.join(', ') || '—'
  const summary = result.evidence?.summary
  feasibilitySummary.textContent = summary == null ? '—' : `${summary.aggregation}(${summary.field}) = ${summary.value ?? 'null'}`
  feasibilityRubric.textContent = result.rubric == null
    ? '—'
    : result.rubric.passed ? 'passed' : `failed: ${result.rubric.reasons.join('; ')}`
  feasibilityHash.textContent = result.safe_output_sha256 || '—'
}

async function runFeasibilityAction(candidateJson, input, button, pendingLabel) {
  if (feasibilityBusy) return
  feasibilityBusy = true
  button.disabled = true
  const previousLabel = button.textContent
  button.textContent = pendingLabel
  feasibilityStatus.textContent = 'Preparing candidate…'
  try {
    renderFeasibilityAttempt(await commitFeasibilityCandidate(candidateJson, input))
  } catch (error) {
    feasibilityStatus.textContent = `Candidate transaction failed: ${error instanceof Error ? error.message : String(error)}`
    if (feasibilityLastSuccessfulResult === null) {
      feasibilityClassification.textContent = 'client_failure'
      feasibilityClassification.className = 'mt-0.5 text-[#f48771]'
    }
  } finally {
    button.disabled = false
    button.textContent = previousLabel
    feasibilityBusy = false
  }
}

document.querySelectorAll('[data-feasibility-case]').forEach((button) => {
  button.addEventListener('click', () => setFeasibilityCase(button.dataset.feasibilityCase))
})

feasibilityRunRecorded.addEventListener('click', () => {
  const input = recordedDemoInput(selectedFeasibilityCaseId)
  return runFeasibilityAction(input.candidateJson, input, feasibilityRunRecorded, 'Replaying…')
})

if (import.meta.env.DEV) {
  window.__canopyGenUiFeasibilityTest = Object.freeze({
    async runSlot({ studyId, runCapability, caseId, slotId }) {
      const input = recordedDemoInput(caseId)
      const request = buildLiveStudyRequest({ studyId, runCapability, caseId, slotId })
      await resetSlotSession()
      const response = await fetch('/api/genui-feasibility', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify(request),
      })
      const provider = await response.json()
      if (!response.ok || provider.classification !== 'success' || typeof provider.candidateJson !== 'string') {
        return provider
      }
      const result = await commitFeasibilityCandidate(provider.candidateJson, input)
      return {
        candidateJson: provider.candidateJson,
        ...result,
        revision: result.session?.revision ?? null,
        provider,
      }
    },
    async commitSavedCandidate({ caseId, candidateJson }) {
      await resetSlotSession()
      return commitFeasibilityCandidate(candidateJson, recordedDemoInput(caseId))
    },
    async evaluateSavedCandidate({ caseId, candidateJson }) {
      return evaluateFeasibilityCandidate(candidateJson, recordedDemoInput(caseId))
    },
    resetSlotSession,
  })
}

setFeasibilityCase(selectedFeasibilityCaseId)

renderDataExplorer();

function resetState() {
  if (jsxModule && jsxSessionHandle !== null) {
    jsxModule.jsx_session_dispose(jsxSessionHandle)
    jsxSessionHandle = null
    jsxSessionRevision = null
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

async function replayCandidate(candidateJson, capabilitiesJson) {
  if (!jsxModule) jsxModule = await import('@moonbit/crdt-jsx')
  if (jsxSessionHandle === null) {
    const created = JSON.parse(jsxModule.jsx_session_new('<div>initial</div>', 'html-preview'))
    if (!created.success || created.handle === null) return created.result
    jsxSessionHandle = Number(created.handle)
    jsxSessionRevision = created.result.revision
  }
  return replayCandidateAtRevision(jsxSessionRevision, candidateJson, capabilitiesJson)
}

async function replayCandidateAtRevision(baseRevision, candidateJson, capabilitiesJson) {
  if (!jsxModule) jsxModule = await import('@moonbit/crdt-jsx')
  if (jsxSessionHandle === null) throw new Error('candidate session is not initialized')
  const split = Math.max(1, Math.floor(candidateJson.length / 2))
  const chunks = candidateJson.slice(0, split) + '\u0000' + candidateJson.slice(split)
  const result = JSON.parse(
    jsxModule.jsx_session_replay_candidate_json(
      jsxSessionHandle,
      baseRevision,
      chunks,
      capabilitiesJson,
    ),
  )
  if (result.success) {
    jsxSessionRevision = result.revision
    htmlNodeCount.textContent = String(result.mounted_ids.length)
  }
  return result
}

function requireJsxSession() {
  if (!jsxModule || jsxSessionHandle === null) throw new Error('candidate session is not initialized');
}

function sessionNewForTest(rootId) {
  if (!jsxModule) throw new Error('JSX module is not initialized');
  const created = JSON.parse(jsxModule.jsx_session_new('<div>initial</div>', rootId));
  return {
    success: created.success,
    handle: Number(created.handle),
    revision: created.result?.revision ?? null,
  };
}

function sessionDisposeForTest(handle) {
  if (!jsxModule) throw new Error('JSX module is not initialized');
  jsxModule.jsx_session_dispose(handle);
}

function asyncDriverNewForSession(sessionHandle, baseRevision) {
  if (!jsxModule) throw new Error('JSX module is not initialized');
  return JSON.parse(jsxModule.__jsx_async_driver_new(sessionHandle, baseRevision));
}

function asyncDriverNew(baseRevision) {
  requireJsxSession();
  return JSON.parse(jsxModule.__jsx_async_driver_new(jsxSessionHandle, baseRevision));
}

function asyncDriverStart(driverHandle) {
  return JSON.parse(jsxModule.__jsx_async_driver_start(driverHandle));
}

function asyncDriverQueueChunk(driverHandle, generationId, baseRevision, sequence, payload) {
  jsxModule.__jsx_async_driver_queue_chunk(driverHandle, generationId, baseRevision, sequence, payload);
}

function asyncDriverQueueFinal(driverHandle, generationId, baseRevision, sequence) {
  jsxModule.__jsx_async_driver_queue_final(driverHandle, generationId, baseRevision, sequence);
}

function asyncDriverQueueFailure(driverHandle, generationId, baseRevision, sequence, code, message) {
  jsxModule.__jsx_async_driver_queue_failure(driverHandle, generationId, baseRevision, sequence, code, message);
}

async function asyncDriverResolveNext(driverHandle) {
  return JSON.parse(await jsxModule.__jsx_async_driver_resolve_next(driverHandle));
}

async function asyncDriverWaitNext(driverHandle) {
  return JSON.parse(await jsxModule.__jsx_async_driver_wait_next(driverHandle));
}

function asyncDriverResolveCurrent(driverHandle) {
  jsxModule.__jsx_async_driver_resolve_current(driverHandle);
}

function asyncDriverProviderNew(driverHandle, generationId, baseRevision, sequence) {
  return JSON.parse(
    jsxModule.__jsx_async_driver_provider_new(
      driverHandle,
      generationId,
      baseRevision,
      sequence,
    ),
  );
}

async function asyncDriverProviderWait(providerHandle) {
  return JSON.parse(await jsxModule.__jsx_async_driver_provider_wait(providerHandle));
}

function asyncDriverProviderReject(providerHandle, code, message) {
  jsxModule.__jsx_async_driver_provider_reject(providerHandle, code, message);
}

function asyncDriverProviderAbort(providerHandle) {
  jsxModule.__jsx_async_driver_provider_abort(providerHandle);
}

function asyncDriverCancel(driverHandle) {
  return JSON.parse(jsxModule.__jsx_async_driver_cancel(driverHandle));
}

function asyncDriverRestart(driverHandle, baseRevision) {
  return JSON.parse(jsxModule.__jsx_async_driver_restart(driverHandle, baseRevision));
}

function asyncDriverCommit(driverHandle, capabilitiesJson) {
  const result = JSON.parse(jsxModule.__jsx_async_driver_commit(driverHandle, capabilitiesJson));
  if (result.success) {
    jsxSessionRevision = result.revision;
    htmlNodeCount.textContent = String(result.mounted_ids.length);
  }
  return result;
}

function asyncDriverStats(driverHandle) {
  return JSON.parse(jsxModule.__jsx_async_driver_stats(driverHandle));
}

function asyncDriverDispose(driverHandle) {
  jsxModule.__jsx_async_driver_dispose(driverHandle);
}

if (import.meta.env.DEV) {
  window.__canopyGenUiTest = Object.freeze({
    sessionNewForTest,
    sessionDisposeForTest,
    asyncDriverNewForSession,
    replayCandidate,
    replayCandidateAtRevision,
    sessionRevision: () => jsxSessionRevision,
    resetSession: resetState,
    asyncDriverNew,
    asyncDriverStart,
    asyncDriverQueueChunk,
    asyncDriverQueueFinal,
    asyncDriverQueueFailure,
    asyncDriverResolveNext,
    asyncDriverWaitNext,
    asyncDriverResolveCurrent,
    asyncDriverProviderNew,
    asyncDriverProviderWait,
    asyncDriverProviderReject,
    asyncDriverProviderAbort,
    asyncDriverCancel,
    asyncDriverRestart,
    asyncDriverCommit,
    asyncDriverStats,
    asyncDriverDispose,
  })
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
      jsxSessionRevision = null
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
      jsxSessionRevision = renderResult.revision
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
