'use client';

import { createElement, useLayoutEffect, useRef } from 'react';
import type { DemoId } from '../../catalog/demo-catalog';
import {
  type MountedImperativeSession,
  ownImperativeSession,
} from './imperative-session';
import { useRouteLifecycle } from './provider';

export type { MountedImperativeSession } from './imperative-session';

export type MountImperativeDemo = (
  container: HTMLElement,
  restoredSnapshot: unknown,
) => MountedImperativeSession;

export function ImperativeDemoHost({
  demoId,
  mount,
  className,
}: {
  readonly demoId: DemoId;
  readonly mount: MountImperativeDemo;
  readonly className?: string;
}) {
  const containerRef = useRef<HTMLDivElement>(null);
  const lifecycle = useRouteLifecycle();

  useLayoutEffect(() => {
    const container = containerRef.current;
    if (container === null) throw new Error('Imperative demo host container is unavailable');
    const session = ownImperativeSession(
      mount(container, lifecycle.snapshotForMount(demoId)),
    );
    return lifecycle.registerSurface(demoId, { container, session });
  }, [demoId, lifecycle.mountRevision, lifecycle.registerSurface, lifecycle.snapshotForMount, mount]);

  return createElement('div', {
    ref: containerRef,
    className,
    'data-imperative-demo-host': demoId,
  });
}
