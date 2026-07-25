'use client';

/**
 * THROWAWAY WAYFINDER PROTOTYPE — a simple, data-driven demo catalog.
 */
import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import { DEMOS, DEMO_GROUPS } from '../core/demo-catalog';
import './styles.css';

export function WakuHubPrototype() {
  return (
    <div className="demo-hub">
      <a className="skip-link" href="#demo-catalog">Skip to demos</a>

      <main id="demo-catalog">
        <header className="page-heading">
          <h1>Canopy demos</h1>
          <p>Choose a demo to open its interactive page.</p>
        </header>

        <div className="catalog-groups">
          {DEMO_GROUPS.map((group) => {
            const demos = DEMOS.filter((demo) => demo.group === group.id);
            if (demos.length === 0) return null;

            return (
              <section key={group.id} className="catalog-group" aria-labelledby={`group-${group.id}`}>
                <h2 id={`group-${group.id}`}>{group.title}</h2>
                <ul className="demo-list">
                  {demos.map((demo) => (
                    <li key={demo.id}>
                      <a href={demo.href} data-demo-id={demo.id}>
                        <span className="demo-copy">
                          <strong>{demo.title}</strong>
                          <span>{demo.description}</span>
                        </span>
                        <span className="open-label" aria-hidden="true">Open →</span>
                      </a>
                    </li>
                  ))}
                </ul>
              </section>
            );
          })}
        </div>
      </main>
    </div>
  );
}

export function mountWakuHubPrototype(): void {
  const root = document.getElementById('root');
  if (root === null) throw new Error('Missing Waku Hub prototype root');

  createRoot(root).render(
    <StrictMode>
      <WakuHubPrototype />
    </StrictMode>,
  );
}
