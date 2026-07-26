interface RecoveryRouter {
  back(): void;
}

export function recoverPreCommitNavigation(
  router: RecoveryRouter,
  rememberFailure: () => void,
): void {
  rememberFailure();
  router.back();
}
