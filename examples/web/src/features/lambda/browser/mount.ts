'use client';

// Legacy Vite entry point for the Mini-ML editor.

import * as crdt from '@moonbit/crdt-lambda';
import * as graphviz from '@moonbit/graphviz';
import './styles.css';
import { mountLambdaEditor } from './editor';

export function mountLambda(): void {
  mountLambdaEditor(document, undefined, crdt, graphviz);
}
