import {
  createPostEvent,
  engagementByPost,
  isLocalPostEvent,
  newestEventFirst,
  type LocalPostEvent,
  type LocalPostEventType,
  type PostEngagementSignals,
} from '../core/post-events';

export type { LocalPostEvent, LocalPostEventType, PostEngagementSignals } from '../core/post-events';

const POST_EVENT_STORAGE_KEY = 'canopy.post-events.v1';

function createEventId(now: Date): string {
  const time = now.getTime().toString(36);
  const random = Math.random().toString(36).slice(2, 10);
  return `post-event-${time}-${random}`;
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
    return this.append(createPostEvent(
      createEventId(now),
      'post_created',
      postId,
      now.toISOString(),
    ));
  }

  recordRelatedOpened(postId: string, now = new Date()): LocalPostEvent {
    return this.append(createPostEvent(
      createEventId(now),
      'related_opened',
      postId,
      now.toISOString(),
    ));
  }

  engagementByPost(): ReadonlyMap<string, PostEngagementSignals> {
    return engagementByPost(this.all());
  }

  private append(event: LocalPostEvent): LocalPostEvent {
    this.save([event, ...this.all()].sort(newestEventFirst));
    return event;
  }

  private save(events: LocalPostEvent[]): void {
    this.storage.setItem(this.key, JSON.stringify(events));
  }
}
