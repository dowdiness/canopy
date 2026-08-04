/// <reference types="vite/client" />

interface ImportMeta {
  readonly env: ImportMetaEnv
}

declare module '*.jsonl?raw' {
  const content: string;
  export default content;
}
