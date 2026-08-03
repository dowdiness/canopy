import {
  moonbitBuildCoordinator,
  moonbitImportIds,
  moonbitModules,
} from '../../moonbit-artifacts.mjs';
import { moonbitPlugin } from '../../vite-plugin-moonbit';

export { moonbitImportIds };

/** Adapt the shared generated-artifact contract to a Vite environment. */
export function createMoonbitArtifactsPlugin({ watch }: { readonly watch: boolean }) {
  return moonbitPlugin({
    modules: moonbitModules.map((module) => ({ ...module })),
    coordinator: {
      ...moonbitBuildCoordinator,
      buildFlags: [...moonbitBuildCoordinator.buildFlags],
    },
    watch,
  });
}
