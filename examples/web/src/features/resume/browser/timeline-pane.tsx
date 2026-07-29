import { useEffect, useState } from 'react';
import { activityTextForDisplay } from '../core/session';
import {
  activityKindLabel,
  type PilotTimelinePhase,
} from './workbench-view-model';

export interface TimelinePaneProps {
  readonly phases: readonly PilotTimelinePhase[];
  readonly selectedEntryId: string;
  readonly selectedPhase: PilotTimelinePhase | undefined;
  readonly selectedPhaseId: string | undefined;
  readonly formatTime: (timestamp: string) => string;
  readonly onSelectEntry: (entryId: string) => void;
}

export function TimelinePane({
  phases,
  selectedEntryId,
  selectedPhase,
  selectedPhaseId,
  formatTime,
  onSelectEntry,
}: TimelinePaneProps) {
  const [expandedPhaseIds, setExpandedPhaseIds] = useState<ReadonlySet<string>>(
    () => new Set(selectedPhaseId === undefined ? [] : [selectedPhaseId]),
  );
  useEffect(() => {
    if (selectedPhaseId === undefined) return;
    setExpandedPhaseIds(current =>
      current.has(selectedPhaseId) ? current : new Set([...current, selectedPhaseId]),
    );
  }, [selectedPhaseId]);

  return (
    <section
      className="pilot-workbench-panel pilot-timeline"
      data-pane="timeline"
      aria-labelledby="pilot-timeline-title"
    >
      <header className="pilot-panel-heading">
        <div>
          <h3 id="pilot-timeline-title">Timeline</h3>
        </div>
        <p>{phases.length} phases · {phases.flatMap(phase => phase.items).length} recorded events</p>
      </header>
      <ol className="pilot-phase-list">
        {phases.map(phase => {
          const containsSelection = phase === selectedPhase;
          const expanded = expandedPhaseIds.has(phase.id);
          const first = phase.items[0]!;
          const last = phase.items[phase.items.length - 1]!;
          return (
            <li className="pilot-phase" data-selected={containsSelection} key={phase.id}>
              <button
                className="pilot-phase-toggle"
                type="button"
                aria-expanded={expanded}
                onClick={() => {
                  setExpandedPhaseIds(current => {
                    const next = new Set(current);
                    if (next.has(phase.id)) next.delete(phase.id);
                    else next.add(phase.id);
                    return next;
                  });
                }}
              >
                <span>Phase {String(phase.index + 1).padStart(2, '0')}</span>
                <time dateTime={first.timestamp}>
                  {formatTime(first.timestamp)}–{formatTime(last.timestamp)}
                </time>
                <strong>{phase.recordedKinds.join(' · ')}</strong>
                <i aria-hidden="true">{expanded ? '−' : '+'}</i>
              </button>
              {expanded ? (
                <ol className="pilot-event-list">
                  {phase.items.map(item => {
                    const selected = item.source.entryId === selectedEntryId;
                    return (
                      <li
                        id={`source-${item.source.entryId}`}
                        data-selected={selected}
                        aria-current={selected ? 'true' : undefined}
                        key={item.id}
                      >
                        <button type="button" onClick={() => onSelectEntry(item.source.entryId)}>
                          <span>{activityKindLabel(item)}</span>
                          <time dateTime={item.timestamp}>{formatTime(item.timestamp)}</time>
                          <strong>{item.title}</strong>
                          <small>{activityTextForDisplay(item)}</small>
                        </button>
                      </li>
                    );
                  })}
                </ol>
              ) : null}
            </li>
          );
        })}
      </ol>
    </section>
  );
}
