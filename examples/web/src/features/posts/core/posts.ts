export interface LocalPost {
  readonly id: string;
  readonly text: string;
  readonly createdAt: string;
}

export function isLocalPost(value: unknown): value is LocalPost {
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

export function newestPostFirst(a: LocalPost, b: LocalPost): number {
  return Date.parse(b.createdAt) - Date.parse(a.createdAt);
}

export function createPost(id: string, text: string, createdAt: string): LocalPost {
  return { id, text: text.trim(), createdAt };
}
