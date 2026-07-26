import type { ReactNode } from 'react';
import { RouteLifecycleProvider } from '../shared/route-lifecycle/browser/provider';
import '../shared/shell/styles.css';

export default function Root({ children }: { readonly children: ReactNode }) {
  return (
    <html lang="en">
      <head>
        <meta charSet="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <title>Canopy demos</title>
      </head>
      <body><RouteLifecycleProvider>{children}</RouteLifecycleProvider></body>
    </html>
  );
}
