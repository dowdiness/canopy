export type DemoGroupId = 'editors' | 'memory' | 'generated-change';

export interface DemoGroup {
  readonly id: DemoGroupId;
  readonly title: string;
}

export interface DemoDefinition {
  readonly id: string;
  readonly title: string;
  readonly description: string;
  readonly href: string;
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
    href: '/index.html',
    group: 'editors',
  },
  {
    id: 'json',
    title: 'JSON Editor',
    description: 'Edit JSON as text or a tree and review the edit history.',
    href: '/json.html',
    group: 'editors',
  },
  {
    id: 'markdown',
    title: 'Markdown Editor',
    description: 'Edit Markdown in block, source, and preview views.',
    href: '/markdown.html',
    group: 'editors',
  },
  {
    id: 'memo',
    title: 'Canopy Memo',
    description: 'Review spelling corrections and structured edits before applying them.',
    href: '/memo.html',
    group: 'memory',
  },
  {
    id: 'posts',
    title: 'Posts',
    description: 'Save short notes locally and find earlier posts related to what you are writing.',
    href: '/posts.html',
    group: 'memory',
  },
  {
    id: 'resume',
    title: 'Session Resume',
    description: 'Review an agent session by timeline, conversation, and source.',
    href: '/resume.html',
    group: 'memory',
  },
  {
    id: 'genui',
    title: 'Generative UI',
    description: 'Edit JSX and inspect the parser output and generated interface.',
    href: '/genui.html',
    group: 'generated-change',
  },
  {
    id: 'journey',
    title: 'Journey Proposals',
    description: 'Compare changes to a travel plan, apply them, and undo them.',
    href: '/genui-possibilities.html',
    group: 'generated-change',
  },
];
