// Adapted from the AI Elements conversation registry component:
// https://registry.ai-sdk.dev/conversation.json
import type { ComponentProps } from 'react';
import { useCallback } from 'react';
import { StickToBottom, useStickToBottomContext } from 'use-stick-to-bottom';

function classes(base: string, className: string | undefined): string {
  return className === undefined ? base : `${base} ${className}`;
}

export type ConversationProps = ComponentProps<typeof StickToBottom>;

export function Conversation({ className, ...props }: ConversationProps) {
  return (
    <StickToBottom
      className={classes('ai-conversation', className)}
      initial="smooth"
      resize="smooth"
      role="log"
      {...props}
    />
  );
}

export type ConversationContentProps = ComponentProps<typeof StickToBottom.Content>;

export function ConversationContent({ className, ...props }: ConversationContentProps) {
  return (
    <StickToBottom.Content
      className={classes('ai-conversation-content', className)}
      {...props}
    />
  );
}

export type ConversationEmptyStateProps = ComponentProps<'div'> & {
  readonly title?: string;
};

export function ConversationEmptyState({
  className,
  title = 'No messages yet',
  ...props
}: ConversationEmptyStateProps) {
  return (
    <div className={classes('ai-conversation-empty', className)} {...props}>
      {title}
    </div>
  );
}

export type ConversationScrollButtonProps = ComponentProps<'button'>;

export function ConversationScrollButton({
  className,
  children = 'Jump to latest',
  ...props
}: ConversationScrollButtonProps) {
  const { isAtBottom, scrollToBottom } = useStickToBottomContext();
  const handleClick = useCallback(() => scrollToBottom(), [scrollToBottom]);
  if (isAtBottom) return null;
  return (
    <button
      className={classes('ai-conversation-scroll', className)}
      type="button"
      onClick={handleClick}
      {...props}
    >
      {children}
    </button>
  );
}
