import { useState, type ReactNode } from 'react';
import { activityTextForDisplay, type ActivityItem, type NormalizedEntry } from '../core/session';

export interface EvidencePaneProps {
  readonly chat: ReactNode;
  readonly normalizedRecord: string;
  readonly operationRelationship: string | undefined;
  readonly selectedEntryId: string;
  readonly selectedItem: ActivityItem | undefined;
  readonly selectedItemIndex: number;
  readonly selectedRecord: NormalizedEntry | undefined;
  readonly terminalPathId: string;
  readonly totalItems: number;
  readonly formatTime: (timestamp: string) => string;
  readonly normalizedEntryLabel: (entry: NormalizedEntry | undefined) => string;
}

export function EvidencePane({
  chat,
  normalizedRecord,
  operationRelationship,
  selectedEntryId,
  selectedItem,
  selectedItemIndex,
  selectedRecord,
  terminalPathId,
  totalItems,
  formatTime,
  normalizedEntryLabel,
}: EvidencePaneProps) {
  const [inspectorMode, setInspectorMode] = useState<'discuss' | 'evidence'>('discuss');
  const [evidenceMode, setEvidenceMode] = useState<'readable' | 'normalized'>('readable');

  return (
    <section className="pilot-workbench-panel pilot-evidence" data-pane="evidence" id="pilot-inspector" aria-labelledby="pilot-inspector-title">
      <header className="pilot-panel-heading">
        <div><h3 id="pilot-inspector-title" tabIndex={-1}>Evidence</h3></div>
        <p>Selected {selectedItemIndex + 1} of {totalItems}</p>
      </header>
      <div className="pilot-inspector-tabs" role="tablist" aria-label="Evidence panel mode">
        <button type="button" role="tab" aria-selected={inspectorMode === 'discuss'} onClick={() => setInspectorMode('discuss')}>Discuss</button>
        <button type="button" role="tab" aria-selected={inspectorMode === 'evidence'} onClick={() => setInspectorMode('evidence')}>Evidence</button>
      </div>
      <div hidden={inspectorMode !== 'discuss'} role="tabpanel">{chat}</div>
      {inspectorMode !== 'evidence' ? null : (
        <>
          <div className="pilot-evidence-tabs" role="tablist" aria-label="Evidence representation">
            <button type="button" role="tab" aria-selected={evidenceMode === 'readable'} onClick={() => setEvidenceMode('readable')}>Readable</button>
            <button type="button" role="tab" aria-selected={evidenceMode === 'normalized'} onClick={() => setEvidenceMode('normalized')}>Normalized record</button>
          </div>
          {evidenceMode === 'readable' ? (
            <div className="pilot-evidence-readable" role="tabpanel">
              <section className="pilot-evidence-copy" aria-labelledby="pilot-evidence-copy-title">
                <span className="kicker">Selected recorded entry</span>
                <h4 id="pilot-evidence-copy-title">{selectedItem?.title ?? 'Unavailable entry'}</h4>
                <p>{selectedItem === undefined ? 'No recorded entry is selected.' : activityTextForDisplay(selectedItem)}</p>
              </section>
              <dl className="pilot-evidence-metadata">
                <div><dt>Recorded type</dt><dd>{normalizedEntryLabel(selectedRecord)}</dd></div>
                <div><dt>Time</dt><dd>{selectedItem === undefined ? 'Unknown' : formatTime(selectedItem.timestamp)}</dd></div>
                <div><dt>Path position</dt><dd>{selectedItemIndex + 1} of {totalItems}</dd></div>
                <div><dt>Terminal path</dt><dd>{terminalPathId}</dd></div>
                <div><dt>Source entry</dt><dd>{selectedEntryId}</dd></div>
              </dl>
              {operationRelationship === undefined ? null : <div className="pilot-operation-relation"><strong>Recorded operation relationship</strong><p>{operationRelationship}</p></div>}
            </div>
          ) : (
            <div className="pilot-evidence-normalized" role="tabpanel">
              <p>This is the bounded normalized import used by this view, not the unfiltered JSONL line.</p>
              <pre>{normalizedRecord}</pre>
            </div>
          )}
        </>
      )}
    </section>
  );
}
