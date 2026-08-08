'use client';
import { adaptMoonBitModule } from '@canopy/editor-adapter/moonbit-result';
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

const DEFAULT_RUNTIME = Object.freeze({
  loadJsx: () => import('@moonbit/crdt-jsx'),
});

const MAX_RECORDED_RESTORE_STEPS = 1_000

function splitStreamPrefixes(source) {
  const prefixes = []
  let lastSplit = 0
  for (let index = 0; index < source.length; index += 1) {
    if (source[index] === '>' && index - lastSplit >= 10) {
      prefixes.push(source.slice(0, index + 1))
      lastSplit = index
    }
  }
  if (prefixes[prefixes.length - 1] !== source) prefixes.push(source)
  return prefixes
}

function readSnapshot(value) {
  if (typeof value !== 'object' || value === null || Array.isArray(value)) return null;
  return value.version === 1 ? value : null;
}

export function mountGenui(
  root = globalThis.document,
  restoredSnapshot = undefined,
  runtime = DEFAULT_RUNTIME,
) {
const document = root.ownerDocument ?? root
const window = document.defaultView ?? globalThis.window
const surface = root.querySelector('.genui-surface')
const snapshot = readSnapshot(restoredSnapshot)
const listenerController = new window.AbortController()
const liveRequestControllers = new Set()
const testSessionHandles = new Set()
const asyncDriverHandles = new Set()
const asyncProviderHandles = new Set()
let disposed = false
let ready = false
let pendingFocusToken = null
let streamDelayCancel = null

const sourceInput = root.querySelector('#source-input')
const streamBtn = root.querySelector('#stream-btn')
const clearBtn = root.querySelector('#clear-btn')
const treeOutput = root.querySelector('#tree-output')
const htmlPreview = root.querySelector('#html-preview')
const errorsList = root.querySelector('#errors-list')
const stepNum = root.querySelector('#step-num')
const htmlStepNum = root.querySelector('#html-step-num')
const htmlNodeCount = root.querySelector('#html-node-count')
const streamProgress = root.querySelector('#stream-progress')
const statusBar = root.querySelector('#status-bar')
const dataFilterInput = root.querySelector('#data-filter-input')
const dataFilterClear = root.querySelector('#data-filter-clear')
const dataJsonSource = root.querySelector('#data-json-source')
const dataCsvSource = root.querySelector('#data-csv-source')

const dataSourceLabel = root.querySelector('#data-source-label')
const dataRowCount = root.querySelector('#data-row-count')
const dataSummaryCount = root.querySelector('#data-summary-count')
const dataSummaryTotal = root.querySelector('#data-summary-total')
const dataSummaryAverage = root.querySelector('#data-summary-average')
const ordersTableBody = root.querySelector('#orders-table-body')
const dataSelectionStatus = root.querySelector('#data-selection-status')
const dataDetailEmpty = root.querySelector('#data-detail-empty')
const dataDetailContent = root.querySelector('#data-detail-content')
const dataDetailId = root.querySelector('#data-detail-id')
const dataDetailName = root.querySelector('#data-detail-name')
const dataDetailStatus = root.querySelector('#data-detail-status')
const dataDetailAmount = root.querySelector('#data-detail-amount')
const feasibilityPreview = root.querySelector('#feasibility-preview')
const feasibilityQuestion = root.querySelector('#feasibility-question')
const feasibilitySource = root.querySelector('#feasibility-source')
const feasibilityRunRecorded = root.querySelector('#feasibility-run-recorded')
const feasibilityStatus = root.querySelector('#feasibility-status')
const feasibilityClassification = root.querySelector('#feasibility-classification')
const feasibilityRevision = root.querySelector('#feasibility-revision')
const feasibilityKeys = root.querySelector('#feasibility-keys')
const feasibilitySummary = root.querySelector('#feasibility-summary')
const feasibilityRubric = root.querySelector('#feasibility-rubric')
const feasibilityHash = root.querySelector('#feasibility-hash')

let isStreaming = false
let streamRunId = 0
let previousNodeIds = new Set()
let jsxModule = null
let jsxModulePromise = null
let jsxSessionHandle = null
let jsxSessionRevision = null
let committedJsxSource = null
let committedJsxRevision = null
let dataRows = snapshot?.explorer?.source === 'csv'
  ? parseOrdersCsv(ORDERS_CSV_FIXTURE)
  : ORDER_ROWS
let dataSource = snapshot?.explorer?.source === 'csv' ? 'CSV fixture' : 'JSON fixture'
let selectedOrderId = selectOrder(dataRows, snapshot?.explorer?.selectedOrderId ?? '')

if (typeof snapshot?.jsxSource === 'string') sourceInput.value = snapshot.jsxSource
if (typeof snapshot?.explorer?.filter === 'string') dataFilterInput.value = snapshot.explorer.filter
if (
  typeof snapshot?.committed?.source === 'string' &&
  Number.isSafeInteger(snapshot?.committed?.revision) &&
  snapshot.committed.revision > 0
) {
  committedJsxSource = snapshot.committed.source
  committedJsxRevision = snapshot.committed.revision
}

root.querySelectorAll('[data-example]').forEach(function(btn) {
  btn.addEventListener('click', function() {
    if (isStreaming) return;
    sourceInput.value = EXAMPLES[parseInt(btn.dataset.example)];
    resetState();
    statusBar.textContent = 'Example loaded. Click \u25B6 Stream.';
  }, { signal: listenerController.signal });
});

root.querySelectorAll('.view-tab').forEach(function(tab) {
  tab.addEventListener('click', function() {
    const view = tab.dataset.view;
    tab.parentElement.querySelectorAll('.view-tab').forEach(function(t) { t.classList.remove('active'); });
    tab.classList.add('active');
    tab.parentElement.parentElement.querySelectorAll('.view-panel').forEach(function(p) { p.classList.remove('active'); });
    const panel = root.querySelector('#view-' + view)
    panel.classList.add('active');
    panel.style.display = 'flex';
  }, { signal: listenerController.signal });
});

clearBtn.addEventListener('click', function() {
  cancelStream();
  streamBtn.disabled = false;
  streamBtn.textContent = '\u25B6 Stream';
  streamBtn.className = 'btn-primary';
  resetState();
  statusBar.textContent = 'Cleared.';
}, { signal: listenerController.signal });

dataFilterInput.addEventListener('input', renderDataExplorer, { signal: listenerController.signal })
dataFilterClear.addEventListener('click', function() {
  dataFilterInput.value = '';
  renderDataExplorer();
  dataFilterInput.focus();
}, { signal: listenerController.signal });

dataJsonSource.addEventListener('click', function() {
  setDataSource(ORDER_ROWS, 'JSON fixture');
}, { signal: listenerController.signal });

dataCsvSource.addEventListener('click', function() {
  setDataSource(parseOrdersCsv(ORDERS_CSV_FIXTURE), 'CSV fixture');
}, { signal: listenerController.signal });

function renderDataExplorer() {
  const view = deriveOrderView(dataRows, dataFilterInput.value, selectedOrderId);
  const summary = summarizeOrders(view.rows);
  const focusedOrderId = document.activeElement instanceof window.HTMLElement
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
    tr.dataset.routeFocus = 'order:' + row.id;
    tr.addEventListener('click', () => selectDataRow(row.id), { signal: listenerController.signal });
    tr.addEventListener('keydown', (event) => {
      if (event.key === 'Enter' || event.key === ' ') {
        event.preventDefault();
        selectDataRow(row.id);
      }
    }, { signal: listenerController.signal });

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
      if (candidate instanceof window.HTMLElement && candidate.dataset.orderId === focusedOrderId) {
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

const restoredCaseIds = new Set([
  'orders-pending-attention',
  'inventory-low-stock',
  'incidents-critical-resolution',
])
let selectedFeasibilityCaseId = restoredCaseIds.has(snapshot?.recordedCaseId)
  ? snapshot.recordedCaseId
  : 'orders-pending-attention'
let feasibilitySessionHandle = null
let feasibilitySessionRevision = null
let feasibilityBusy = false
let feasibilityLastSuccessfulResult = null
let committedRecordedRevision = Number.isSafeInteger(snapshot?.recordedRevision) && snapshot.recordedRevision > 0
  ? snapshot.recordedRevision
  : null
let feasibilityTestApi = null

function setFeasibilityCase(caseId, clearCommitted = true) {
  const input = recordedDemoInput(caseId)
  selectedFeasibilityCaseId = caseId
  if (clearCommitted) committedRecordedRevision = null
  feasibilityQuestion.textContent = input.fixture.question
  feasibilitySource.textContent = `${input.fixture.sourceFormat} · @${input.fixture.binding} · ${input.fixture.fields.length} fields`
  root.querySelectorAll('[data-feasibility-case]').forEach((button) => {
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
  feasibilityPreview.innerHTML =
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

async function ensureJsxModule() {
  if (jsxModule) return
  const loadPromise = jsxModulePromise ?? runtime.loadJsx()
  jsxModulePromise = loadPromise
  let loaded
  try {
    loaded = await loadPromise
  } catch (error) {
    if (jsxModulePromise === loadPromise) jsxModulePromise = null
    throw error
  }
  if (disposed) throw new Error('GenUI session was disposed before the JSX runtime loaded.')
  jsxModule = adaptMoonBitModule(loaded)
}

async function ensureFeasibilitySession() {
  await ensureJsxModule()
  if (disposed) throw new Error('GenUI session is disposed.')
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
  await ensureJsxModule()
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
  if (feasibilityBusy || disposed) return null
  feasibilityBusy = true
  button.disabled = true
  const previousLabel = button.textContent
  button.textContent = pendingLabel
  feasibilityStatus.textContent = 'Preparing candidate…'
  try {
    const result = await commitFeasibilityCandidate(candidateJson, input)
    if (disposed) return result
    renderFeasibilityAttempt(result)
    return result
  } catch (error) {
    if (disposed) return null
    feasibilityStatus.textContent = `Candidate transaction failed: ${error instanceof Error ? error.message : String(error)}`
    if (feasibilityLastSuccessfulResult === null) {
      feasibilityClassification.textContent = 'client_failure'
      feasibilityClassification.className = 'mt-0.5 text-[#f48771]'
    }
  } finally {
    if (!disposed) {
      button.disabled = false
      button.textContent = previousLabel
    }
    feasibilityBusy = false
  }
}

root.querySelectorAll('[data-feasibility-case]').forEach((button) => {
  button.addEventListener(
    'click',
    () => setFeasibilityCase(button.dataset.feasibilityCase),
    { signal: listenerController.signal },
  )
})

feasibilityRunRecorded.addEventListener('click', async () => {
  const input = recordedDemoInput(selectedFeasibilityCaseId)
  const result = await runFeasibilityAction(
    input.candidateJson,
    input,
    feasibilityRunRecorded,
    'Replaying…',
  )
  if (result?.classification === 'success' && result.session?.success) {
    committedRecordedRevision = Number(result.session.revision)
  }
}, { signal: listenerController.signal })

if (import.meta.env.DEV) {
  feasibilityTestApi = Object.freeze({
    async runSlot({ studyId, runCapability, caseId, slotId }) {
      const input = recordedDemoInput(caseId)
      const request = buildLiveStudyRequest({ studyId, runCapability, caseId, slotId })
      await resetSlotSession()
      const controller = new window.AbortController()
      liveRequestControllers.add(controller)
      try {
        const response = await window.fetch('/api/genui-feasibility', {
          method: 'POST',
          headers: { 'content-type': 'application/json' },
          body: JSON.stringify(request),
          signal: controller.signal,
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
      } finally {
        liveRequestControllers.delete(controller)
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
  window.__canopyGenUiFeasibilityTest = feasibilityTestApi
}

setFeasibilityCase(selectedFeasibilityCaseId, false)

dataJsonSource.setAttribute('aria-pressed', String(dataSource === 'JSON fixture'))
dataCsvSource.setAttribute('aria-pressed', String(dataSource === 'CSV fixture'))
renderDataExplorer();

function resetState() {
  if (jsxModule && jsxSessionHandle !== null) {
    jsxModule.jsx_session_dispose(jsxSessionHandle)
  }
  jsxSessionHandle = null
  jsxSessionRevision = null
  committedJsxSource = null
  committedJsxRevision = null
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
  await ensureJsxModule()
  if (jsxSessionHandle === null) {
    const created = JSON.parse(jsxModule.jsx_session_new('<div>initial</div>', 'html-preview'))
    if (!created.success || created.handle === null) return created.result
    jsxSessionHandle = Number(created.handle)
    jsxSessionRevision = created.result.revision
  }
  return replayCandidateAtRevision(jsxSessionRevision, candidateJson, capabilitiesJson)
}

async function replayCandidateAtRevision(baseRevision, candidateJson, capabilitiesJson) {
  await ensureJsxModule()
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
    committedJsxSource = null
    committedJsxRevision = null
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
  const result = {
    success: created.success,
    handle: Number(created.handle),
    revision: created.result?.revision ?? null,
  };
  if (result.success && Number.isFinite(result.handle)) testSessionHandles.add(result.handle)
  return result
}

function sessionDisposeForTest(handle) {
  if (!jsxModule) throw new Error('JSX module is not initialized');
  jsxModule.jsx_session_dispose(handle);
  testSessionHandles.delete(handle)
}

function asyncDriverNewForSession(sessionHandle, baseRevision) {
  if (!jsxModule) throw new Error('JSX module is not initialized');
  const result = JSON.parse(jsxModule.__jsx_async_driver_new(sessionHandle, baseRevision));
  asyncDriverHandles.add(result.driver_handle)
  return result
}

function asyncDriverNew(baseRevision) {
  requireJsxSession();
  const result = JSON.parse(jsxModule.__jsx_async_driver_new(jsxSessionHandle, baseRevision));
  asyncDriverHandles.add(result.driver_handle)
  return result
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
  const result = JSON.parse(
    jsxModule.__jsx_async_driver_provider_new(
      driverHandle,
      generationId,
      baseRevision,
      sequence,
    ),
  );
  asyncProviderHandles.add(result.provider_handle)
  return result
}

async function asyncDriverProviderWait(providerHandle) {
  try {
    return JSON.parse(await jsxModule.__jsx_async_driver_provider_wait(providerHandle));
  } finally {
    asyncProviderHandles.delete(providerHandle)
  }
}

function asyncDriverProviderReject(providerHandle, code, message) {
  jsxModule.__jsx_async_driver_provider_reject(providerHandle, code, message);
  asyncProviderHandles.delete(providerHandle)
}

function asyncDriverProviderAbort(providerHandle) {
  jsxModule.__jsx_async_driver_provider_abort(providerHandle);
  asyncProviderHandles.delete(providerHandle)
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
    committedJsxSource = null
    committedJsxRevision = null
    htmlNodeCount.textContent = String(result.mounted_ids.length);
  }
  return result;
}

function asyncDriverStats(driverHandle) {
  return JSON.parse(jsxModule.__jsx_async_driver_stats(driverHandle));
}

function asyncDriverDispose(driverHandle) {
  jsxModule.__jsx_async_driver_dispose(driverHandle);
  asyncDriverHandles.delete(driverHandle)
}

let genuiTestApi = null
if (import.meta.env.DEV) {
  genuiTestApi = Object.freeze({
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
  window.__canopyGenUiTest = genuiTestApi
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

function cancelStream() {
  streamRunId += 1
  isStreaming = false
  streamDelayCancel?.()
  streamDelayCancel = null
}

function waitForStreamDelay(delayMs) {
  return new Promise((resolve) => {
    let settled = false
    const finish = () => {
      if (settled) return
      settled = true
      window.clearTimeout(timer)
      if (streamDelayCancel === finish) streamDelayCancel = null
      resolve()
    }
    const timer = window.setTimeout(finish, delayMs)
    streamDelayCancel = finish
  })
}

// ── Streaming (MoonBit render via a stateful JSX FFI session) ──
streamBtn.addEventListener('click', async function() {
  if (isStreaming) {
    cancelStream()
    streamBtn.textContent = '\u25B6 Stream'
    streamBtn.className = 'btn-primary'
    statusBar.textContent = 'Stopped.'
    return
  }
  const fullText = sourceInput.value;
  if (!fullText.trim()) { statusBar.textContent = 'Please enter JSX text.'; return; }
  const runId = ++streamRunId
  isStreaming = true
  streamBtn.textContent = '\u25A0 Stop'; streamBtn.className = 'btn-primary';
  previousNodeIds = new Set();
  htmlPreview.innerHTML = '';
  statusBar.textContent = 'Loading MoonBit JSX module...';

  // Split at JSX syntactic boundaries (after `>`) so each prefix ends at a
  // complete tag opening or closing, avoiding "truncated tag" / "unterminated
  // attribute" diagnostics from mid-attribute cuts.
  const prefixes = splitStreamPrefixes(fullText)

  try {
    await ensureJsxModule()
    if (disposed || runId !== streamRunId) return
    const JsxMod = jsxModule
    if (jsxSessionHandle !== null) {
      JsxMod.jsx_session_dispose(jsxSessionHandle);
      jsxSessionHandle = null;
      jsxSessionRevision = null
    }
    statusBar.textContent = 'Streaming ' + prefixes.length + ' steps...';
    let finalIds = [];
    for (let si = 0; si < prefixes.length; si++) {
      if (disposed || runId !== streamRunId) return
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
      await waitForStreamDelay(si < 5 ? 60 : 100)
      if (disposed || runId !== streamRunId) return
    }
    if (disposed || runId !== streamRunId) return
    committedJsxSource = fullText
    committedJsxRevision = jsxSessionRevision
    statusBar.className = 'mt-2 p-1.5 bg-canopy-bg rounded-md text-[11px] text-canopy-muted';
    statusBar.textContent = 'Complete \u2014 ' + finalIds.length + ' DOM nodes rendered.';
  } catch (err) {
    if (disposed || runId !== streamRunId) return
    console.error(err);
    statusBar.className = 'mt-2 p-1.5 bg-canopy-bg rounded-md text-[11px] text-canopy-red';
    statusBar.textContent = 'Error: ' + err.message;
    treeOutput.innerHTML = '<div class="text-center py-8 text-canopy-red text-xs">Error: ' + esc(err.message) + '</div>';
  }
  if (runId !== streamRunId) return
  isStreaming = false;
  streamBtn.textContent = '\u25B6 Stream';
  streamBtn.className = 'btn-primary';
}, { signal: listenerController.signal });

async function restoreMainCommit() {
  if (committedJsxSource === null || committedJsxRevision === null) return
  await ensureJsxModule()
  if (disposed) return
  const targetRevision = committedJsxRevision
  const prefixes = splitStreamPrefixes(committedJsxSource)
  htmlPreview.replaceChildren()
  const created = JSON.parse(jsxModule.jsx_session_new(prefixes[0], 'html-preview'))
  if (!created.success || created.handle === null) {
    throw new Error(created.result?.error?.message || 'Could not restore the committed JSX session.')
  }
  jsxSessionHandle = Number(created.handle)
  let result = created.result
  let prefixIndex = 1
  while (!disposed && Number(result.revision) < targetRevision) {
    if (prefixIndex >= prefixes.length) {
      throw new Error(`Could not reach committed JSX revision ${targetRevision}.`)
    }
    const previousRevision = Number(result.revision)
    result = JSON.parse(jsxModule.jsx_session_render(jsxSessionHandle, prefixes[prefixIndex]))
    if (!result.success) {
      throw new Error(result.error?.message || 'Could not restore the committed JSX revision.')
    }
    const restoredRevision = Number(result.revision)
    if (!Number.isSafeInteger(restoredRevision) || restoredRevision <= previousRevision) {
      throw new Error('Committed JSX restoration did not advance its revision.')
    }
    prefixIndex += 1
  }
  if (disposed) return
  if (Number(result.revision) !== targetRevision) {
    throw new Error(`Could not reach committed JSX revision ${targetRevision}.`)
  }
  jsxSessionRevision = Number(result.revision)
  htmlNodeCount.textContent = String(result.mounted_ids.length)
  statusBar.textContent = `Restored committed revision ${jsxSessionRevision}.`
}

async function restoreRecordedCommit() {
  if (committedRecordedRevision === null) return
  const targetRevision = committedRecordedRevision
  if (targetRevision > MAX_RECORDED_RESTORE_STEPS) {
    throw new Error(`Recorded revision ${targetRevision} exceeds the restore limit.`)
  }
  const input = recordedDemoInput(selectedFeasibilityCaseId)
  let result = null
  let previousRevision = 0
  let restoreSteps = 0
  do {
    if (restoreSteps >= MAX_RECORDED_RESTORE_STEPS) {
      throw new Error(`Could not reach recorded revision ${targetRevision}.`)
    }
    result = await commitFeasibilityCandidate(input.candidateJson, input)
    if (result.classification !== 'success' || !result.session?.success) {
      throw new Error(result.message || result.session?.error?.message || 'Could not restore recorded replay.')
    }
    const restoredRevision = Number(result.session.revision)
    if (!Number.isSafeInteger(restoredRevision) || restoredRevision <= previousRevision) {
      throw new Error('Recorded replay restoration did not advance its revision.')
    }
    previousRevision = restoredRevision
    restoreSteps += 1
  } while (!disposed && Number(result.session.revision) < targetRevision)
  if (disposed) return
  if (Number(result.session.revision) !== targetRevision) {
    throw new Error(`Could not reach recorded revision ${targetRevision}.`)
  }
  committedRecordedRevision = Number(result.session.revision)
  renderFeasibilityAttempt(result)
}

async function restoreCommittedState() {
  await restoreMainCommit()
  await restoreRecordedCommit()
}

function applyFocusToken(token) {
  if (token === 'heading') {
    const heading = root.querySelector('[data-route-heading]')
    if (!heading) return false
    heading.focus({ preventScroll: true })
    return true
  }
  if (token === 'source') {
    sourceInput.focus({ preventScroll: true })
    return true
  }
  if (!token.startsWith('order:')) return false
  const orderId = token.slice('order:'.length)
  const row = [...ordersTableBody.children].find(
    (candidate) => candidate.dataset?.orderId === orderId,
  )
  if (!row) return false
  row.focus({ preventScroll: true })
  return true
}

const restoration = restoreCommittedState()
  .catch((error) => {
    if (disposed) return
    if (typeof runtime.reportError === 'function') {
      runtime.reportError(error)
      return
    }
    statusBar.className = 'mt-2 p-1.5 bg-canopy-bg rounded-md text-[11px] text-canopy-red'
    statusBar.textContent = `Restore failed: ${error instanceof Error ? error.message : String(error)}`
  })
  .finally(() => {
    if (disposed) return
    surface?.removeAttribute('inert')
    if (surface) surface.dataset.genuiReady = 'true'
    ready = true
    if (pendingFocusToken !== null) {
      applyFocusToken(pendingFocusToken)
      pendingFocusToken = null
    } else if (document.activeElement === document.body) {
      root.querySelector('[data-route-heading]')?.focus({ preventScroll: true })
    }
  })

return {
  snapshot() {
    return {
      version: 1,
      jsxSource: sourceInput.value,
      committed: committedJsxSource === null || committedJsxRevision === null
        ? null
        : { source: committedJsxSource, revision: committedJsxRevision },
      recordedCaseId: selectedFeasibilityCaseId,
      recordedRevision: committedRecordedRevision,
      explorer: {
        source: dataSource === 'CSV fixture' ? 'csv' : 'json',
        filter: dataFilterInput.value,
        selectedOrderId,
      },
    }
  },
  restoreFocus(token) {
    if (disposed) return false
    if (!ready) {
      if (token !== 'heading' && token !== 'source' && !token.startsWith('order:')) return false
      pendingFocusToken = token
      return true
    }
    return applyFocusToken(token)
  },
  dispose() {
    if (disposed) return
    disposed = true
    cancelStream()
    listenerController.abort()
    for (const controller of liveRequestControllers) controller.abort()
    liveRequestControllers.clear()
    if (jsxModule) {
      for (const providerHandle of asyncProviderHandles) {
        try { jsxModule.__jsx_async_driver_provider_abort(providerHandle) } catch {}
      }
      for (const driverHandle of asyncDriverHandles) {
        try { jsxModule.__jsx_async_driver_cancel(driverHandle) } catch {}
        try { jsxModule.__jsx_async_driver_dispose(driverHandle) } catch {}
      }
      for (const handle of testSessionHandles) {
        try { jsxModule.jsx_session_dispose(handle) } catch {}
      }
      if (jsxSessionHandle !== null) jsxModule.jsx_session_dispose(jsxSessionHandle)
      if (feasibilitySessionHandle !== null) jsxModule.jsx_session_dispose(feasibilitySessionHandle)
    }
    asyncProviderHandles.clear()
    asyncDriverHandles.clear()
    testSessionHandles.clear()
    jsxSessionHandle = null
    feasibilitySessionHandle = null
    void restoration
    if (import.meta.env.DEV) {
      if (window.__canopyGenUiTest === genuiTestApi) {
        Reflect.deleteProperty(window, '__canopyGenUiTest')
      }
      if (window.__canopyGenUiFeasibilityTest === feasibilityTestApi) {
        Reflect.deleteProperty(window, '__canopyGenUiFeasibilityTest')
      }
    }
    surface?.setAttribute('inert', '')
    if (surface) surface.dataset.genuiReady = 'false'
  },
}
}
