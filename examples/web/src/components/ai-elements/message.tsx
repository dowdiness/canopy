// Adapted from the AI Elements message registry component:
// https://registry.ai-sdk.dev/message.json
import type { UIMessage } from 'ai';
import { memo, type HTMLAttributes } from 'react';
import ReactMarkdown, { type Options as ReactMarkdownOptions } from 'react-markdown';
import remend from 'remend';
import remarkGfm from 'remark-gfm';

function classes(base: string, className: string | undefined): string {
  return className === undefined ? base : `${base} ${className}`;
}

export type MessageProps = HTMLAttributes<HTMLDivElement> & {
  readonly from: UIMessage['role'];
};

export function Message({ className, from, ...props }: MessageProps) {
  return (
    <article
      className={classes('ai-message', className)}
      data-role={from}
      {...props}
    />
  );
}

export type MessageContentProps = HTMLAttributes<HTMLDivElement>;

export function MessageContent({ className, ...props }: MessageContentProps) {
  return <div className={classes('ai-message-content', className)} {...props} />;
}

export type MessageResponseProps = Omit<ReactMarkdownOptions, 'children'> & {
  readonly children: string;
  readonly className?: string;
  readonly mode?: 'static' | 'streaming';
};

export const MessageResponse = memo(
  ({ children, className, mode = 'static', remarkPlugins, ...props }: MessageResponseProps) => (
    <div className={classes('ai-message-response', className)}>
      <ReactMarkdown
        remarkPlugins={[remarkGfm, ...(remarkPlugins ?? [])]}
        skipHtml
        {...props}
      >
        {mode === 'streaming' ? remend(children, { linkMode: 'text-only' }) : children}
      </ReactMarkdown>
    </div>
  ),
  (previous, next) => previous.children === next.children && previous.mode === next.mode,
);

MessageResponse.displayName = 'MessageResponse';
