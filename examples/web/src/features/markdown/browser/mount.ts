'use client';

import './styles.css';
import * as crdt from '@moonbit/crdt-markdown';
import { mountMarkdownApp } from './app';
import type { MountedImperativeSession } from '../../../shared/route-lifecycle/browser/imperative-session';

export function mountMarkdown(
  root: Document | HTMLElement = globalThis.document,
  restoredSnapshot?: unknown,
): MountedImperativeSession {
  return mountMarkdownApp(root, restoredSnapshot, crdt);
}
