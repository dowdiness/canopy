'use client';

import type { ReactNode } from 'react';
import { ImperativeDemoHost } from '../../../shared/route-lifecycle/browser/imperative-host';
import { mountPosts } from '../browser/mount';

export function PostsClient({ children }: { readonly children: ReactNode }) {
  return (
    <ImperativeDemoHost
      demoId="posts"
      mount={mountPosts}
      className="posts-surface"
    >
      {children}
    </ImperativeDemoHost>
  );
}
