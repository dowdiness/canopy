import type { ReactNode } from 'react';

export default function Root({ children }: { readonly children: ReactNode }) {
  return (
    <html lang="en">
      <head>
        <meta charSet="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <title>Canopy Waku Foundation</title>
      </head>
      <body>{children}</body>
    </html>
  );
}
