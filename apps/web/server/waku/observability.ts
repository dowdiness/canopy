import type {
  WorkerCapability,
  WorkerRouteClass,
} from './request-policy.ts';

export type WorkerErrorCategory =
  | 'none'
  | 'asset-unavailable'
  | 'signaling-unavailable'
  | 'waku-unhandled';

export type WorkerTelemetryRecord = Readonly<{
  event: 'canopy.worker.request';
  deploymentVersion: string;
  routeClass: WorkerRouteClass;
  capability: WorkerCapability;
  status: number;
  errorCategory: WorkerErrorCategory;
}>;

export type WorkerTelemetryInput = Readonly<{
  deploymentVersion?: string;
  routeClass: WorkerRouteClass;
  capability: WorkerCapability;
  status: number;
  errorCategory: WorkerErrorCategory;
}>;

export function createWorkerTelemetryRecord(
  input: WorkerTelemetryInput,
): WorkerTelemetryRecord {
  return Object.freeze({
    event: 'canopy.worker.request' as const,
    deploymentVersion: input.deploymentVersion?.trim() || 'local',
    routeClass: input.routeClass,
    capability: input.capability,
    status: input.status,
    errorCategory: input.errorCategory,
  });
}
