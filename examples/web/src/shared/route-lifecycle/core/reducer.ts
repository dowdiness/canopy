import type { DemoId, DemoPath } from '../../catalog/demo-catalog';

export type LifecycleHref =
  | '/'
  | DemoPath
  | `${DemoPath}?${string}`
  | `${DemoPath}#${string}`;

export interface SnapshotRecord {
  readonly value: unknown;
  readonly focusToken: string | null;
}

export interface PendingNavigation {
  readonly mode: 'push' | 'pop';
  readonly to: string;
  readonly destination: DemoId | null;
  readonly source: DemoId | null;
}

export type RouteFailure =
  | {
      readonly phase: 'pre-commit';
      readonly message: string;
      readonly retryHref: LifecycleHref;
    }
  | {
      readonly phase: 'post-commit';
      readonly demoId: DemoId;
      readonly message: string;
    };

export interface LifecycleState {
  readonly activeDemo: DemoId | null;
  readonly snapshots: Readonly<Partial<Record<DemoId, SnapshotRecord>>>;
  readonly pending: PendingNavigation | null;
  readonly error: RouteFailure | null;
}

export type LifecycleEvent =
  | {
      readonly type: 'navigation-started';
      readonly mode: 'push' | 'pop';
      readonly to: string;
      readonly destination: DemoId | null;
      readonly source?: {
        readonly demoId: DemoId;
        readonly snapshot: unknown;
        readonly focusToken: string | null;
      };
    }
  | { readonly type: 'forget'; readonly demoId: DemoId }
  | {
      readonly type: 'navigation-requested';
      readonly mode: 'push';
      readonly to: LifecycleHref;
    }
  | {
      readonly type: 'navigation-requested';
      readonly mode: 'back' | 'forward';
    }
  | {
      readonly type: 'navigation-committed';
      readonly destination: DemoId | null;
      readonly fragment: string | null;
    }
  | {
      readonly type: 'navigation-failed';
      readonly message: string;
      readonly retryHref: LifecycleHref;
    }
  | {
      readonly type: 'render-failed';
      readonly demoId: DemoId;
      readonly message: string;
    }
  | { readonly type: 'retry' };

export type LifecycleDecision =
  | { readonly type: 'save-snapshot'; readonly demoId: DemoId }
  | { readonly type: 'dispose-surface'; readonly demoId: DemoId }
  | { readonly type: 'forget-snapshot'; readonly demoId: DemoId }
  | { readonly type: 'navigate'; readonly mode: 'push'; readonly to: LifecycleHref }
  | { readonly type: 'navigate'; readonly mode: 'back' | 'forward' }
  | {
      readonly type: 'mount-surface';
      readonly demoId: DemoId;
      readonly snapshot?: unknown;
    }
  | {
      readonly type: 'focus-route';
      readonly preferred:
        | { readonly kind: 'adapter'; readonly token: string }
        | null;
      readonly fallback: 'route-heading';
      readonly preventScroll: true;
    }
  | {
      readonly type: 'announce-navigation-error';
      readonly phase: 'pre-commit';
      readonly message: string;
      readonly retryHref: LifecycleHref;
    }
  | {
      readonly type: 'show-route-error';
      readonly demoId: DemoId;
      readonly message: string;
    };

export interface LifecycleResult {
  readonly state: LifecycleState;
  readonly decisions: readonly LifecycleDecision[];
}

export function createLifecycleState(activeDemo: DemoId | null = null): LifecycleState {
  return {
    activeDemo,
    snapshots: {},
    pending: null,
    error: null,
  };
}

export function reduceLifecycle(
  state: LifecycleState,
  event: LifecycleEvent,
): LifecycleResult {
  if (event.type === 'forget') {
    const { [event.demoId]: _forgotten, ...snapshots } = state.snapshots;
    return {
      state: { ...state, snapshots },
      decisions: [{ type: 'forget-snapshot', demoId: event.demoId }],
    };
  }
  if (event.type === 'navigation-requested') {
    return {
      state,
      decisions: event.mode === 'push'
        ? [{ type: 'navigate', mode: 'push', to: event.to }]
        : [{ type: 'navigate', mode: event.mode }],
    };
  }
  if (event.type === 'navigation-failed') {
    const error: RouteFailure = {
      phase: 'pre-commit',
      message: event.message,
      retryHref: event.retryHref,
    };
    return {
      state: { ...state, pending: null, error },
      decisions: [{ type: 'announce-navigation-error', ...error }],
    };
  }
  if (event.type === 'render-failed') {
    const error: RouteFailure = {
      phase: 'post-commit',
      demoId: event.demoId,
      message: event.message,
    };
    return {
      state: { ...state, pending: null, error },
      decisions: [
        { type: 'dispose-surface', demoId: event.demoId },
        { type: 'show-route-error', demoId: event.demoId, message: event.message },
      ],
    };
  }
  if (event.type === 'retry') {
    if (state.error === null) return { state, decisions: [] };
    if (state.error.phase === 'pre-commit') {
      return {
        state: { ...state, error: null },
        decisions: [{ type: 'navigate', mode: 'push', to: state.error.retryHref }],
      };
    }
    const { demoId } = state.error;
    const snapshot = state.snapshots[demoId];
    return {
      state: { ...state, error: null },
      decisions: [
        { type: 'dispose-surface', demoId },
        {
          type: 'mount-surface',
          demoId,
          ...(snapshot === undefined ? {} : { snapshot: structuredClone(snapshot.value) }),
        },
      ],
    };
  }
  if (event.type === 'navigation-committed') {
    const snapshot = event.destination === null
      ? undefined
      : state.snapshots[event.destination];
    const preferred = state.pending?.mode === 'pop' && snapshot?.focusToken
      ? { kind: 'adapter' as const, token: snapshot.focusToken }
      : null;
    const disposeDecision: LifecycleDecision[] =
      state.pending?.source !== null &&
      state.pending?.source !== undefined &&
      state.pending.source !== event.destination
        ? [{ type: 'dispose-surface', demoId: state.pending.source }]
        : [];
    const mountDecision: LifecycleDecision[] = event.destination === null
      ? []
      : [{
          type: 'mount-surface',
          demoId: event.destination,
          ...(snapshot === undefined ? {} : { snapshot: structuredClone(snapshot.value) }),
        }];
    return {
      state: {
        ...state,
        activeDemo: event.destination,
        pending: null,
        error: null,
      },
      decisions: [
        ...disposeDecision,
        ...mountDecision,
        {
          type: 'focus-route',
          preferred,
          fallback: 'route-heading',
          preventScroll: true,
        },
      ],
    };
  }

  const source = event.source;
  if (source === undefined) {
    return {
      state: {
        ...state,
        error: null,
        pending: {
          mode: event.mode,
          to: event.to,
          destination: event.destination,
          source: state.activeDemo,
        },
      },
      decisions: [],
    };
  }

  const snapshot: SnapshotRecord = {
    value: structuredClone(source.snapshot),
    focusToken: source.focusToken,
  };
  return {
    state: {
      ...state,
      snapshots: { ...state.snapshots, [source.demoId]: snapshot },
      error: null,
      pending: {
        mode: event.mode,
        to: event.to,
        destination: event.destination,
        source: state.activeDemo,
      },
    },
    decisions: [{ type: 'save-snapshot', demoId: source.demoId }],
  };
}
