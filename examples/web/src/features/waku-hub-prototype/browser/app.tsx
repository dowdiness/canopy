'use client';

/**
 * THROWAWAY WAYFINDER PROTOTYPE — a deliberately simple, data-driven catalog.
 * The Hub explains each demo and follows the existing demo URL directly.
 */
import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import { DEMOS, DEMO_GROUPS } from '../core/demo-catalog';
import './styles.css';

export function WakuHubPrototype() {
  return (
    <div className="demo-hub">
      <a className="skip-link" href="#demo-catalog">Skip to demonstrations</a>

      <header className="site-header">
        <div className="site-identity" aria-label="Canopy demonstrations">
          <strong>CANOPY</strong>
          <span>Demos</span>
        </div>
        <span className="demo-count">{DEMOS.length} demonstrations</span>
      </header>

      <main id="demo-catalog">
        <header className="page-heading">
          <p className="eyebrow">Working examples</p>
          <h1>Demonstrations</h1>
          <p>
            Explore how Canopy edits structured content, recalls evidence, and
            keeps generated changes inspectable. Select a demo to open it.
          </p>
        </header>

        <div className="catalog-groups">
          {DEMO_GROUPS.map((group) => {
            const demos = DEMOS.filter((demo) => demo.group === group.id);
            if (demos.length === 0) return null;

            return (
              <section key={group.id} className="catalog-group" aria-labelledby={`group-${group.id}`}>
                <header>
                  <h2 id={`group-${group.id}`}>{group.title}</h2>
                  <p>{group.description}</p>
                </header>
                <ul className="demo-list">
                  {demos.map((demo) => (
                    <li key={demo.id}>
                      <a href={demo.href} data-demo-id={demo.id}>
                        <span className="demo-copy">
                          <strong>{demo.title}</strong>
                          <span>{demo.description}</span>
                        </span>
                        <span className="open-label">
                          Open demo <span aria-hidden="true">→</span>
                        </span>
                      </a>
                    </li>
                  ))}
                </ul>
              </section>
            );
          })}
        </div>
      </main>

      <footer>
        <span>Canopy</span>
        <a href="https://github.com/dowdiness/canopy">View source</a>
      </footer>
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
