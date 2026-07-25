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
  { id: 'editors', title: 'エディター' },
  { id: 'memory', title: '記録と振り返り' },
  { id: 'generated-change', title: '生成UIと変更提案' },
];

/** Add one entry here to include another demo in the Hub. */
export const DEMOS: readonly DemoDefinition[] = [
  {
    id: 'lambda',
    title: 'Mini-ML エディター',
    description: 'Mini-MLコードを編集し、AST、型エラー、評価結果を確認できます。',
    href: '/index.html',
    group: 'editors',
  },
  {
    id: 'json',
    title: 'JSON エディター',
    description: 'JSONをテキストまたはツリーとして編集し、変更履歴を確認できます。',
    href: '/json.html',
    group: 'editors',
  },
  {
    id: 'markdown',
    title: 'Markdown エディター',
    description: 'Markdownをブロック、ソース、プレビューの3つの表示で編集できます。',
    href: '/markdown.html',
    group: 'editors',
  },
  {
    id: 'memo',
    title: 'Canopy Memo',
    description: '文章の誤字修正や構造化編集を、適用前に確認できます。',
    href: '/memo.html',
    group: 'memory',
  },
  {
    id: 'posts',
    title: 'Posts',
    description: '短いメモを端末内に保存し、入力内容に関連する過去の投稿を探せます。',
    href: '/posts.html',
    group: 'memory',
  },
  {
    id: 'resume',
    title: 'Session Resume',
    description: 'エージェントの作業履歴を、時系列、会話、参照元に分けて確認できます。',
    href: '/resume.html',
    group: 'memory',
  },
  {
    id: 'genui',
    title: 'Generative UI',
    description: 'JSXを編集し、解析結果と生成されたUIを確認できます。',
    href: '/genui.html',
    group: 'generated-change',
  },
  {
    id: 'journey',
    title: '旅行プランの変更提案',
    description: '旅行プランの変更案を比較し、適用結果の確認と取り消しができます。',
    href: '/genui-possibilities.html',
    group: 'generated-change',
  },
];
