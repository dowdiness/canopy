import {
  createContext,
  useContext,
  useMemo,
  useRef,
  useState,
  type ReactNode,
  type RefObject,
} from 'react';
import {
  ConversationPane,
  type ConversationPaneHandle,
} from './conversation-pane';
import { EvidencePane } from './evidence-pane';
import { TimelinePane } from './timeline-pane';
import {
  normalizedEntryLabel,
  type WorkbenchViewModel,
} from './workbench-view-model';

export type WorkbenchPane = 'timeline' | 'conversation' | 'evidence';

export interface WorkbenchRootProps {
  readonly viewModel: WorkbenchViewModel;
  readonly selectedEntryId: string;
  readonly terminalPathId: string;
  readonly onSelectEntry: (entryId: string) => void;
  readonly onSelectChatSource: (entryId: string, leafId: string) => void;
  readonly onToggleChatSource: (entryId: string) => void;
  readonly children: ReactNode;
}

interface WorkbenchContextValue {
  readonly viewModel: WorkbenchViewModel;
  readonly selectedEntryId: string;
  readonly terminalPathId: string;
  readonly activePane: WorkbenchPane;
  readonly setActivePane: (pane: WorkbenchPane) => void;
  readonly selectFromTimeline: (entryId: string) => void;
  readonly selectChatSource: (entryId: string, leafId: string) => void;
  readonly onSelectEntry: (entryId: string) => void;
  readonly onToggleChatSource: (entryId: string) => void;
  readonly conversationPaneRef: RefObject<ConversationPaneHandle | null>;
}

const WorkbenchContext = createContext<WorkbenchContextValue | null>(null);

function useWorkbench(): WorkbenchContextValue {
  const context = useContext(WorkbenchContext);
  if (context === null) throw new Error('Workbench compound children must be inside Workbench.Root.');
  return context;
}

export function Root({
  viewModel,
  selectedEntryId,
  terminalPathId,
  onSelectEntry,
  onSelectChatSource,
  onToggleChatSource,
  children,
}: WorkbenchRootProps) {
  const [activePane, setActivePane] = useState<WorkbenchPane>('conversation');
  const conversationPaneRef = useRef<ConversationPaneHandle>(null);
  const context = useMemo<WorkbenchContextValue>(() => ({
    viewModel,
    selectedEntryId,
    terminalPathId,
    activePane,
    setActivePane,
    selectFromTimeline: entryId => {
      conversationPaneRef.current?.revealConversationSelection();
      onSelectEntry(entryId);
      setActivePane('conversation');
    },
    selectChatSource: (entryId, leafId) => {
      onSelectChatSource(entryId, leafId);
      setActivePane('evidence');
    },
    onSelectEntry,
    onToggleChatSource,
    conversationPaneRef,
  }), [
    activePane,
    onSelectChatSource,
    onSelectEntry,
    onToggleChatSource,
    selectedEntryId,
    terminalPathId,
    viewModel,
  ]);
  return (
    <WorkbenchContext.Provider value={context}>
      <section className="pilot-workbench" aria-labelledby="pilot-workbench-title">
        {children}
      </section>
    </WorkbenchContext.Provider>
  );
}

export function Tabs() {
  const { activePane, setActivePane } = useWorkbench();
  return (
    <nav className="pilot-workbench-tabs" aria-label="Session understanding views">
      {(['timeline', 'conversation', 'evidence'] as const).map(pane => (
        <button
          type="button"
          data-pane={pane}
          aria-pressed={activePane === pane}
          key={pane}
          onClick={() => setActivePane(pane)}
        >
          {pane === 'timeline' ? 'Timeline' : pane === 'conversation' ? 'Conversation' : 'Evidence'}
        </button>
      ))}
    </nav>
  );
}
export function Grid({ children }: { readonly children: ReactNode }) {
  const { activePane } = useWorkbench();
  return (
    <div className="pilot-workbench-grid" data-active-pane={activePane}>
      {children}
    </div>
  );
}

export function Timeline() {
  const {
    viewModel: { phases, selectedPhase, selectedPhaseId },
    selectedEntryId,
    selectFromTimeline,
  } = useWorkbench();
  return (
    <TimelinePane
      phases={phases}
      selectedEntryId={selectedEntryId}
      selectedPhase={selectedPhase}
      selectedPhaseId={selectedPhaseId}
      formatTime={formatWorkbenchTime}
      onSelectEntry={selectFromTimeline}
    />
  );
}

export function Conversation() {
  const {
    viewModel: {
      conversationItems,
      entriesById,
      operationIndex,
      selectedItemIndex,
    },
    selectedEntryId,
    activePane,
    conversationPaneRef,
    onSelectEntry,
  } = useWorkbench();
  return (
    <ConversationPane
      ref={conversationPaneRef}
      active={activePane === 'conversation'}
      conversationItems={conversationItems}
      entriesById={entriesById}
      operationIndex={operationIndex}
      selectedEntryId={selectedEntryId}
      selectedItemIndex={selectedItemIndex}
      totalEvents={conversationItems.length}
      formatTime={formatWorkbenchTime}
      onSelectEntry={onSelectEntry}
    />
  );
}

export function Evidence({ children }: { readonly children: ReactNode }) {
  const {
    viewModel: {
      normalizedRecord,
      operationRelationship,
      selectedItem,
      selectedItemIndex,
      selectedRecord,
      conversationItems,
    },
    selectedEntryId,
    terminalPathId,
  } = useWorkbench();
  return (
    <EvidencePane
      chat={children}
      normalizedRecord={normalizedRecord}
      operationRelationship={operationRelationship}
      selectedEntryId={selectedEntryId}
      selectedItem={selectedItem}
      selectedItemIndex={selectedItemIndex}
      selectedRecord={selectedRecord}
      terminalPathId={terminalPathId}
      totalItems={conversationItems.length}
      formatTime={formatWorkbenchTime}
      normalizedEntryLabel={normalizedEntryLabel}
    />
  );
}

const workbenchTimeFormat = new Intl.DateTimeFormat(undefined, {
  hour: '2-digit',
  minute: '2-digit',
  second: '2-digit',
});

function formatWorkbenchTime(value: string): string {
  return workbenchTimeFormat.format(new Date(value));
}

export const Workbench = {
  Root,
  Tabs,
  Grid,
  Timeline,
  Conversation,
  Evidence,
} as const;

export { useWorkbench };
