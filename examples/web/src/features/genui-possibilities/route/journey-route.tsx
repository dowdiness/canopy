import { JourneyClient } from './journey-client';

export function JourneyRoute() {
  return (
    <JourneyClient>
      <div>
        <a className="skip-link" href="#decision-workspace">Skip to decision</a>
        <header className="app-bar">
          <a className="wordmark" href="/" aria-label="Canopy home">CANOPY</a>
          <div className="journey-identity" role="group" aria-label="Current artifact">
            <span>Naoshima journey</span>
          </div>
          <section className="revision-trace" aria-labelledby="revision-trace-title">
            <h2 id="revision-trace-title" className="visually-hidden">Revision history</h2>
            <span id="revision-label">Revision 3</span>
            <button className="quiet-action" id="undo-button" type="button" disabled>Undo last change</button>
          </section>
        </header>

        <main id="decision-workspace" aria-labelledby="decision-title">
          <section className="disruption" aria-labelledby="disruption-title">
            <div className="disruption-mark" aria-hidden="true">!</div>
            <div className="disruption-copy">
              <p className="section-label">Disruption context · updated 8 min ago</p>
              <h2 id="disruption-title">Strong winds put the 17:20 ferry at risk.</h2>
              <p>The last connection expected to run normally leaves Kyoto at 12:52. Your museum reservation tomorrow is unchanged.</p>
            </div>
            <dl className="source-status">
              <div>
                <dt>Risk</dt>
                <dd><span className="certainty likely">Cancellation likely</span></dd>
              </div>
              <div>
                <dt>Sources</dt>
                <dd>JR West + Shikoku Kisen</dd>
              </div>
            </dl>
          </section>

          <div className="workspace-grid">
            <section className="itinerary-panel" aria-labelledby="itinerary-title">
              <header className="panel-heading">
                <div>
                  <p className="section-label">Persistent itinerary</p>
                  <h2 id="itinerary-title">Kyoto to Naoshima</h2>
                </div>
                <span id="plan-status" className="plan-status at-risk">Needs attention</span>
              </header>
              <ol id="itinerary-list" className="itinerary-list" role="list"></ol>
            </section>

            <section className="decision-panel" aria-labelledby="decision-title">
              <header className="decision-heading">
                <p className="section-label">Decision</p>
                <h1 id="decision-title" data-route-heading tabIndex={-1}>How should this journey change?</h1>
                <p>Nothing changes until you apply a response.</p>
              </header>

              <section className="response-comparison" aria-labelledby="response-comparison-title">
                <header className="comparison-heading">
                  <div className="comparison-heading-copy">
                    <h2 id="response-comparison-title">Compare responses</h2>
                    <p>Each response uses the same arrival, cost, evidence, and consequence.</p>
                  </div>
                  <button id="clear-selection-button" className="selection-reset" type="button" disabled>Clear selection</button>
                </header>
                <div className="comparison-table" role="radiogroup" aria-labelledby="response-comparison-title">
                  <div className="comparison-labels" aria-hidden="true">
                    <span>Response and evidence</span><span>Arrival</span><span>Cost</span><span>What changes</span>
                  </div>
                  <div id="response-list"></div>
                </div>
              </section>

              <section className="decision-preview" aria-labelledby="selection-detail-title">
                <header>
                  <p className="section-label">Decision preview</p>
                  <h2 id="selection-detail-title">What would change</h2>
                </header>
                <aside id="selection-detail" className="selection-detail" aria-live="polite">
                  <p>Select a response to see exactly what would change in your itinerary.</p>
                </aside>
              </section>

              <section className="decision-action-region" aria-labelledby="decision-actions-title">
                <div>
                  <p className="section-label">Actions</p>
                  <h2 id="decision-actions-title">Choose what happens next</h2>
                </div>
                <div className="decision-actions">
                  <button id="apply-button" className="primary-action" type="button" disabled>Apply to itinerary</button>
                </div>
              </section>
            </section>
          </div>
        </main>

        <div id="toast" className="toast" role="status" aria-live="polite"></div>
      </div>
    </JourneyClient>
  );
}
