import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import { JsonReactBoundaryPrototype } from './app';

const root = document.getElementById('root');
if (!root) throw new Error('Missing prototype root');

createRoot(root).render(
  <StrictMode>
    <JsonReactBoundaryPrototype />
  </StrictMode>,
);
