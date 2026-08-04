// Adapted from the AI Elements sources registry component:
// https://registry.ai-sdk.dev/sources.json
import type { ComponentProps } from 'react';

function classes(base: string, className: string | undefined): string {
  return className === undefined ? base : `${base} ${className}`;
}

export type SourcesProps = ComponentProps<'details'>;

export function Sources({ className, ...props }: SourcesProps) {
  return <details className={classes('ai-sources', className)} {...props} />;
}

export type SourcesTriggerProps = ComponentProps<'summary'> & {
  readonly count: number;
};

export function SourcesTrigger({
  className,
  count,
  children,
  ...props
}: SourcesTriggerProps) {
  return (
    <summary className={classes('ai-sources-trigger', className)} {...props}>
      {children ?? `${count} exact source${count === 1 ? '' : 's'}`}
    </summary>
  );
}

export type SourcesContentProps = ComponentProps<'div'>;

export function SourcesContent({ className, ...props }: SourcesContentProps) {
  return <div className={classes('ai-sources-content', className)} {...props} />;
}

export type SourceProps = ComponentProps<'button'>;

export function Source({ className, type = 'button', ...props }: SourceProps) {
  return (
    <button
      className={classes('ai-source', className)}
      type={type}
      {...props}
    />
  );
}
