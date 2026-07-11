// StatusBar Component
//
// Shows editor status: character count, cursor position, agent ID, sync status.

interface StatusBarProps {
  charCount: number;
  cursorPosition: number;
  agentId: string;
  syncing: boolean;
}

export function StatusBar({
  charCount,
  cursorPosition,
  agentId,
  syncing,
}: StatusBarProps) {
  return (
    <div className="status-bar">
      <div className="status-item">
        <span className="status-label">Chars:</span>
        <span className="status-value">{charCount}</span>
      </div>

      <div className="status-item">
        <span className="status-label">Cursor:</span>
        <span className="status-value">{cursorPosition}</span>
      </div>

      <div className="status-item">
        <span className="status-label">Agent:</span>
        <span className="status-value status-agent">{agentId.slice(0, 12)}...</span>
      </div>

      {syncing && (
        <div className="status-item status-syncing">
          <span className="sync-indicator" />
          Syncing...
        </div>
      )}
    </div>
  );
}
