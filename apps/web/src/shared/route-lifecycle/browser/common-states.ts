'use client';

import { createElement, type ReactElement } from 'react';
import type { LifecycleHref } from '../core/reducer';

export function NavigationFailureAlert({
  message,
  retryHref,
  onRetry,
}: {
  readonly message: string;
  readonly retryHref: LifecycleHref;
  readonly onRetry: () => void;
}): ReactElement {
  return createElement('div', { className: 'navigation-alert', role: 'alert' }, [
    createElement('p', { key: 'message' }, message),
    createElement('div', { className: 'route-state__actions', key: 'actions' }, [
      createElement('button', { type: 'button', onClick: onRetry, key: 'retry' }, 'Retry'),
      createElement('a', { href: retryHref, key: 'fallback' }, 'Open directly'),
    ]),
  ]);
}

export function PostCommitRouteError({
  message,
  onRetry,
}: {
  readonly message: string;
  readonly onRetry: () => void;
}): ReactElement {
  return createElement('main', {
    className: 'route-state route-state--error',
    role: 'alert',
  }, [
    createElement('p', { className: 'route-state__label', key: 'label' }, 'Demo error'),
    createElement('h1', {
      tabIndex: -1,
      'data-route-error-heading': true,
      key: 'heading',
    }, 'This demo could not be displayed'),
    createElement('p', { key: 'message' }, message),
    createElement(
      'p',
      { key: 'recovery' },
      'The destination remains selected. Retry the demo or return to the catalog.',
    ),
    createElement('div', { className: 'route-state__actions', key: 'actions' }, [
      createElement('button', { type: 'button', onClick: onRetry, key: 'retry' }, 'Retry'),
      createElement('a', { href: '/', key: 'back' }, 'Back to demos'),
    ]),
  ]);
}
