// Editor adapter library — re-exports all public types and implementations.

export type {
  ViewNode,
  ViewPatch,
  UserIntent,
  Decoration,
  Diagnostic,
} from './types';

export type { EditorAdapter } from './adapter';

export { HTMLAdapter } from './html-adapter';
export { CM6Adapter } from './cm6-adapter';
export { PMAdapter, pmAdapterSchema } from './pm-adapter';
export { MarkdownPreview } from './markdown-preview';
export { BlockInput } from './block-input';
