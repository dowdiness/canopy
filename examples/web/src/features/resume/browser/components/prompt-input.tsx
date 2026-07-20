// Adapted from the AI Elements prompt-input registry component:
// https://registry.ai-sdk.dev/prompt-input.json
import type { ChatStatus } from 'ai';
import type { ComponentProps } from 'react';

function classes(base: string, className: string | undefined): string {
  return className === undefined ? base : `${base} ${className}`;
}

export type PromptInputProps = ComponentProps<'form'>;

export function PromptInput({ className, ...props }: PromptInputProps) {
  return <form className={classes('ai-prompt-input', className)} {...props} />;
}

export type PromptInputBodyProps = ComponentProps<'div'>;

export function PromptInputBody({ className, ...props }: PromptInputBodyProps) {
  return <div className={classes('ai-prompt-input-body', className)} {...props} />;
}

export type PromptInputTextareaProps = ComponentProps<'textarea'>;

export function PromptInputTextarea({ className, ...props }: PromptInputTextareaProps) {
  return (
    <textarea
      className={classes('ai-prompt-input-textarea', className)}
      rows={3}
      {...props}
    />
  );
}

export type PromptInputFooterProps = ComponentProps<'footer'>;

export function PromptInputFooter({ className, ...props }: PromptInputFooterProps) {
  return <footer className={classes('ai-prompt-input-footer', className)} {...props} />;
}

export type PromptInputSubmitProps = ComponentProps<'button'> & {
  readonly status?: ChatStatus;
};

export function PromptInputSubmit({
  className,
  status = 'ready',
  children,
  ...props
}: PromptInputSubmitProps) {
  const label = status === 'submitted' || status === 'streaming' ? 'Stop' : 'Send';
  return (
    <button
      className={classes('ai-prompt-input-submit', className)}
      type="submit"
      {...props}
    >
      {children ?? label}
    </button>
  );
}
