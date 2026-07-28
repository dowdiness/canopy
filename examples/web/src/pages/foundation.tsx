import { MoonbitClientProbe } from '../shared/browser/moonbit-client-probe';
import { LifecycleLink } from '../shared/route-lifecycle/browser/lifecycle-link';

export default function WakuFoundationPage() {
  return (
    <main className="route-state">
      <h1 tabIndex={-1} data-route-heading>Canopy Waku foundation</h1>
      <p>This diagnostic route verifies the generated client artifact boundary.</p>
      <LifecycleLink
        className="route-state__action"
        to={'/json.html?source=client&flag&note=a%20b#legacy-focus' as never}
      >
        Open the legacy JSON route
      </LifecycleLink>
      <MoonbitClientProbe />
    </main>
  );
}
