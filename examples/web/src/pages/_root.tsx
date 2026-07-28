import type { ReactNode } from 'react';
import { RouteLifecycleProvider } from '../shared/route-lifecycle/browser/provider';
import '../shared/shell/styles.css';

const boundedPreloadRecovery = String.raw`
(() => {
  const recoveryKey = 'canopy.preload-recovery.v1';
  const pageKey = location.pathname + location.search;
  const recoveredPages = new Set();
  try {
    const storedPages = JSON.parse(sessionStorage.getItem(recoveryKey) || '[]');
    if (Array.isArray(storedPages)) {
      for (const storedPage of storedPages) {
        if (typeof storedPage === 'string') recoveredPages.add(storedPage);
      }
    }
  } catch {
    recoveredPages.add(pageKey);
  }
  let reloadAttempted = recoveredPages.has(pageKey);
  addEventListener('vite:preloadError', (event) => {
    if (reloadAttempted) {
      event.preventDefault();
      event.stopImmediatePropagation();
      return;
    }
    reloadAttempted = true;
    recoveredPages.add(pageKey);
    try {
      sessionStorage.setItem(recoveryKey, JSON.stringify([...recoveredPages]));
    } catch {
      event.preventDefault();
      event.stopImmediatePropagation();
    }
  }, { capture: true });
})();
`;

export default function Root({ children }: { readonly children: ReactNode }) {
  return (
    <html lang="en">
      <head>
        <meta charSet="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <title>Canopy demos</title>
        <script dangerouslySetInnerHTML={{ __html: boundedPreloadRecovery }} />
      </head>
      <body><RouteLifecycleProvider>{children}</RouteLifecycleProvider></body>
    </html>
  );
}
