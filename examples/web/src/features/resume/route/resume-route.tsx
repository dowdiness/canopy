'use client';

import { useCallback, useRef, useState } from 'react';
import {
  useRouteLifecycle,
  useRouteSnapshot,
} from '../../../shared/route-lifecycle/browser/provider';
import {
  ResumeApp,
  type ResumeRouteSnapshot,
} from '../browser/app';

const resumeControlFocusTokens = Object.freeze([
  'session-file',
  'branch-select',
  'forget-session',
  'chat-message',
]);

export function ResumeRoute() {
  const [lifetime, setLifetime] = useState(0);
  const remountAfterForget = useCallback(() => {
    setLifetime(current => current + 1);
  }, []);

  return (
    <ResumeRouteLifetime
      key={lifetime}
      initialDemoRestored={lifetime > 0}
      onForget={remountAfterForget}
    />
  );
}

function ResumeRouteLifetime({
  initialDemoRestored,
  onForget,
}: {
  readonly initialDemoRestored: boolean;
  readonly onForget: () => void;
}) {
  const lifecycle = useRouteLifecycle();
  const surfaceRef = useRef<HTMLDivElement>(null);
  const snapshotRef = useRef<ResumeRouteSnapshot | undefined>(undefined);
  const restoredSnapshot = useRouteSnapshot<ResumeRouteSnapshot | undefined>('resume', {
    snapshot: () => snapshotRef.current,
    restoreFocus(token) {
      const accepted = resumeControlFocusTokens.includes(token) ||
        token.startsWith('conversation:');
      if (!accepted) return false;
      const target = [...(surfaceRef.current
        ?.querySelectorAll<HTMLElement>('[data-route-focus]') ?? [])]
        .find(candidate => candidate.dataset.routeFocus === token);
      if (target === undefined) return false;
      target.focus({ preventScroll: true });
      return document.activeElement === target;
    },
  });
  const captureSnapshot = useCallback((snapshot: ResumeRouteSnapshot) => {
    snapshotRef.current = snapshot;
  }, []);
  const forgetSnapshot = useCallback(() => {
    lifecycle.forget('resume');
    onForget();
  }, [lifecycle, onForget]);

  return (
    <ResumeApp
      initialSnapshot={restoredSnapshot}
      initialDemoRestored={initialDemoRestored}
      onSnapshotChange={captureSnapshot}
      onForgetSnapshot={forgetSnapshot}
      surfaceRef={surfaceRef}
    />
  );
}
