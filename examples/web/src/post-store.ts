export interface LocalPost {
  readonly id: string;
  readonly text: string;
  readonly createdAt: string;
}

const POST_STORAGE_KEY = 'canopy.posts.v1';

function isLocalPost(value: unknown): value is LocalPost {
  if (typeof value !== 'object' || value === null) return false;

  const record = value as Record<string, unknown>;
  return (
    typeof record.id === 'string' &&
    typeof record.text === 'string' &&
    record.text.trim().length > 0 &&
    typeof record.createdAt === 'string' &&
    !Number.isNaN(Date.parse(record.createdAt))
  );
}

function newestFirst(a: LocalPost, b: LocalPost): number {
  return Date.parse(b.createdAt) - Date.parse(a.createdAt);
}

function createId(now: Date): string {
  const time = now.getTime().toString(36);
  const random = Math.random().toString(36).slice(2, 10);
  return `post-${time}-${random}`;
}

function createPost(text: string, now = new Date()): LocalPost {
  return {
    id: createId(now),
    text: text.trim(),
    createdAt: now.toISOString(),
  };
}

export class LocalPostStore {
  constructor(
    private readonly storage: Storage,
    private readonly key = POST_STORAGE_KEY,
  ) {}

  all(): LocalPost[] {
    try {
      const raw = this.storage.getItem(this.key);
      if (raw === null) return [];

      const parsed: unknown = JSON.parse(raw);
      if (!Array.isArray(parsed)) return [];

      return parsed.filter(isLocalPost).sort(newestFirst);
    } catch {
      return [];
    }
  }

  add(text: string, now = new Date()): LocalPost {
    const post = createPost(text, now);
    this.save([post, ...this.all()].sort(newestFirst));
    return post;
  }

  private save(posts: LocalPost[]): void {
    this.storage.setItem(this.key, JSON.stringify(posts));
  }
}
