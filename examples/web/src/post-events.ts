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

const POST_EVENT_STORAGE_KEY = 'canopy.post-events.v1';

function isLocalPostEvent(value: unknown): value is LocalPostEvent {
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

function newestEventFirst(a: LocalPostEvent, b: LocalPostEvent): number {
  return Date.parse(b.createdAt) - Date.parse(a.createdAt);
}

function createEventId(now: Date): string {
  const time = now.getTime().toString(36);
  const random = Math.random().toString(36).slice(2, 10);
  return `post-event-${time}-${random}`;
}

function createEvent(type: LocalPostEventType, postId: string, now: Date): LocalPostEvent {
  return {
    id: createEventId(now),
    type,
    postId,
    createdAt: now.toISOString(),
  };
}

export class LocalPostEventStore {
  constructor(
    private readonly storage: Storage,
    private readonly key = POST_EVENT_STORAGE_KEY,
  ) {}

  all(): LocalPostEvent[] {
    try {
      const raw = this.storage.getItem(this.key);
      if (raw === null) return [];

      const parsed: unknown = JSON.parse(raw);
      if (!Array.isArray(parsed)) return [];

      return parsed.filter(isLocalPostEvent).sort(newestEventFirst);
    } catch {
      return [];
    }
  }

  recordPostCreated(postId: string, now = new Date()): LocalPostEvent {
    return this.append(createEvent('post_created', postId, now));
  }

  recordRelatedOpened(postId: string, now = new Date()): LocalPostEvent {
    return this.append(createEvent('related_opened', postId, now));
  }

  engagementByPost(): ReadonlyMap<string, PostEngagementSignals> {
    const summaries = new Map<string, PostEngagementSignals>();

    for (const event of this.all()) {
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

  private append(event: LocalPostEvent): LocalPostEvent {
    this.save([event, ...this.all()].sort(newestEventFirst));
    return event;
  }

  private save(events: LocalPostEvent[]): void {
    this.storage.setItem(this.key, JSON.stringify(events));
  }
}
