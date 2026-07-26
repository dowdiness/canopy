import markdownDocument from '../../../../markdown.html?raw';
import { MarkdownClient } from './markdown-client';

const MARKDOWN_SHELL_PATTERN = /<!-- markdown-shell:start -->([\s\S]*?)<!-- markdown-shell:end -->/;

export function MarkdownRoute() {
  const shellMatch = MARKDOWN_SHELL_PATTERN.exec(markdownDocument);
  if (shellMatch === null) {
    throw new Error('The canonical Markdown document shell is unavailable');
  }

  return (
    <MarkdownClient>
      <div dangerouslySetInnerHTML={{ __html: shellMatch[1] }} />
    </MarkdownClient>
  );
}
