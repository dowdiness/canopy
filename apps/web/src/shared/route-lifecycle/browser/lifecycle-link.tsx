'use client';

import type { AnchorHTMLAttributes, MouseEvent, ReactNode } from 'react';
import { Link } from 'waku/router/client';
import type { LifecycleHref } from '../core/reducer';
import { useRouteLifecycle } from './provider';

interface LifecycleLinkProps extends Omit<AnchorHTMLAttributes<HTMLAnchorElement>, 'href'> {
  readonly to: LifecycleHref;
  readonly children: ReactNode;
}

function isModifiedClick(event: MouseEvent<HTMLAnchorElement>): boolean {
  return event.button !== 0 || event.metaKey || event.altKey || event.ctrlKey || event.shiftKey;
}

export function LifecycleLink({
  to,
  children,
  onClick,
  target,
  download,
  ...props
}: LifecycleLinkProps) {
  const lifecycle = useRouteLifecycle();
  const downloads = download !== undefined && download !== null && download !== false;
  if ((target !== undefined && target.toLowerCase() !== '_self') || downloads) {
    return (
      <a {...props} href={to} target={target} download={download} onClick={onClick}>
        {children}
      </a>
    );
  }

  return (
    <Link
      {...props}
      to={to}
      onClick={(event) => {
        onClick?.(event);
        if (event.defaultPrevented || isModifiedClick(event)) return;
        event.preventDefault();
        lifecycle.navigate(to);
      }}
    >
      {children}
    </Link>
  );
}
