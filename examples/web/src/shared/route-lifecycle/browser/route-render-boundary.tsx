'use client';

import { Component, type ErrorInfo, type ReactNode } from 'react';
import { PostCommitRouteError } from './common-states';

interface RouteRenderBoundaryProps {
  readonly children: ReactNode;
  readonly message: string;
  readonly onError: () => void;
  readonly onRetry: () => void;
}

interface RouteRenderBoundaryState {
  readonly failed: boolean;
}

export class RouteRenderBoundary extends Component<
  RouteRenderBoundaryProps,
  RouteRenderBoundaryState
> {
  state: RouteRenderBoundaryState = { failed: false };

  static getDerivedStateFromError(): RouteRenderBoundaryState {
    return { failed: true };
  }

  componentDidCatch(_error: unknown, _errorInfo: ErrorInfo): void {
    this.props.onError();
    requestAnimationFrame(() => {
      document.querySelector<HTMLElement>('[data-route-error-heading]')
        ?.focus({ preventScroll: true });
    });
  }

  render(): ReactNode {
    if (!this.state.failed) return this.props.children;
    return (
      <PostCommitRouteError message={this.props.message} onRetry={this.props.onRetry} />
    );
  }
}
