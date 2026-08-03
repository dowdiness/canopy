import { createPost, isLocalPost, newestPostFirst, type LocalPost } from '../core/posts';

export type { LocalPost } from '../core/posts';

const POST_STORAGE_KEY = 'canopy.posts.v1';

function createId(now: Date): string {
  const time = now.getTime().toString(36);
  const random = Math.random().toString(36).slice(2, 10);
  return `post-${time}-${random}`;
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

      return parsed.filter(isLocalPost).sort(newestPostFirst);
    } catch {
      return [];
    }
  }

  add(text: string, now = new Date()): LocalPost {
    const post = createPost(createId(now), text, now.toISOString());
    this.save([post, ...this.all()].sort(newestPostFirst));
    return post;
  }

  private save(posts: LocalPost[]): void {
    this.storage.setItem(this.key, JSON.stringify(posts));
  }
}
