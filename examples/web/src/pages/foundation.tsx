import { MoonbitClientProbe } from '../shared/browser/moonbit-client-probe';

export default function WakuFoundationPage() {
  return (
    <main className="route-state">
      <h1 tabIndex={-1} data-route-heading>Canopy Waku foundation</h1>
      <p>This pre-production route verifies the generated client artifact boundary.</p>
      <MoonbitClientProbe />
    </main>
  );
}
