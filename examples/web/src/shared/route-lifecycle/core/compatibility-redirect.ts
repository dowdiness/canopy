import { DEMOS, type DemoPath } from '../../catalog/demo-catalog.ts';
import type { LifecycleHref } from './reducer';

export const MAX_COMPATIBILITY_HISTORY_ATTEMPTS = 60;

export interface CompatibilityRoute {
  readonly path: string;
  readonly query: string;
  readonly hash: string;
}

interface PendingCompatibilityRedirect {
  readonly id: number;
  readonly canonicalPath: DemoPath;
  readonly query: string;
  readonly hash: string;
}

export interface CompatibilityRedirectState {
  readonly nextId: number;
  readonly pending: PendingCompatibilityRedirect | null;
  readonly activeRepairId: number | null;
  readonly disposed: boolean;
}

export type CompatibilityRedirectEvent =
  | { readonly type: 'navigation-started'; readonly route: CompatibilityRoute }
  | { readonly type: 'navigation-completed'; readonly route: CompatibilityRoute }
  | {
      readonly type: 'history-observed';
      readonly repairId: number;
      readonly attempt: number;
      readonly pathname: string;
      readonly search: string;
    }
  | { readonly type: 'replace-rejected'; readonly repairId: number }
  | { readonly type: 'disposed' };

export type CompatibilityRedirectDecision =
  | { readonly type: 'none' }
  | { readonly type: 'suppress-navigation-start' }
  | {
      readonly type: 'observe-history';
      readonly repairId: number;
      readonly attempt: number;
    }
  | {
      readonly type: 'replace-history';
      readonly repairId: number;
      readonly href: LifecycleHref;
    }
  | {
      readonly type: 'commit-navigation';
      readonly path: string;
      readonly fragment: string | null;
      readonly reportPendingFailure: boolean;
    }
  | { readonly type: 'recover-navigation'; readonly href: LifecycleHref };

export interface CompatibilityRedirectResult {
  readonly state: CompatibilityRedirectState;
  readonly decision: CompatibilityRedirectDecision;
}

export function createCompatibilityRedirectState(): CompatibilityRedirectState {
  return {
    nextId: 0,
    pending: null,
    activeRepairId: null,
    disposed: false,
  };
}

function compatibilityTarget(pending: PendingCompatibilityRedirect): {
  readonly search: string;
  readonly href: LifecycleHref;
} {
  const search = pending.query === '' ? '' : `?${pending.query}`;
  return {
    search,
    href: `${pending.canonicalPath}${search}${pending.hash}` as LifecycleHref,
  };
}

export function reduceCompatibilityRedirect(
  state: CompatibilityRedirectState,
  event: CompatibilityRedirectEvent,
): CompatibilityRedirectResult {
  if (event.type === 'disposed') {
    return {
      state: { ...state, pending: null, activeRepairId: null, disposed: true },
      decision: { type: 'none' },
    };
  }
  if (state.disposed) return { state, decision: { type: 'none' } };

  if (event.type === 'navigation-started') {
    const active = state.pending?.id === state.activeRepairId ? state.pending : null;
    if (
      active !== null &&
      event.route.path === active.canonicalPath &&
      event.route.query === active.query &&
      event.route.hash === active.hash
    ) {
      return { state, decision: { type: 'suppress-navigation-start' } };
    }

    const compatibilityDemo = DEMOS.find(
      (demo) => demo.legacyHref === event.route.path,
    );
    if (compatibilityDemo === undefined || event.route.hash === '') {
      return {
        state: { ...state, pending: null, activeRepairId: null },
        decision: { type: 'none' },
      };
    }

    const pending: PendingCompatibilityRedirect = {
      id: state.nextId,
      canonicalPath: compatibilityDemo.href,
      query: event.route.query,
      hash: event.route.hash,
    };
    return {
      state: {
        ...state,
        nextId: state.nextId + 1,
        pending,
        activeRepairId: null,
      },
      decision: { type: 'none' },
    };
  }

  if (event.type === 'navigation-completed') {
    const pending = state.pending;
    if (
      pending !== null &&
      event.route.path === pending.canonicalPath &&
      event.route.query === pending.query &&
      event.route.hash === ''
    ) {
      return {
        state,
        decision: { type: 'observe-history', repairId: pending.id, attempt: 0 },
      };
    }
    return {
      state: { ...state, pending: null, activeRepairId: null },
      decision: {
        type: 'commit-navigation',
        path: event.route.path,
        fragment: event.route.hash.startsWith('#') ? event.route.hash.slice(1) : null,
        reportPendingFailure: true,
      },
    };
  }

  const pending = state.pending;
  if (pending === null || pending.id !== event.repairId) {
    return { state, decision: { type: 'none' } };
  }

  if (event.type === 'replace-rejected') {
    if (state.activeRepairId !== event.repairId) {
      return { state, decision: { type: 'none' } };
    }
    return {
      state: { ...state, pending: null, activeRepairId: null },
      decision: {
        type: 'recover-navigation',
        href: compatibilityTarget(pending).href,
      },
    };
  }

  const target = compatibilityTarget(pending);
  if (event.pathname === pending.canonicalPath && event.search === target.search) {
    return {
      state: { ...state, activeRepairId: pending.id },
      decision: {
        type: 'replace-history',
        repairId: pending.id,
        href: target.href,
      },
    };
  }
  if (event.attempt < MAX_COMPATIBILITY_HISTORY_ATTEMPTS) {
    return {
      state,
      decision: {
        type: 'observe-history',
        repairId: pending.id,
        attempt: event.attempt + 1,
      },
    };
  }
  return {
    state: { ...state, pending: null, activeRepairId: null },
    decision: {
      type: 'commit-navigation',
      path: pending.canonicalPath,
      fragment: null,
      reportPendingFailure: false,
    },
  };
}
