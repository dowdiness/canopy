'use client';

import './styles.css';
import * as crdt from '@moonbit/crdt-json';
import { mountJsonEditor } from './editor';
import type { MountedImperativeSession } from '../../../shared/route-lifecycle/browser/imperative-session';

export function mountJson(
  root: Document | HTMLElement = globalThis.document,
  restoredSnapshot?: unknown,
): MountedImperativeSession {
  return mountJsonEditor(root, restoredSnapshot, crdt);
}
