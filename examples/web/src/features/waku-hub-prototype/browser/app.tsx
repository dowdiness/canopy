'use client';

/**
 * THROWAWAY WAYFINDER PROTOTYPE — three structurally different answers to
 * “How should the Waku Demo Hub introduce all eight demos and preserve
 * orientation inside a demo?”, switchable with ?variant=A|B|C.
 */
import { StrictMode, useEffect, useState, type MouseEvent } from 'react';
import { createRoot } from 'react-dom/client';
import './styles.css';

type VariantId = 'A' | 'B' | 'C';
type DemoId =
  | 'lambda'
  | 'json'
  | 'markdown'
  | 'memo'
  | 'posts'
  | 'resume'
  | 'genui'
  | 'journey';
type ScreenId = 'hub' | DemoId;

interface DemoDefinition {
  readonly id: DemoId;
  readonly index: string;
  readonly title: string;
  readonly shortTitle: string;
  readonly route: string;
  readonly material: string;
  readonly question: string;
  readonly description: string;
  readonly evidence: string;
  readonly status: string;
  readonly group: 'Structure' | 'Memory' | 'Decisions';
}

interface JourneyDefinition {
  readonly number: string;
  readonly title: string;
  readonly prompt: string;
  readonly demoIds: readonly DemoId[];
}

interface LocationState {
  readonly variant: VariantId;
  readonly screen: ScreenId;
}

const DEMOS: readonly DemoDefinition[] = [
  {
    id: 'lambda',
    index: '01',
    title: 'Mini-ML editor',
    shortTitle: 'Mini-ML',
    route: '/index.html',
    material: 'Typed programs',
    question: 'How does source become structure and evaluation?',
    description: 'Write a typed program, inspect its syntax tree, and see diagnostics beside the source.',
    evidence: 'AST · evaluation · collaboration',
    status: 'Browser + local AST analysis',
    group: 'Structure',
  },
  {
    id: 'json',
    index: '02',
    title: 'JSON editor',
    shortTitle: 'JSON',
    route: '/json.html',
    material: 'Structured data',
    question: 'Can structure stay legible while the text changes?',
    description: 'Edit JSON as text or a structural tree while CRDT identity and edit history remain visible.',
    evidence: 'Structure · roles · edit log',
    status: 'Browser',
    group: 'Structure',
  },
  {
    id: 'markdown',
    index: '03',
    title: 'Markdown editor',
    shortTitle: 'Markdown',
    route: '/markdown.html',
    material: 'Documents',
    question: 'Can one document support several faithful views?',
    description: 'Move between block, source, and reading views without losing the document or your place.',
    evidence: 'Blocks · source · preview',
    status: 'Browser',
    group: 'Structure',
  },
  {
    id: 'memo',
    index: '04',
    title: 'Canopy Memo',
    shortTitle: 'Memo',
    route: '/memo.html',
    material: 'Working notes',
    question: 'How should assisted edits remain inspectable?',
    description: 'Review typo corrections and structured edits against the note they would change.',
    evidence: 'Suggestions · structured edits',
    status: 'Browser',
    group: 'Memory',
  },
  {
    id: 'posts',
    index: '05',
    title: 'Posts',
    shortTitle: 'Posts',
    route: '/posts.html',
    material: 'Personal fragments',
    question: 'What should return while you are writing?',
    description: 'Capture a thought locally and let related older posts return without replacing chronology.',
    evidence: 'Local persistence · retrieval',
    status: 'Browser · local data',
    group: 'Memory',
  },
  {
    id: 'resume',
    index: '06',
    title: 'Session Resume',
    shortTitle: 'Resume',
    route: '/resume.html',
    material: 'Agent sessions',
    question: 'How can a long session become inspectable evidence?',
    description: 'Trace a session through timeline, conversation, sources, and explicitly attached chat context.',
    evidence: 'Timeline · transcript · evidence',
    status: 'Browser + local chat relay',
    group: 'Memory',
  },
  {
    id: 'genui',
    index: '07',
    title: 'Generative UI',
    shortTitle: 'GenUI',
    route: '/genui.html',
    material: 'Generated interfaces',
    question: 'Can generated JSX stay parseable and testable?',
    description: 'Inspect an incrementally parsed interface and evaluate recorded candidates against real data.',
    evidence: 'JSX · data · feasibility',
    status: 'Browser · live study is local only',
    group: 'Decisions',
  },
  {
    id: 'journey',
    index: '08',
    title: 'Journey responses',
    shortTitle: 'Journey',
    route: '/genui-possibilities.html',
    material: 'Proposed changes',
    question: 'How should a person compare and apply generated change?',
    description: 'Compare responses on shared evidence, preview the exact effect, then apply or undo deliberately.',
    evidence: 'Reasons · preview · revision',
    status: 'Browser',
    group: 'Decisions',
  },
];

const JOURNEYS: readonly JourneyDefinition[] = [
  {
    number: 'I',
    title: 'Understand structure',
    prompt: 'I want to see how editable material becomes a stable, inspectable structure.',
    demoIds: ['lambda', 'json', 'markdown'],
  },
  {
    number: 'II',
    title: 'Recover context',
    prompt: 'I want useful prior material to return without losing provenance or chronology.',
    demoIds: ['memo', 'posts', 'resume'],
  },
  {
    number: 'III',
    title: 'Judge generated change',
    prompt: 'I want to inspect generated output before deciding whether it should affect an artifact.',
    demoIds: ['genui', 'journey'],
  },
];

const VARIANT_NAMES: Readonly<Record<VariantId, string>> = {
  A: 'Workshop index',
  B: 'Instrument register',
  C: 'Guided trails',
};
const VARIANTS: readonly VariantId[] = ['A', 'B', 'C'];

function readLocation(): LocationState {
  const search = new URLSearchParams(window.location.search);
  const rawVariant = search.get('variant');
  const variant: VariantId = rawVariant === 'B' || rawVariant === 'C' ? rawVariant : 'A';
  const rawScreen = search.get('screen');
  const screen = DEMOS.some((demo) => demo.id === rawScreen) ? rawScreen as DemoId : 'hub';
  return { variant, screen };
}

function prototypeHref(variant: VariantId, screen: ScreenId): string {
  const search = new URLSearchParams({ variant });
  if (screen !== 'hub') search.set('screen', screen);
  return `/waku-hub-prototype.html?${search.toString()}`;
}

export function WakuHubPrototype() {
  const [location, setLocation] = useState<LocationState>(readLocation);

  useEffect(() => {
    const handlePopState = () => setLocation(readLocation());
    window.addEventListener('popstate', handlePopState);
    return () => window.removeEventListener('popstate', handlePopState);
  }, []);

  useEffect(() => {
    if (!import.meta.env.DEV) return;
    const handleKeyDown = (event: KeyboardEvent) => {
      if (event.key !== 'ArrowLeft' && event.key !== 'ArrowRight') return;
      const target = event.target;
      if (target instanceof HTMLElement && target.closest('input, textarea, [contenteditable]')) return;
      const offset = event.key === 'ArrowLeft' ? -1 : 1;
      const index = VARIANTS.indexOf(location.variant);
      const variant = VARIANTS[(index + offset + VARIANTS.length) % VARIANTS.length];
      replaceVariant(variant);
    };
    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [location]);

  const visit = (event: MouseEvent<HTMLAnchorElement>, screen: ScreenId) => {
    if (event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
    event.preventDefault();
    const next = { ...location, screen };
    window.history.pushState(null, '', prototypeHref(next.variant, next.screen));
    setLocation(next);
    requestAnimationFrame(() => document.querySelector<HTMLElement>('#prototype-main')?.focus());
  };

  const replaceVariant = (variant: VariantId) => {
    const next = { ...location, variant };
    window.history.replaceState(null, '', prototypeHref(next.variant, next.screen));
    setLocation(next);
  };

  const page = location.variant === 'A'
    ? <VariantA location={location} visit={visit} />
    : location.variant === 'B'
      ? <VariantB location={location} visit={visit} />
      : <VariantC location={location} visit={visit} />;

  return (
    <>
      <a className="prototype-skip-link" href="#prototype-main">Skip to main content</a>
      {page}
      {import.meta.env.DEV ? (
        <PrototypeSwitcher current={location.variant} onChange={replaceVariant} />
      ) : null}
    </>
  );
}

interface VariantProps {
  readonly location: LocationState;
  readonly visit: (event: MouseEvent<HTMLAnchorElement>, screen: ScreenId) => void;
}

function VariantA({ location, visit }: VariantProps) {
  const current = DEMOS.find((demo) => demo.id === location.screen);
  return (
    <div className="variant-a prototype-page" data-variant="A">
      <aside className="a-directory" aria-label="Demo directory">
        <a className="prototype-wordmark" href={prototypeHref('A', 'hub')} onClick={(event) => visit(event, 'hub')}>
          CANOPY
        </a>
        <div className="a-directory-heading">
          <span>Demonstrations</span>
          <strong>8 instruments</strong>
        </div>
        <nav aria-label="All demonstrations">
          <a className={location.screen === 'hub' ? 'is-current' : ''} href={prototypeHref('A', 'hub')} onClick={(event) => visit(event, 'hub')}>
            <span>00</span><strong>Index</strong>
          </a>
          {DEMOS.map((demo) => (
            <a key={demo.id} className={location.screen === demo.id ? 'is-current' : ''} aria-current={location.screen === demo.id ? 'page' : undefined} href={prototypeHref('A', demo.id)} onClick={(event) => visit(event, demo.id)}>
              <span>{demo.index}</span><strong>{demo.shortTitle}</strong>
            </a>
          ))}
        </nav>
        <p className="prototype-note">Prototype A · The directory remains visible as the artifact changes.</p>
      </aside>
      <main id="prototype-main" tabIndex={-1}>
        {current ? <DemoPreview demo={current} variant="A" visit={visit} /> : <WorkshopIndex visit={visit} />}
      </main>
    </div>
  );
}

function WorkshopIndex({ visit }: Pick<VariantProps, 'visit'>) {
  return (
    <div className="a-index">
      <header className="a-intro">
        <p className="prototype-kicker">Canopy demonstrations · current workspace</p>
        <h1>Choose the structure you want to understand.</h1>
        <p>Eight demonstrations show different parts of one idea: editable material should remain legible while its structure, context, or proposed changes evolve.</p>
      </header>
      <div className="a-groups">
        {(['Structure', 'Memory', 'Decisions'] as const).map((group, groupIndex) => (
          <section key={group} className="a-group" aria-labelledby={`a-${group.toLowerCase()}`}>
            <header>
              <span>0{groupIndex + 1}</span>
              <div>
                <h2 id={`a-${group.toLowerCase()}`}>{group}</h2>
                <p>{group === 'Structure' ? 'See how text becomes navigable form.' : group === 'Memory' ? 'Bring prior context back with its source attached.' : 'Inspect a proposal before it changes an artifact.'}</p>
              </div>
            </header>
            <div className="a-demo-list">
              {DEMOS.filter((demo) => demo.group === group).map((demo) => (
                <DemoAnchor key={demo.id} demo={demo} variant="A" visit={visit} mode="row" />
              ))}
            </div>
          </section>
        ))}
      </div>
    </div>
  );
}

function VariantB({ location, visit }: VariantProps) {
  const current = DEMOS.find((demo) => demo.id === location.screen);
  return (
    <div className="variant-b prototype-page" data-variant="B">
      <header className="b-header">
        <a className="prototype-wordmark" href={prototypeHref('B', 'hub')} onClick={(event) => visit(event, 'hub')}>CANOPY / LAB</a>
        <span>{current ? `Instrument ${current.index} of 08` : 'Demonstration register'}</span>
        <a href="https://github.com/dowdiness/canopy" target="_blank" rel="noreferrer">Source ↗</a>
      </header>
      <nav className="b-route-strip" aria-label="Demonstrations">
        <a className={location.screen === 'hub' ? 'is-current' : ''} href={prototypeHref('B', 'hub')} onClick={(event) => visit(event, 'hub')}>Register</a>
        {DEMOS.map((demo) => (
          <a key={demo.id} className={location.screen === demo.id ? 'is-current' : ''} aria-current={location.screen === demo.id ? 'page' : undefined} href={prototypeHref('B', demo.id)} onClick={(event) => visit(event, demo.id)}>{demo.shortTitle}</a>
        ))}
      </nav>
      <main id="prototype-main" tabIndex={-1}>
        {current ? <DemoPreview demo={current} variant="B" visit={visit} /> : <InstrumentRegister visit={visit} />}
      </main>
    </div>
  );
}

function InstrumentRegister({ visit }: Pick<VariantProps, 'visit'>) {
  return (
    <div className="b-register">
      <header>
        <p className="prototype-kicker">Prototype B · compare before entering</p>
        <h1>Demonstration register</h1>
        <p>A compact inventory for people who already know what kind of evidence they need.</p>
      </header>
      <div className="b-table" aria-label="Canopy demonstrations">
        <div className="b-table-head" aria-hidden="true">
          <span>Instrument</span>
          <span>Material</span>
          <span>Question answered</span>
          <span>Runtime boundary</span>
        </div>
        {DEMOS.map((demo) => (
          <a key={demo.id} href={prototypeHref('B', demo.id)} onClick={(event) => visit(event, demo.id)}>
            <span><small>{demo.index}</small><strong>{demo.title}</strong></span>
            <span data-label="Material">{demo.material}</span>
            <span data-label="Question">{demo.question}</span>
            <span data-label="Runtime">{demo.status}<b aria-hidden="true">→</b></span>
          </a>
        ))}
      </div>
    </div>
  );
}

function VariantC({ location, visit }: VariantProps) {
  const current = DEMOS.find((demo) => demo.id === location.screen);
  return (
    <div className="variant-c prototype-page" data-variant="C">
      <header className="c-header">
        <a className="prototype-wordmark" href={prototypeHref('C', 'hub')} onClick={(event) => visit(event, 'hub')}>CANOPY</a>
        <p><span>Path</span> {current ? `${current.group} / ${current.title}` : 'Choose a question'}</p>
        <a href={prototypeHref('C', 'hub')} onClick={(event) => visit(event, 'hub')}>Start again</a>
      </header>
      <main id="prototype-main" tabIndex={-1}>
        {current ? <DemoPreview demo={current} variant="C" visit={visit} /> : <GuidedTrails visit={visit} />}
      </main>
      <nav className="c-tape" aria-label="All demonstrations">
        {DEMOS.map((demo) => (
          <a key={demo.id} className={location.screen === demo.id ? 'is-current' : ''} aria-current={location.screen === demo.id ? 'page' : undefined} href={prototypeHref('C', demo.id)} onClick={(event) => visit(event, demo.id)}>
            <span>{demo.index}</span><strong>{demo.shortTitle}</strong>
          </a>
        ))}
      </nav>
    </div>
  );
}

function GuidedTrails({ visit }: Pick<VariantProps, 'visit'>) {
  return (
    <div className="c-trails">
      <header>
        <p className="prototype-kicker">Prototype C · enter through a human question</p>
        <h1>What are you trying to make legible?</h1>
        <p>Choose a trail. Each one moves from a familiar artifact toward the evidence needed to understand it.</p>
      </header>
      <div className="c-journeys">
        {JOURNEYS.map((journey) => (
          <section key={journey.number} aria-labelledby={`journey-${journey.number}`}>
            <span className="c-journey-number">{journey.number}</span>
            <div className="c-journey-copy">
              <h2 id={`journey-${journey.number}`}>{journey.title}</h2>
              <p>{journey.prompt}</p>
            </div>
            <div className="c-journey-stops">
              {journey.demoIds.map((id) => {
                const demo = DEMOS.find((candidate) => candidate.id === id);
                if (!demo) return null;
                return <DemoAnchor key={demo.id} demo={demo} variant="C" visit={visit} mode="stop" />;
              })}
            </div>
          </section>
        ))}
      </div>
    </div>
  );
}

interface DemoPreviewProps extends Pick<VariantProps, 'visit'> {
  readonly demo: DemoDefinition;
  readonly variant: VariantId;
}

function DemoPreview({ demo, variant, visit }: DemoPreviewProps) {
  const groupDemos = DEMOS.filter((candidate) => candidate.group === demo.group);
  return (
    <article className={`demo-preview demo-preview-${variant.toLowerCase()}`}>
      <header className="demo-preview-heading">
        <div>
          <p className="prototype-kicker">{demo.group} · instrument {demo.index}</p>
          <h1>{demo.title}</h1>
          <p>{demo.description}</p>
        </div>
        <a className="open-current-demo" href={demo.route}>Open current demo <span aria-hidden="true">↗</span></a>
      </header>
      <section className="demo-context" aria-labelledby="demo-context-title">
        <div>
          <p className="prototype-kicker">Focal question</p>
          <h2 id="demo-context-title">{demo.question}</h2>
        </div>
        <dl>
          <div><dt>Material</dt><dd>{demo.material}</dd></div>
          <div><dt>Evidence</dt><dd>{demo.evidence}</dd></div>
          <div><dt>Boundary</dt><dd>{demo.status}</dd></div>
        </dl>
      </section>
      <section className="demo-placeholder" aria-label="Existing demonstration boundary">
        <div className="placeholder-artifact">
          <span>Existing client-owned demonstration</span>
          <strong>{demo.material}</strong>
          <p>This region stands for the current demo UI. The prototype changes only the Waku shell and route orientation around it.</p>
        </div>
        <aside>
          <p className="prototype-kicker">Shell contract under test</p>
          <ul>
            <li>The current instrument remains named.</li>
            <li>All eight destinations stay reachable.</li>
            <li>Returning to the Hub is always explicit.</li>
            <li>The demo keeps visual and state authority inside this boundary.</li>
          </ul>
        </aside>
      </section>
      <footer className="demo-neighbors">
        <span>Continue in {demo.group.toLowerCase()}</span>
        <nav aria-label={`Other ${demo.group} demonstrations`}>
          {groupDemos.filter((candidate) => candidate.id !== demo.id).map((candidate) => (
            <a key={candidate.id} href={prototypeHref(variant, candidate.id)} onClick={(event) => visit(event, candidate.id)}>{candidate.title} →</a>
          ))}
        </nav>
      </footer>
    </article>
  );
}

interface DemoAnchorProps extends Pick<VariantProps, 'visit'> {
  readonly demo: DemoDefinition;
  readonly variant: VariantId;
  readonly mode: 'row' | 'stop';
}

function DemoAnchor({ demo, variant, visit, mode }: DemoAnchorProps) {
  return (
    <a className={`demo-anchor demo-anchor-${mode}`} href={prototypeHref(variant, demo.id)} onClick={(event) => visit(event, demo.id)}>
      <span className="demo-anchor-index">{demo.index}</span>
      <span className="demo-anchor-copy"><strong>{demo.title}</strong><small>{mode === 'row' ? demo.question : demo.material}</small></span>
      <span aria-hidden="true">→</span>
    </a>
  );
}

interface PrototypeSwitcherProps {
  readonly current: VariantId;
  readonly onChange: (variant: VariantId) => void;
}

function PrototypeSwitcher({ current, onChange }: PrototypeSwitcherProps) {
  const cycle = (offset: number) => {
    const index = VARIANTS.indexOf(current);
    onChange(VARIANTS[(index + offset + VARIANTS.length) % VARIANTS.length]);
  };
  return (
    <aside className="prototype-switcher" aria-label="Prototype variants">
      <button type="button" aria-label="Previous variant" onClick={() => cycle(-1)}>←</button>
      <div><span>THROWAWAY PROTOTYPE</span><strong>{current} — {VARIANT_NAMES[current]}</strong></div>
      <button type="button" aria-label="Next variant" onClick={() => cycle(1)}>→</button>
    </aside>
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
