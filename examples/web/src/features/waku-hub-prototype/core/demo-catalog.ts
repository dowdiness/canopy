export type DemoGroupId = 'editors' | 'memory' | 'generated-change';

export interface DemoGroup {
  readonly id: DemoGroupId;
  readonly title: string;
  readonly description: string;
}

export interface DemoDefinition {
  readonly id: string;
  readonly title: string;
  readonly description: string;
  readonly href: string;
  readonly group: DemoGroupId;
}

export const DEMO_GROUPS: readonly DemoGroup[] = [
  {
    id: 'editors',
    title: 'Structured editors',
    description: 'Edit source while inspecting the structure Canopy maintains underneath.',
  },
  {
    id: 'memory',
    title: 'Memory and evidence',
    description: 'Bring earlier material back without losing chronology or provenance.',
  },
  {
    id: 'generated-change',
    title: 'Generated interfaces and changes',
    description: 'Inspect generated output and proposed changes before acting on them.',
  },
];

/** Add one entry here to include another demo in the Hub. */
export const DEMOS: readonly DemoDefinition[] = [
  {
    id: 'lambda',
    title: 'Mini-ML editor',
    description: 'Write a typed program and inspect its syntax tree, evaluation, and diagnostics.',
    href: '/index.html',
    group: 'editors',
  },
  {
    id: 'json',
    title: 'JSON editor',
    description: 'Edit JSON as text or a structural tree while retaining CRDT identity and edit history.',
    href: '/json.html',
    group: 'editors',
  },
  {
    id: 'markdown',
    title: 'Markdown editor',
    description: 'Move between block, source, and reading views without losing the document or selection.',
    href: '/markdown.html',
    group: 'editors',
  },
  {
    id: 'memo',
    title: 'Canopy Memo',
    description: 'Review typo corrections and structured edits against the note they would change.',
    href: '/memo.html',
    group: 'memory',
  },
  {
    id: 'posts',
    title: 'Posts',
    description: 'Capture thoughts locally and surface related older posts while preserving chronology.',
    href: '/posts.html',
    group: 'memory',
  },
  {
    id: 'resume',
    title: 'Session Resume',
    description: 'Inspect an agent session through its timeline, transcript, sources, and attached context.',
    href: '/resume.html',
    group: 'memory',
  },
  {
    id: 'genui',
    title: 'Generative UI',
    description: 'Inspect incrementally parsed JSX and evaluate recorded interface candidates with data.',
    href: '/genui.html',
    group: 'generated-change',
  },
  {
    id: 'journey',
    title: 'Journey responses',
    description: 'Compare proposed responses, preview their exact effect, then apply or undo deliberately.',
    href: '/genui-possibilities.html',
    group: 'generated-change',
  },
];
