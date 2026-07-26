export type DemoId =
  | 'lambda'
  | 'json'
  | 'markdown'
  | 'memo'
  | 'posts'
  | 'resume'
  | 'genui'
  | 'journey';

export type DemoPath =
  | '/ml'
  | '/json'
  | '/markdown'
  | '/memo'
  | '/posts'
  | '/resume'
  | '/genui'
  | '/journey';

export type DemoGroupId = 'editors' | 'memory' | 'generated-change';

export interface DemoGroup {
  readonly id: DemoGroupId;
  readonly title: string;
}

export interface DemoDefinition {
  readonly id: DemoId;
  readonly title: string;
  readonly description: string;
  readonly href: DemoPath;
  readonly group: DemoGroupId;
}

export const DEMO_GROUPS: readonly DemoGroup[] = [
  { id: 'editors', title: 'Editors' },
  { id: 'memory', title: 'Notes and history' },
  { id: 'generated-change', title: 'Generated UI and proposals' },
];

/** Add one entry here to include another demo in the Hub. */
export const DEMOS: readonly DemoDefinition[] = [
  {
    id: 'lambda',
    title: 'Mini-ML Editor',
    description: 'Edit Mini-ML code and inspect its AST, type errors, and evaluation results.',
    href: '/ml',
    group: 'editors',
  },
  {
    id: 'json',
    title: 'JSON Editor',
    description: 'Edit JSON as text or a tree and review the edit history.',
    href: '/json',
    group: 'editors',
  },
  {
    id: 'markdown',
    title: 'Markdown Editor',
    description: 'Edit Markdown in block, source, and preview views.',
    href: '/markdown',
    group: 'editors',
  },
  {
    id: 'memo',
    title: 'Canopy Memo',
    description: 'Review spelling corrections and structured edits before applying them.',
    href: '/memo',
    group: 'memory',
  },
  {
    id: 'posts',
    title: 'Posts',
    description: 'Save short notes locally and find earlier posts related to what you are writing.',
    href: '/posts',
    group: 'memory',
  },
  {
    id: 'resume',
    title: 'Session Resume',
    description: 'Review an agent session by timeline, conversation, and source.',
    href: '/resume',
    group: 'memory',
  },
  {
    id: 'genui',
    title: 'Generative UI',
    description: 'Edit JSX and inspect the parser output and generated interface.',
    href: '/genui',
    group: 'generated-change',
  },
  {
    id: 'journey',
    title: 'Journey Proposals',
    description: 'Compare changes to a travel plan, apply them, and undo them.',
    href: '/journey',
    group: 'generated-change',
  },
];

export function demoIdForPath(path: string): DemoId | null {
  return DEMOS.find((demo) => demo.href === path)?.id ?? null;
}
