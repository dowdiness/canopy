import { DEMOS, demoIdForPath } from '../../src/shared/catalog/demo-catalog.ts';

export const SIGNALING_PATH = '/signaling';

export type WorkerRouteClass =
  | 'hub'
  | 'canonical-demo'
  | 'compatibility-alias'
  | 'rsc'
  | 'static-asset'
  | 'signaling'
  | 'unknown';

export type WorkerCapability =
  | 'application'
  | 'navigation'
  | 'rsc'
  | 'static-asset'
  | 'websocket';

type RequestMetadata = Readonly<{
  routeClass: WorkerRouteClass;
  capability: WorkerCapability;
}>;

export type WakuRequestDecision = RequestMetadata & (
  | Readonly<{ action: 'continue' }>
  | Readonly<{ action: 'redirect'; location: string }>
  | Readonly<{ action: 'serve-static-asset' }>
  | Readonly<{ action: 'proxy-signaling' }>
);

export type WakuRequestFacts = Readonly<{
  pathname: string;
  search: string;
}>;

export function decideWakuRequest(facts: WakuRequestFacts): WakuRequestDecision {
  const compatibilityRoute = DEMOS.find(
    ({ legacyHref }) => legacyHref === facts.pathname,
  );
  if (compatibilityRoute !== undefined) {
    return {
      action: 'redirect',
      location: `${compatibilityRoute.href}${facts.search}`,
      routeClass: 'compatibility-alias',
      capability: 'navigation',
    };
  }
  const compatibilityRscRoute = DEMOS.find(
    ({ legacyHref }) => legacyHref !== undefined &&
      `/RSC/R${legacyHref}.txt` === facts.pathname,
  );
  if (compatibilityRscRoute !== undefined) {
    return {
      action: 'redirect',
      location: `/RSC/R${compatibilityRscRoute.href}.txt${facts.search}`,
      routeClass: 'compatibility-alias',
      capability: 'rsc',
    };
  }

  if (facts.pathname === SIGNALING_PATH) {
    return {
      action: 'proxy-signaling',
      routeClass: 'signaling',
      capability: 'websocket',
    };
  }

  if (facts.pathname === '/' || facts.pathname === '/index.html') {
    return {
      action: 'continue',
      routeClass: 'hub',
      capability: 'application',
    };
  }
  if (demoIdForPath(facts.pathname) !== null) {
    return {
      action: 'continue',
      routeClass: 'canonical-demo',
      capability: 'application',
    };
  }
  if (facts.pathname.startsWith('/RSC/')) {
    return {
      action: 'continue',
      routeClass: 'rsc',
      capability: 'rsc',
    };
  }
  if (facts.pathname.startsWith('/assets/')) {
    return {
      action: 'serve-static-asset',
      routeClass: 'static-asset',
      capability: 'static-asset',
    };
  }
  return {
    action: 'continue',
    routeClass: 'unknown',
    capability: 'application',
  };
}
