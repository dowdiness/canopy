export interface MoonBitArtifactModule {
  readonly name: string;
  readonly path: string;
  readonly output: string;
}

export const moonbitModules: readonly MoonBitArtifactModule[];
export const moonbitImportIds: readonly string[];
export const moonbitBuildCoordinator: {
  readonly path: string;
  readonly buildFlags: readonly string[];
};
