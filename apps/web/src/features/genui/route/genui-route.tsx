import genuiStyles from './styles.css?inline';
import { GenuiClient } from './genui-client';

export function GenuiRoute() {
  return (
    <GenuiClient>
      <style data-genui-route-styles>{genuiStyles}</style>
      <div>
        <main className="genui-surface min-h-screen bg-canopy-bg text-canopy-text font-mono p-5" data-genui-ready="false" inert>
          <div className="max-w-[1600px] mx-auto">
            <h1 className="text-canopy-green text-2xl mb-1" tabIndex={-1} data-route-heading data-route-focus="heading">Generative UI</h1>
            <p className="text-canopy-muted text-[13px] mb-4">
              JSX streamed chunk-by-chunk → <em className="text-canopy-yellow not-italic">real DOM elements</em> appear incrementally.
              Stable NodeIds reuse existing DOM nodes; only new content triggers renders.
              <a href="https://github.com/dowdiness/canopy" target="_blank" rel="noopener noreferrer" className="text-canopy-green underline">GitHub</a>
            </p>

            <div className="grid grid-cols-1 lg:grid-cols-3 gap-4">
              <div className="bg-canopy-surface border border-canopy-border rounded-lg p-3.5 flex flex-col">
                <h2 className="text-canopy-green text-[13px] mb-2.5 uppercase tracking-wider">Input</h2>
                <div className="flex flex-wrap gap-1.5 mb-2.5 pb-2.5 border-b border-canopy-border">
                  <span className="text-canopy-muted text-[11px] mr-0.5">Examples:</span>
                  <button className="btn" data-example="0">Simple</button>
                  <button className="btn" data-example="1">Attributes</button>
                  <button className="btn" data-example="2">Deep Nesting</button>
                  <button className="btn" data-example="3">Expressions</button>
                  <button className="btn" data-example="4">Mixed</button>
                  <button className="btn" data-example="5">Tailwind</button>
                  <button className="btn-primary" id="stream-btn">▶ Stream</button>
                  <button className="btn" id="clear-btn">Clear</button>
                </div>
                <textarea id="source-input" spellCheck={false} data-route-focus="source"
                  className="w-full min-h-[80px] flex-1 bg-canopy-bg text-canopy-text border border-canopy-border rounded-md p-2 text-[13px] font-mono resize-y outline-none focus:border-canopy-green"
                  defaultValue={`<div class="card">
  <h1>Hello, World!</h1>
  <p>Streaming JSX → live DOM.</p>
</div>`} />
                <div id="stream-progress" className="mt-1.5 p-1.5 bg-canopy-bg rounded-md text-[11px] text-canopy-muted min-h-[24px] break-all">Ready.</div>
              </div>

              <div className="bg-canopy-surface border border-canopy-border rounded-lg p-3.5 flex flex-col">
                <h2 className="text-canopy-green text-[13px] mb-2.5 uppercase tracking-wider">Rendered HTML</h2>
                <div className="text-[11px] text-canopy-muted mb-1.5">Step: <span id="html-step-num" className="text-canopy-green font-bold">—</span> · <span id="html-node-count" className="text-canopy-green font-bold">0</span> DOM nodes</div>
                <div id="html-preview" className="flex-1 overflow-auto bg-canopy-bg rounded-md p-4 min-h-[200px] max-h-[500px]">
                  <div className="text-center py-8 text-canopy-muted text-xs">Stream JSX to see rendered output.</div>
                </div>
              </div>

              <div className="bg-canopy-surface border border-canopy-border rounded-lg p-3.5 flex flex-col">
                <h2 className="text-canopy-green text-[13px] mb-2.5 uppercase tracking-wider">Projection Tree</h2>
                <div className="flex gap-1 mb-2">
                  <button className="view-tab active" data-view="tree">Tree</button>
                  <button className="view-tab" data-view="errors">Diagnostics</button>
                </div>
                <div className="view-panel active flex flex-col flex-1" id="view-tree">
                  <div className="text-[11px] text-canopy-muted mb-1.5">Step: <span id="step-num" className="text-canopy-green font-bold">—</span></div>
                  <div className="flex gap-3 mb-1.5 text-[10px]">
                    <span className="flex items-center gap-1"><span className="inline-block w-2.5 h-2.5 rounded bg-canopy-green/40"></span> Stable NodeId</span>
                    <span className="flex items-center gap-1"><span className="inline-block w-2.5 h-2.5 rounded bg-canopy-yellow/40"></span> New NodeId</span>
                  </div>
                  <div className="flex-1 overflow-auto bg-canopy-bg rounded-md p-2.5 min-h-[200px] max-h-[500px]">
                    <div id="tree-output" className="text-[11px] leading-relaxed">
                      <div className="text-center py-8 text-canopy-muted text-xs">Stream JSX to see the tree.</div>
                    </div>
                  </div>
                </div>
                <div className="view-panel flex-col flex-1 hidden" id="view-errors">
                  <div className="text-[11px] text-canopy-muted mb-1.5">Parser diagnostics during streaming:</div>
                  <div className="flex-1 overflow-auto bg-canopy-bg rounded-md p-2.5 min-h-[200px] max-h-[500px]">
                    <div id="errors-list"><div className="text-center py-8 text-canopy-muted text-xs">No errors.</div></div>
                  </div>
                </div>
                <div id="status-bar" className="mt-2 p-1.5 bg-canopy-bg rounded-md text-[11px] text-canopy-muted">Ready.</div>
              </div>
            </div>

            <section id="genui-feasibility" className="mt-4 overflow-hidden rounded-lg border border-canopy-border bg-canopy-surface">
              <header className="flex flex-col gap-4 border-b border-canopy-border px-4 py-4 lg:flex-row lg:items-start lg:justify-between">
                <div className="max-w-3xl">
                  <div className="mb-2 flex flex-wrap items-center gap-2 text-[10px] uppercase tracking-[0.14em] text-canopy-muted">
                    <span className="text-canopy-green">Technical feasibility</span>
                    <span aria-hidden="true">·</span>
                    <span>Recorded candidate</span>
                    <span aria-hidden="true">·</span>
                    <span>No user-value claim</span>
                  </div>
                  <h2 className="text-[16px] font-semibold text-canopy-text">Capability-bounded candidate transaction</h2>
                  <p className="mt-2 max-w-[74ch] text-[12px] leading-5 text-canopy-muted">
                    Choose a frozen fixture, then replay a recorded candidate through the same MoonBit decode, validation,
                    materialization, rubric, dry-run, and commit path used by the local study.
                  </p>
                </div>
                <button id="feasibility-run-recorded" className="btn-primary min-h-9 self-start px-3" type="button">
                  Run recorded candidate
                </button>
              </header>

              <div className="grid min-h-[300px] grid-cols-1 lg:grid-cols-[minmax(0,1fr)_320px]">
                <div className="p-4">
                  <div className="flex flex-wrap gap-2" aria-label="Feasibility cases">
                    <button className="btn feasibility-case active" data-feasibility-case="orders-pending-attention" type="button">Orders</button>
                    <button className="btn feasibility-case" data-feasibility-case="inventory-low-stock" type="button">Inventory</button>
                    <button className="btn feasibility-case" data-feasibility-case="incidents-critical-resolution" type="button">Incidents</button>
                  </div>
                  <p id="feasibility-question" className="mt-3 text-[13px] leading-6 text-canopy-text"></p>
                  <p id="feasibility-source" className="mt-1 text-[10px] uppercase tracking-wider text-canopy-muted"></p>

                  <div className="mt-4 rounded-md border border-canopy-border bg-canopy-bg p-4">
                    <div id="feasibility-preview" className="min-h-[180px] overflow-auto">
                      <div className="flex min-h-[180px] items-center justify-center text-center text-[11px] leading-5 text-canopy-muted">
                        Run the recorded candidate to materialize a safe projection.
                      </div>
                    </div>
                  </div>
                </div>

                <aside className="border-t border-canopy-border bg-canopy-bg/40 p-4 lg:border-l lg:border-t-0" aria-labelledby="feasibility-evidence-heading">
                  <h3 id="feasibility-evidence-heading" className="text-[10px] uppercase tracking-[0.14em] text-canopy-green">Transaction evidence</h3>
                  <p id="feasibility-status" className="mt-2 text-[11px] leading-5 text-canopy-muted" role="status" aria-live="polite">
                    Ready. No provider request has been made.
                  </p>
                  <dl className="mt-4 grid grid-cols-2 gap-x-3 gap-y-3 border-t border-canopy-border pt-3 text-[10px] text-canopy-muted">
                    <div><dt>Classification</dt><dd id="feasibility-classification" className="mt-0.5 text-canopy-text">—</dd></div>
                    <div><dt>Revision</dt><dd id="feasibility-revision" className="mt-0.5 text-canopy-text">—</dd></div>
                    <div className="col-span-2"><dt>Matched stable keys</dt><dd id="feasibility-keys" className="mt-0.5 break-words text-canopy-text">—</dd></div>
                    <div><dt>Summary</dt><dd id="feasibility-summary" className="mt-0.5 text-canopy-text">—</dd></div>
                    <div><dt>Rubric</dt><dd id="feasibility-rubric" className="mt-0.5 text-canopy-text">—</dd></div>
                    <div className="col-span-2"><dt>Safe-output SHA-256</dt><dd id="feasibility-hash" className="mt-0.5 break-all font-mono text-[9px] text-canopy-text">—</dd></div>
                  </dl>
                </aside>
              </div>
            </section>

            <section id="data-explorer" className="mt-4 bg-canopy-surface border border-canopy-border rounded-lg p-3.5">
              <div className="flex flex-wrap items-center justify-between gap-2 mb-3">
                <div>
                  <h2 className="text-canopy-green text-[13px] uppercase tracking-wider">Data Explorer</h2>
                  <p className="text-canopy-muted text-[11px] mt-1">Host-owned fixture → declarative table</p>
                </div>
                <div className="flex items-center gap-2 text-[11px] text-canopy-muted">
                  <span className="binding-badge">@orders</span>
                  <span><strong id="data-row-count" data-testid="data-row-count" className="text-canopy-green">0</strong> visible rows</span>
                </div>
              </div>
              <div className="flex flex-wrap items-center gap-2 mb-3" aria-label="Data sources">
                <span className="text-[11px] text-canopy-muted">Source:</span>
                <button id="data-json-source" className="btn" type="button" aria-pressed="true">JSON fixture</button>
                <button id="data-csv-source" className="btn" type="button" aria-pressed="false">CSV fixture</button>
                <span id="data-source-label" className="text-[11px] text-canopy-muted">JSON fixture</span>
              </div>
              <div className="flex flex-wrap items-center gap-2 mb-3">
                <label htmlFor="data-filter-input" className="text-[11px] text-canopy-muted">Filter name, status, or ID</label>
                <input id="data-filter-input" type="search" placeholder="Try: pending" autoComplete="off"
                  className="min-w-[220px] flex-1 bg-canopy-bg text-canopy-text border border-canopy-border rounded-md px-2 py-1.5 text-[12px] font-mono outline-none focus:border-canopy-green" />
                <button id="data-filter-clear" className="btn" type="button">Clear filter</button>
              </div>
              <dl className="grid grid-cols-1 sm:grid-cols-3 gap-2 mb-3" aria-label="Order summary">
                <div className="summary-card">
                  <dt>Visible rows</dt>
                  <dd id="data-summary-count" data-testid="data-summary-count">0</dd>
                </div>
                <div className="summary-card">
                  <dt>Total amount</dt>
                  <dd id="data-summary-total" data-testid="data-summary-total">$0.00</dd>
                </div>
                <div className="summary-card">
                  <dt>Average amount</dt>
                  <dd id="data-summary-average" data-testid="data-summary-average">$0.00</dd>
                </div>
              </dl>
              <div className="overflow-x-auto bg-canopy-bg rounded-md">
                <table id="orders-table" data-testid="orders-table" aria-label="Orders" className="w-full text-left text-[12px]">
                  <thead className="text-canopy-muted border-b border-canopy-border">
                    <tr>
                      <th className="px-3 py-2 font-normal">Order</th>
                      <th className="px-3 py-2 font-normal">Name</th>
                      <th className="px-3 py-2 font-normal">Status</th>
                      <th className="px-3 py-2 font-normal text-right">Amount</th>
                    </tr>
                  </thead>
                  <tbody id="orders-table-body"></tbody>
                </table>
              </div>
              <div id="data-selection-status" className="mt-3 text-[11px] text-canopy-muted" role="status" aria-live="polite">No row selected.</div>
              <aside id="data-detail" className="mt-3 border-t border-canopy-border pt-3" aria-labelledby="data-detail-heading">
                <h3 id="data-detail-heading" className="text-canopy-green text-[11px] uppercase tracking-wider">Selected order</h3>
                <p id="data-detail-empty" className="text-canopy-muted text-[11px] mt-1">Select a row to inspect its details.</p>
                <dl id="data-detail-content" className="grid grid-cols-2 sm:grid-cols-4 gap-2 mt-2" hidden>
                  <div className="detail-field"><dt>ID</dt><dd id="data-detail-id" data-testid="data-detail-id"></dd></div>
                  <div className="detail-field"><dt>Name</dt><dd id="data-detail-name" data-testid="data-detail-name"></dd></div>
                  <div className="detail-field"><dt>Status</dt><dd id="data-detail-status" data-testid="data-detail-status"></dd></div>
                  <div className="detail-field"><dt>Amount</dt><dd id="data-detail-amount" data-testid="data-detail-amount"></dd></div>
                </dl>
              </aside>
            </section>
          </div>

          {/* Safelist utility classes emitted by streamed and recorded GenUI JSX. */}
          <div className="hidden bg-gray-800 text-white p-6 rounded-xl shadow-lg max-w-lg text-2xl font-bold text-emerald-400 mb-2 text-gray-300 text-xl text-sky-400 mb-3 underline hover:text-sky-300 space-y-3 bg-gray-700 rounded-lg p-4 text-amber-400 mt-3 list-disc list-inside space-y-1 text-rose-400 bg-amber-500/20 text-amber-300 px-3 py-1 rounded-full text-sm inline-block space-y-4 border-b border-gray-600 pb-3 text-cyan-400 flex gap-4 hover:text-cyan-400 bg-gradient-to-br from-indigo-500 to-purple-600 shadow-lg max-w-md text-indigo-100 bg-white/20 bg-white/10 text-indigo-200"></div>
        </main>
      </div>
    </GenuiClient>
  );
}
