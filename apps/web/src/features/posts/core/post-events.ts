export type LocalPostEventType = 'post_created' | 'related_opened';

export interface LocalPostEvent {
  readonly id: string;
  readonly type: LocalPostEventType;
  readonly postId: string;
  readonly createdAt: string;
}

export interface PostEngagementSignals {
  readonly relatedOpenCount: number;
  readonly lastRelatedOpenedAt?: string;
}

export function isLocalPostEvent(value: unknown): value is LocalPostEvent {
  if (typeof value !== 'object' || value === null) return false;

  const record = value as Record<string, unknown>;
  const type = record.type;
  return (
    typeof record.id === 'string' &&
    (type === 'post_created' || type === 'related_opened') &&
    typeof record.postId === 'string' &&
    record.postId.length > 0 &&
    typeof record.createdAt === 'string' &&
    !Number.isNaN(Date.parse(record.createdAt))
  );
}

export function newestEventFirst(a: LocalPostEvent, b: LocalPostEvent): number {
  return Date.parse(b.createdAt) - Date.parse(a.createdAt);
}

export function createPostEvent(
  id: string,
  type: LocalPostEventType,
  postId: string,
  createdAt: string,
): LocalPostEvent {
  return { id, type, postId, createdAt };
}

export function engagementByPost(
  events: readonly LocalPostEvent[],
): ReadonlyMap<string, PostEngagementSignals> {
  const summaries = new Map<string, PostEngagementSignals>();

  for (const event of events) {
    if (event.type !== 'related_opened') continue;

    const current = summaries.get(event.postId);
    const currentLastOpened = current?.lastRelatedOpenedAt;
    const eventTime = Date.parse(event.createdAt);
    const currentLastOpenedTime =
      currentLastOpened === undefined ? Number.NEGATIVE_INFINITY : Date.parse(currentLastOpened);
    const nextLastOpened =
      currentLastOpened === undefined || eventTime > currentLastOpenedTime
        ? event.createdAt
        : currentLastOpened;

    summaries.set(event.postId, {
      relatedOpenCount: (current?.relatedOpenCount ?? 0) + 1,
      lastRelatedOpenedAt: nextLastOpened,
    });
  }

  return summaries;
}
