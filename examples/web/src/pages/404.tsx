export default function NotFoundPage() {
  return (
    <main className="route-state" aria-labelledby="not-found-heading">
      <p className="route-state__label">404</p>
      <h1 id="not-found-heading" tabIndex={-1} data-route-heading>Demo not found</h1>
      <p>The requested page is not part of the Canopy demo catalog.</p>
      <a className="route-state__action" href="/">Back to demos</a>
    </main>
  );
}
