import { LifecycleLink } from '../../../shared/route-lifecycle/browser/lifecycle-link';

const MEMO_SHELL_PATTERN = /<!-- memo-shell:start -->([\s\S]*?)<!-- memo-shell:end -->/;

export async function MemoRoute() {
  if (import.meta.env.PROD) {
    return (
      <main className="route-state" data-memo-production-unavailable>
        <p className="route-state__label">Local-only demo</p>
        <h1 tabIndex={-1} data-route-heading>Canopy Memo</h1>
        <p>
          This demo is available only in local development because it sends
          provider requests directly from the browser. Production requires a
          server-side provider proxy.
        </p>
        <LifecycleLink className="route-state__action" to="/">
          Back to demos
        </LifecycleLink>
      </main>
    );
  }

  const [
    { default: memoDocument },
    { MemoClient },
  ] = await Promise.all([
    import('../../../../memo.html?raw'),
    import('./memo-client'),
  ]);
  const shellMatch = MEMO_SHELL_PATTERN.exec(memoDocument);
  if (shellMatch === null) {
    throw new Error('The canonical Memo document shell is unavailable');
  }
  return (
    <MemoClient>
      <div dangerouslySetInnerHTML={{ __html: shellMatch[1] }} />
    </MemoClient>
  );
}
