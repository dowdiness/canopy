import type { LocalPost } from './post-store';

export interface RelatedPost {
  readonly post: LocalPost;
  readonly score: number;
  readonly matchedTerms: readonly string[];
}

export interface RetrievalOptions {
  readonly limit?: number;
}

interface TokenProfile {
  readonly uniqueTerms: ReadonlySet<string>;
  readonly counts: ReadonlyMap<string, number>;
  readonly totalTerms: number;
}

interface IndexedPost {
  readonly post: LocalPost;
  readonly profile: TokenProfile;
}

const DEFAULT_RELATED_LIMIT = 5;

// #593 intentionally starts with a tiny browser-local lexical scorer instead of
// wiring the experimental MoonBit `echo` package into Vite. Keeping the app on
// this module boundary lets `echo` replace the scorer once it has a production
// browser FFI surface.
const STOP_WORDS = new Set([
  'a',
  'about',
  'after',
  'also',
  'an',
  'and',
  'are',
  'as',
  'at',
  'be',
  'been',
  'before',
  'being',
  'by',
  'could',
  'for',
  'from',
  'had',
  'has',
  'have',
  'how',
  'i',
  'in',
  'into',
  'is',
  'it',
  'just',
  'me',
  'my',
  'no',
  'not',
  'note',
  'notes',
  'of',
  'on',
  'or',
  'our',
  'post',
  'posts',
  'remember',
  'should',
  'that',
  'the',
  'their',
  'them',
  'these',
  'they',
  'thing',
  'things',
  'this',
  'those',
  'to',
  'was',
  'we',
  'were',
  'what',
  'when',
  'where',
  'while',
  'who',
  'why',
  'will',
  'with',
  'would',
  'yes',
  'you',
  'your',
]);

export class PostRetrievalIndex {
  private readonly indexedPosts: readonly IndexedPost[];
  private readonly documentFrequency: ReadonlyMap<string, number>;

  constructor(posts: readonly LocalPost[]) {
    this.indexedPosts = posts
      .map(post => ({ post, profile: profileText(post.text) }))
      .filter(({ profile }) => profile.totalTerms > 0);
    this.documentFrequency = buildDocumentFrequency(this.indexedPosts);
  }

  query(draftText: string, options: RetrievalOptions = {}): RelatedPost[] {
    const limit = Math.max(0, options.limit ?? DEFAULT_RELATED_LIMIT);
    if (limit === 0 || this.indexedPosts.length === 0) return [];

    const query = profileText(draftText);
    if (query.totalTerms === 0) return [];

    return this.indexedPosts
      .map(indexedPost => this.scorePost(query, indexedPost))
      .filter((result): result is RelatedPost => result !== null)
      .sort(compareRelatedPosts)
      .slice(0, limit);
  }

  private scorePost(query: TokenProfile, indexedPost: IndexedPost): RelatedPost | null {
    const matchedTerms = Array.from(query.uniqueTerms).filter(term =>
      indexedPost.profile.uniqueTerms.has(term),
    );
    if (matchedTerms.length === 0) return null;

    const weightedOverlap = matchedTerms.reduce((score, term) => {
      const frequency = this.documentFrequency.get(term) ?? 0;
      const idf = Math.log(1 + this.indexedPosts.length / (1 + frequency));
      const termFrequency = indexedPost.profile.counts.get(term) ?? 1;
      return score + idf * (1 + Math.log(termFrequency));
    }, 0);
    const queryCoverage = matchedTerms.length / query.uniqueTerms.size;
    const lengthPenalty = Math.sqrt(indexedPost.profile.totalTerms);

    return {
      post: indexedPost.post,
      score: (weightedOverlap * (1 + queryCoverage)) / lengthPenalty,
      matchedTerms,
    };
  }
}

function profileText(text: string): TokenProfile {
  const counts = new Map<string, number>();

  for (const match of text.normalize('NFKC').toLowerCase().matchAll(/[\p{L}\p{N}]+/gu)) {
    const term = normalizeTerm(match[0]);
    if (term.length < 2 || STOP_WORDS.has(term)) continue;
    counts.set(term, (counts.get(term) ?? 0) + 1);
  }

  return {
    uniqueTerms: new Set(counts.keys()),
    counts,
    totalTerms: Array.from(counts.values()).reduce((sum, count) => sum + count, 0),
  };
}

function normalizeTerm(term: string): string {
  if (term.length > 5 && term.endsWith('ies')) return `${term.slice(0, -3)}y`;
  if (term.length > 5 && term.endsWith('ing')) return term.slice(0, -3);
  if (term.length > 4 && term.endsWith('ed')) return term.slice(0, -2);
  if (term.length > 4 && term.endsWith('s')) return term.slice(0, -1);
  return term;
}

function buildDocumentFrequency(posts: readonly IndexedPost[]): ReadonlyMap<string, number> {
  const frequency = new Map<string, number>();

  for (const { profile } of posts) {
    for (const term of profile.uniqueTerms) {
      frequency.set(term, (frequency.get(term) ?? 0) + 1);
    }
  }

  return frequency;
}

function compareRelatedPosts(a: RelatedPost, b: RelatedPost): number {
  const scoreDelta = b.score - a.score;
  if (Math.abs(scoreDelta) > Number.EPSILON) return scoreDelta;
  return Date.parse(b.post.createdAt) - Date.parse(a.post.createdAt);
}
