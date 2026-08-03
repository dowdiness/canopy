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

interface WorkbenchViewContextValue {
  readonly viewModel: WorkbenchViewModel;
  readonly selectedEntryId: string;
  readonly terminalPathId: string;
}

interface WorkbenchNavigationContextValue {
  readonly activePane: WorkbenchPane;
  readonly setActivePane: (pane: WorkbenchPane) => void;
  readonly selectFromTimeline: (entryId: string) => void;
  readonly selectChatSource: (entryId: string, leafId: string) => void;
  readonly onSelectEntry: (entryId: string) => void;
  readonly onToggleChatSource: (entryId: string) => void;
  readonly conversationPaneRef: RefObject<ConversationPaneHandle | null>;
}

const WorkbenchViewContext = createContext<WorkbenchViewContextValue | null>(null);
const WorkbenchNavigationContext = createContext<WorkbenchNavigationContextValue | null>(null);

function useWorkbenchView(): WorkbenchViewContextValue {
  const context = useContext(WorkbenchViewContext);
  if (context === null) throw new Error('Workbench compound children must be inside Workbench.Root.');
  return context;
}

function useWorkbenchNavigation(): WorkbenchNavigationContextValue {
  const context = useContext(WorkbenchNavigationContext);
  if (context === null) throw new Error('Workbench compound children must be inside Workbench.Root.');
  return context;
}

function Root({
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
  const viewContext = useMemo<WorkbenchViewContextValue>(() => ({
    viewModel,
    selectedEntryId,
    terminalPathId,
  }), [selectedEntryId, terminalPathId, viewModel]);
  const navigationContext = useMemo<WorkbenchNavigationContextValue>(() => ({
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
  }), [activePane, onSelectChatSource, onSelectEntry, onToggleChatSource]);
  return (
    <WorkbenchViewContext.Provider value={viewContext}>
      <WorkbenchNavigationContext.Provider value={navigationContext}>
        <section className="pilot-workbench" aria-labelledby="pilot-workbench-title">
          {children}
        </section>
      </WorkbenchNavigationContext.Provider>
    </WorkbenchViewContext.Provider>
  );
}

function Tabs() {
  const { activePane, setActivePane } = useWorkbenchNavigation();
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

function Grid({ children }: { readonly children: ReactNode }) {
  const { activePane } = useWorkbenchNavigation();
  return (
    <div className="pilot-workbench-grid" data-active-pane={activePane}>
      {children}
    </div>
  );
}

function Timeline() {
  const {
    viewModel: { phases, selectedPhase, selectedPhaseId },
    selectedEntryId,
  } = useWorkbenchView();
  const { selectFromTimeline } = useWorkbenchNavigation();
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

function Conversation() {
  const {
    viewModel: {
      conversationItems,
      entriesById,
      operationIndex,
      selectedItemIndex,
    },
    selectedEntryId,
  } = useWorkbenchView();
  const {
    activePane,
    conversationPaneRef,
    onSelectEntry,
  } = useWorkbenchNavigation();
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

function Evidence({ children }: { readonly children: ReactNode }) {
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
  } = useWorkbenchView();
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

const workbenchTimeFormat = new Intl.DateTimeFormat('en-US', {
  timeZone: 'UTC',
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

export { useWorkbenchNavigation };
