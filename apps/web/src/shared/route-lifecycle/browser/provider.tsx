'use client';

import {
  createContext,
  type ReactNode,
  useCallback,
  useContext,
  useLayoutEffect,
  useMemo,
  useRef,
  useState,
} from 'react';
import { useRouter } from 'waku/router/client';
import { demoIdForPath, type DemoId } from '../../catalog/demo-catalog';
import {
  type CompatibilityRedirectDecision,
  type CompatibilityRedirectEvent,
  type CompatibilityRoute,
  createCompatibilityRedirectState,
  reduceCompatibilityRedirect,
} from '../core/compatibility-redirect';
import {
  createLifecycleState,
  type LifecycleDecision,
  type LifecycleEvent,
  type LifecycleHref,
  reduceLifecycle,
  type RouteFailure,
} from '../core/reducer';
import { NavigationFailureAlert } from './common-states';
import { applyFocusDecision } from './focus-manager';
import type { MountedImperativeSession } from './imperative-session';
import { recoverPreCommitNavigation } from './navigation-recovery';
import { RouteRenderBoundary } from './route-render-boundary';

interface RegisteredSurface {
  readonly container: HTMLElement;
  readonly session: MountedImperativeSession;
}

interface RegisteredReactRoute {
  snapshot(): unknown;
  restoreFocus(token: string): boolean;
}

interface RouteLifecycleContextValue {
  readonly registerSurface: (
    demoId: DemoId,
    surface: RegisteredSurface,
  ) => () => void;
  readonly snapshotForMount: (demoId: DemoId) => unknown;
  readonly registerReactRoute: (
    demoId: DemoId,
    route: RegisteredReactRoute,
  ) => () => void;
  readonly mountRevision: number;
  readonly forget: (demoId: DemoId) => void;
  readonly navigate: (to: LifecycleHref) => void;
  readonly back: () => void;
  readonly forward: () => void;
}

const RouteLifecycleContext = createContext<RouteLifecycleContextValue | null>(null);
const DEFAULT_ROUTE_ERROR_MESSAGE = 'This demo could not be displayed.';

function safeFocusToken(surface: RegisteredSurface | undefined): string | null {
  if (surface === undefined) return null;
  const active = document.activeElement;
  if (!(active instanceof HTMLElement) || !surface.container.contains(active)) return null;
  return active.closest<HTMLElement>('[data-route-focus]')?.dataset.routeFocus ?? null;
}

export function RouteLifecycleProvider({ children }: { readonly children: ReactNode }) {
  const router = useRouter();
  const lifecycle = useRef(createLifecycleState(demoIdForPath(router.path)));
  const surfaces = useRef(new Map<DemoId, RegisteredSurface>());
  const reactRoutes = useRef(new Map<DemoId, RegisteredReactRoute>());
  const nextMode = useRef<'push' | 'pop'>('push');
  const headingBeforeNavigation = useRef<HTMLElement | null>(null);
  const pendingPreCommitFailure = useRef<LifecycleHref | null>(null);
  const compatibilityRedirect = useRef(createCompatibilityRedirectState());
  const [preCommitError, setPreCommitError] = useState<RouteFailure | null>(null);
  const [ready, setReady] = useState(false);
  const [mountRevision, setMountRevision] = useState(0);
  const [boundaryRevision, setBoundaryRevision] = useState(0);
  const [routeErrorMessage, setRouteErrorMessage] = useState(DEFAULT_ROUTE_ERROR_MESSAGE);

  const executeDecisions = useCallback((decisions: readonly LifecycleDecision[]) => {
    for (const decision of decisions) {
      if (decision.type === 'dispose-surface') {
        surfaces.current.get(decision.demoId)?.session.dispose();
      } else if (decision.type === 'show-route-error') {
        setRouteErrorMessage(decision.message);
      } else if (decision.type === 'navigate') {
        if (decision.mode === 'push') {
          void router.push(decision.to).catch(() => {
            recoverPreCommitNavigation(router, () => {
              pendingPreCommitFailure.current = decision.to;
            });
          });
        } else if (decision.mode === 'back') {
          router.back();
        } else {
          router.forward();
        }
      } else if (decision.type === 'focus-route') {
        let attempts = 0;
        const focusCommittedRoute = () => {
          const heading = document.querySelector<HTMLElement>('[data-route-heading]');
          if (
            heading === headingBeforeNavigation.current &&
            attempts < 60
          ) {
            attempts += 1;
            requestAnimationFrame(focusCommittedRoute);
            return;
          }
          const activeDemo = lifecycle.current.activeDemo;
          const session = activeDemo === null
            ? undefined
            : surfaces.current.get(activeDemo)?.session ?? reactRoutes.current.get(activeDemo);
          applyFocusDecision(decision, {
            document,
            ...(session === undefined ? {} : { session }),
          });
          headingBeforeNavigation.current = null;
        };
        requestAnimationFrame(focusCommittedRoute);
      } else if (decision.type === 'announce-navigation-error') {
        setPreCommitError({
          phase: 'pre-commit',
          message: decision.message,
          retryHref: decision.retryHref,
        });
      } else if (decision.type === 'mount-surface') {
        setMountRevision((revision) => revision + 1);
      }
    }
  // `dispatch` reads only refs and this callback; the declaration is intentionally recursive.
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [router]);

  function dispatch(event: LifecycleEvent): void {
    const result = reduceLifecycle(lifecycle.current, event);
    lifecycle.current = result.state;
    if (result.state.error?.phase !== 'pre-commit') setPreCommitError(null);
    executeDecisions(result.decisions);
  }

  useLayoutEffect(() => {
    let disposed = false;
    compatibilityRedirect.current = createCompatibilityRedirectState();

    function transitionCompatibility(
      event: CompatibilityRedirectEvent,
    ): CompatibilityRedirectDecision {
      const result = reduceCompatibilityRedirect(compatibilityRedirect.current, event);
      compatibilityRedirect.current = result.state;
      return result.decision;
    }

    function executeCompatibilityDecision(
      decision: CompatibilityRedirectDecision,
    ): void {
      if (decision.type === 'observe-history') {
        requestAnimationFrame(() => {
          observeCompatibilityHistory(decision.repairId, decision.attempt);
        });
      } else if (decision.type === 'replace-history') {
        void router.replace(decision.href).catch(() => {
          if (disposed) return;
          executeCompatibilityDecision(transitionCompatibility({
            type: 'replace-rejected',
            repairId: decision.repairId,
          }));
        });
      } else if (decision.type === 'recover-navigation') {
        recoverPreCommitNavigation(router, () => {
          pendingPreCommitFailure.current = decision.href;
        });
      } else if (decision.type === 'commit-navigation') {
        dispatch({
          type: 'navigation-committed',
          destination: demoIdForPath(decision.path),
          fragment: decision.fragment,
        });
        if (!decision.reportPendingFailure) return;
        const failedTarget = pendingPreCommitFailure.current;
        if (failedTarget !== null) {
          pendingPreCommitFailure.current = null;
          dispatch({
            type: 'navigation-failed',
            message: 'The demo could not be loaded.',
            retryHref: failedTarget,
          });
          setBoundaryRevision((revision) => revision + 1);
        }
      }
    }

    function observeCompatibilityHistory(repairId: number, attempt: number): void {
      if (disposed) return;
      const currentUrl = new URL(window.location.href);
      executeCompatibilityDecision(transitionCompatibility({
        type: 'history-observed',
        repairId,
        attempt,
        pathname: currentUrl.pathname,
        search: currentUrl.search,
      }));
    }

    const markPop = () => {
      nextMode.current = 'pop';
    };
    const handleStart = (route: CompatibilityRoute) => {
      const compatibilityDecision = transitionCompatibility({
        type: 'navigation-started',
        route,
      });
      if (compatibilityDecision.type === 'suppress-navigation-start') {
        nextMode.current = 'push';
        return;
      }
      headingBeforeNavigation.current = document.querySelector<HTMLElement>('[data-route-heading]');
      const sourceDemo = lifecycle.current.activeDemo;
      const surface = sourceDemo === null ? undefined : surfaces.current.get(sourceDemo);
      let source: Extract<LifecycleEvent, { type: 'navigation-started' }>['source'];
      if (sourceDemo !== null && surface !== undefined) {
        source = {
          demoId: sourceDemo,
          snapshot: surface.session.snapshot(),
          focusToken: safeFocusToken(surface),
        };
      } else if (sourceDemo !== null) {
        const reactRoute = reactRoutes.current.get(sourceDemo);
        if (reactRoute !== undefined) {
          const active = document.activeElement;
          source = {
            demoId: sourceDemo,
            snapshot: reactRoute.snapshot(),
            focusToken: active instanceof HTMLElement
              ? active.closest<HTMLElement>('[data-route-focus]')?.dataset.routeFocus ?? null
              : null,
          };
        }
      }
      dispatch({
        type: 'navigation-started',
        mode: nextMode.current,
        to: route.path,
        destination: demoIdForPath(route.path),
        ...(source === undefined ? {} : { source }),
      });
      nextMode.current = 'push';
    };
    const handleComplete = (route: CompatibilityRoute) => {
      executeCompatibilityDecision(transitionCompatibility({
        type: 'navigation-completed',
        route,
      }));
    };

    window.addEventListener('popstate', markPop);
    router.unstable_events.on('start', handleStart);
    router.unstable_events.on('complete', handleComplete);
    setReady(true);
    return () => {
      disposed = true;
      window.removeEventListener('popstate', markPop);
      router.unstable_events.off('start', handleStart);
      router.unstable_events.off('complete', handleComplete);
      transitionCompatibility({ type: 'disposed' });
      for (const surface of surfaces.current.values()) surface.session.dispose();
      surfaces.current.clear();
      reactRoutes.current.clear();
    };
  // The pinned Waku router event registry is stable for the provider lifetime.
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [router.unstable_events]);

  const registerSurface = useCallback((demoId: DemoId, surface: RegisteredSurface) => {
    surfaces.current.get(demoId)?.session.dispose();
    surfaces.current.set(demoId, surface);
    return () => {
      if (surfaces.current.get(demoId) !== surface) return;
      surface.session.dispose();
      surfaces.current.delete(demoId);
    };
  }, []);

  const snapshotForMount = useCallback((demoId: DemoId) => {
    const snapshot = lifecycle.current.snapshots[demoId];
    return snapshot === undefined ? undefined : structuredClone(snapshot.value);
  }, []);

  const registerReactRoute = useCallback((demoId: DemoId, route: RegisteredReactRoute) => {
    reactRoutes.current.set(demoId, route);
    return () => {
      if (reactRoutes.current.get(demoId) === route) reactRoutes.current.delete(demoId);
    };
  }, []);

  const actions = useMemo<RouteLifecycleContextValue>(() => ({
    registerSurface,
    snapshotForMount,
    registerReactRoute,
    mountRevision,
    forget: (demoId) => dispatch({ type: 'forget', demoId }),
    navigate: (to) => dispatch({ type: 'navigation-requested', mode: 'push', to }),
    back: () => dispatch({ type: 'navigation-requested', mode: 'back' }),
    forward: () => dispatch({ type: 'navigation-requested', mode: 'forward' }),
  // `dispatch` is a ref-backed command boundary and intentionally not memoized.
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }), [mountRevision, registerReactRoute, registerSurface, snapshotForMount]);

  const reportRenderFailure = useCallback(() => {
    if (lifecycle.current.pending !== null) return;
    const demoId = lifecycle.current.activeDemo;
    if (demoId === null) return;
    dispatch({
      type: 'render-failed',
      demoId,
      message: DEFAULT_ROUTE_ERROR_MESSAGE,
    });
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const retryRender = useCallback(() => {
    dispatch({ type: 'retry' });
    setRouteErrorMessage(DEFAULT_ROUTE_ERROR_MESSAGE);
    setBoundaryRevision((revision) => revision + 1);
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  return (
    <RouteLifecycleContext.Provider value={actions}>
      <div data-route-lifecycle-ready={ready ? 'true' : 'false'}>
        {preCommitError?.phase === 'pre-commit' ? (
          <NavigationFailureAlert
            message={preCommitError.message}
            retryHref={preCommitError.retryHref}
            onRetry={() => dispatch({ type: 'retry' })}
          />
        ) : null}
        <RouteRenderBoundary
          key={boundaryRevision}
          message={routeErrorMessage}
          onError={reportRenderFailure}
          onRetry={retryRender}
        >
          {children}
        </RouteRenderBoundary>
      </div>
    </RouteLifecycleContext.Provider>
  );
}

export function useRouteLifecycle(): RouteLifecycleContextValue {
  const value = useContext(RouteLifecycleContext);
  if (value === null) throw new Error('Route lifecycle context is unavailable');
  return value;
}

export function useRouteSnapshot<Snapshot>(
  demoId: DemoId,
  adapter: {
    readonly snapshot: () => Snapshot;
    readonly restoreFocus: (token: string) => boolean;
  },
): Snapshot | undefined {
  const lifecycle = useRouteLifecycle();
  const adapterRef = useRef(adapter);
  adapterRef.current = adapter;
  const restored = useRef<Snapshot | undefined>(
    lifecycle.snapshotForMount(demoId) as Snapshot | undefined,
  );

  useLayoutEffect(
    () => lifecycle.registerReactRoute(demoId, {
      snapshot: () => adapterRef.current.snapshot(),
      restoreFocus: (token) => adapterRef.current.restoreFocus(token),
    }),
    [demoId, lifecycle.registerReactRoute],
  );
  return restored.current;
}
