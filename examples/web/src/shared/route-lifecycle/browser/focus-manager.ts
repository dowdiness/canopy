import type { LifecycleDecision } from '../core/reducer';

type FocusDecision = Extract<LifecycleDecision, { readonly type: 'focus-route' }>;

interface FocusTarget {
  focus(options?: FocusOptions): void;
}

interface FocusDocument {
  querySelector(selector: string): FocusTarget | null;
}

interface FocusSession {
  restoreFocus(token: string): boolean;
}

export type FocusOutcome = 'preferred' | 'route-heading' | 'none';

export function applyFocusDecision(
  decision: FocusDecision,
  dependencies: {
    readonly document: FocusDocument;
    readonly session?: FocusSession;
  },
): FocusOutcome {
  const { preferred } = decision;
  if (
    preferred?.kind === 'adapter' &&
    dependencies.session?.restoreFocus(preferred.token) === true
  ) {
    return 'preferred';
  }
  const heading = dependencies.document.querySelector('[data-route-heading]');
  if (heading === null) return 'none';
  heading.focus({ preventScroll: decision.preventScroll });
  return 'route-heading';
}
