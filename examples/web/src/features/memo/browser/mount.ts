'use client';

import * as runtime from '@moonbit/crdt-lambda';
import { mountMemoApp } from './app';
import './styles.css';

export function mountMemo(): void {
  mountMemoApp(document, undefined, runtime);
}
