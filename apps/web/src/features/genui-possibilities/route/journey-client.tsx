'use client';

import type { MouseEvent, ReactNode } from 'react';
import { mountGenuiPossibilities } from '../browser/mount.js';
import { ImperativeDemoHost } from '../../../shared/route-lifecycle/browser/imperative-host';
import { useRouteLifecycle } from '../../../shared/route-lifecycle/browser/provider';

export function JourneyClient({ children }: { readonly children: ReactNode }) {
  const lifecycle = useRouteLifecycle();
  const handleNavigation = (event: MouseEvent<HTMLDivElement>) => {
    const target = event.target;
    if (!(target instanceof Element)) return;
    const link = target.closest<HTMLAnchorElement>('a.wordmark[href="/"]');
    if (
      link === null ||
      event.defaultPrevented ||
      event.button !== 0 ||
      event.metaKey ||
      event.altKey ||
      event.ctrlKey ||
      event.shiftKey
    ) {
      return;
    }
    event.preventDefault();
    lifecycle.navigate('/');
  };

  return (
    <ImperativeDemoHost
      demoId="journey"
      mount={mountGenuiPossibilities}
      className="journey-surface"
    >
      <div onClick={handleNavigation}>{children}</div>
    </ImperativeDemoHost>
  );
}
