export interface MountedImperativeSession {
  snapshot(): unknown;
  restoreFocus(token: string): boolean;
  dispose(): void;
}

export function ownImperativeSession(
  session: MountedImperativeSession,
): MountedImperativeSession {
  let disposed = false;
  return {
    snapshot: () => structuredClone(session.snapshot()),
    restoreFocus: (token) => !disposed && session.restoreFocus(token),
    dispose: () => {
      if (disposed) return;
      disposed = true;
      session.dispose();
    },
  };
}
