import { DEMOS, type DemoId } from '../catalog/demo-catalog';
import { LifecycleLink } from '../route-lifecycle/browser/lifecycle-link';

export function DemoPlaceholder({ demoId }: { readonly demoId: DemoId }) {
  const demo = DEMOS.find((candidate) => candidate.id === demoId);
  if (demo === undefined) throw new Error(`Unknown demo catalog entry: ${demoId}`);

  return (
    <main className="route-state" data-demo-placeholder={demo.id}>
      <p className="route-state__label">Migration pending</p>
      <h1 tabIndex={-1} data-route-heading>{demo.title}</h1>
      <p>This demo still runs in the parallel Vite application during Stage 2.</p>
      <LifecycleLink className="route-state__action" to="/">Back to demos</LifecycleLink>
    </main>
  );
}
