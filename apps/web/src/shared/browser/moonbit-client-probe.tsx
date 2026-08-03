'use client';

import { useEffect, useState } from 'react';

const probeIds = [
  '@moonbit/crdt-lambda',
  '@moonbit/crdt-json',
  '@moonbit/crdt-markdown',
  '@moonbit/crdt-jsx',
  '@moonbit/graphviz',
] as const;

const moduleLoaders = import.meta.env.SSR
  ? []
  : [
      () => import('@moonbit/crdt-lambda'),
      () => import('@moonbit/crdt-json'),
      () => import('@moonbit/crdt-markdown'),
      () => import('@moonbit/crdt-jsx'),
      () => import('@moonbit/graphviz'),
    ];

export function MoonbitClientProbe() {
  const [status, setStatus] = useState<'loading' | 'ready' | 'failed'>('loading');

  useEffect(() => {
    let active = true;
    Promise.all(moduleLoaders.map((load) => load())).then(
      () => {
        if (active) setStatus('ready');
      },
      () => {
        if (active) setStatus('failed');
      },
    );
    return () => {
      active = false;
    };
  }, []);

  return (
    <section aria-labelledby="moonbit-probe-heading" data-moonbit-client-probe={status}>
      <h2 id="moonbit-probe-heading">Generated module boundary</h2>
      <ul>
        {probeIds.map((id) => (
          <li key={id} data-module-id={id}>{id}</li>
        ))}
      </ul>
    </section>
  );
}
