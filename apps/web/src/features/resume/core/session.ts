export const DEFAULT_LIMITS = {
  maxFileBytes: 32 * 1024 * 1024,
  maxLineBytes: 8 * 1024 * 1024,
  maxEntries: 5_000,
  maxAncestryDepth: 5_000,
  maxExcerptChars: 360,
} as const;

export const PKE_SENSITIVE_POLICY_VERSION = 'pke-sensitive-v1';

export type SensitivePolicyReason =
  | 'private-key-header'
  | 'known-token-prefix'
  | 'credential-header'
  | 'credential-assignment'
  | 'credential-url'
  | 'email-address'
  | 'long-encoded-value';

export type BashClassification = 'build' | 'test' | 'lint' | 'git' | 'other';

export type DiagnosticSeverity = 'error' | 'warning';

export interface ResumeDiagnostic {
  readonly severity: DiagnosticSeverity;
  readonly code: string;
  readonly message: string;
  readonly entryId?: string;
}

export interface SessionHeader {
  readonly sessionId: string;
  readonly version: 3;
  readonly timestamp: string;
  readonly cwd: string;
  readonly parentSession?: string;
}

export interface SourceReference {
  readonly sessionId: string;
  readonly entryId: string;
  readonly fragmentIds?: readonly string[];
}

export type EpistemicOrigin =
  | { readonly kind: 'recorded-human' }
  | { readonly kind: 'human-accepted-source' }
  | {
      readonly kind: 'observed-tool';
      readonly outcome: 'success' | 'failure';
      readonly toolCallId?: string;
    }
  | { readonly kind: 'assistant-claim' }
  | { readonly kind: 'person-authored' }
  | { readonly kind: 'canopy-system' };

export type Derivation =
  | { readonly kind: 'recorded' }
  | {
      readonly kind: 'deterministic';
      readonly ruleId: string;
      readonly ruleVersion: string;
    }
  | {
      readonly kind: 'model-inference';
      readonly modelIdentity: string;
      readonly analysisVersion: string;
    };

export interface PersonAuthoredRevision {
  readonly text: string;
  readonly origin: { readonly kind: 'person-authored' };
  readonly derivation: { readonly kind: 'recorded' };
}

export type ReviewState =
  | { readonly kind: 'unreviewed' }
  | { readonly kind: 'accepted' }
  | { readonly kind: 'corrected'; readonly replacement: PersonAuthoredRevision }
  | { readonly kind: 'dismissed' };

export interface ThinkingItem {
  readonly id: string;
  readonly text?: string;
  readonly origin: EpistemicOrigin;
  readonly derivation: Derivation;
  readonly review: ReviewState;
  readonly sources: readonly SourceReference[];
}

export type ThinkingItemReviewEvent =
  | { readonly kind: 'accept' }
  | { readonly kind: 'correct'; readonly text: string }
  | { readonly kind: 'dismiss' }
  | { readonly kind: 'reset' };

export type AnchorKind = 'goal' | 'decision' | 'question' | 'next-step';

type SafeExcerpt = string | undefined;

interface EntryBase {
  readonly id: string;
  readonly parentId: string | null;
  readonly timestamp: string;
  readonly source: SourceReference;
}

export interface NormalizedToolCall {
  readonly id: string;
  readonly name: string;
  readonly path?: string;
  readonly editCount?: number;
  readonly bashClassification?: BashClassification;
  readonly bashLabel?: SafeExcerpt;
}

export interface CompactionPaths {
  readonly readFiles: readonly string[];
  readonly modifiedFiles: readonly string[];
}

export type NormalizedEntry =
  | (EntryBase & {
      readonly kind: 'message';
      readonly role: 'user' | 'assistant' | 'toolResult';
      readonly text?: SafeExcerpt;
      readonly toolCallId?: string;
      readonly toolName?: string;
      readonly toolCalls: readonly NormalizedToolCall[];
      readonly isError?: boolean;
      readonly outcome?: 'success' | 'failure';
      readonly automaticOutputAllowed?: boolean;
    })
  | (EntryBase & {
      readonly kind: 'bashExecution';
      readonly commandLabel?: SafeExcerpt;
      readonly classification: BashClassification;
      readonly output?: SafeExcerpt;
      readonly automaticOutputAllowed: boolean;
      readonly exitCode?: number;
      readonly cancelled: boolean;
    })
  | (EntryBase & {
      readonly kind: 'compaction';
      readonly summary?: SafeExcerpt;
      readonly details?: CompactionPaths;
      readonly firstKeptEntryId?: string;
    })
  | (EntryBase & {
      readonly kind: 'branchSummary';
      readonly summary?: SafeExcerpt;
      readonly fromId?: string;
    })
  | (EntryBase & {
      readonly kind: 'checkpoint';
      readonly anchorKind: AnchorKind;
      readonly text: string;
      readonly accepted: true;
    })
  | (EntryBase & {
      readonly kind: 'omitted';
      readonly originalType: string;
      readonly reason: string;
    });

export interface DecodedPiSession {
  readonly header: SessionHeader;
  readonly entries: readonly NormalizedEntry[];
  readonly diagnostics: readonly ResumeDiagnostic[];
}

export interface TerminalPath {
  readonly leafId: string;
  readonly entryIds: readonly string[];
}

export interface ReducedPiSession {
  readonly header: SessionHeader;
  readonly entries: readonly NormalizedEntry[];
  readonly terminalPaths: readonly TerminalPath[];
  readonly diagnostics: readonly ResumeDiagnostic[];
}

export type ActivityKind =
  | 'human'
  | 'assistant-claim'
  | 'tool-evidence'
  | 'compaction'
  | 'branch-summary'
  | 'checkpoint'
  | 'omitted';

export interface ActivityItem extends ThinkingItem {
  readonly id: string;
  readonly kind: ActivityKind;
  readonly title: string;
  readonly timestamp: string;
  readonly text?: string;
  readonly source: SourceReference;
  readonly evidenceStatus?: 'observed' | 'observed-failure' | 'claim';
  readonly anchorKind?: AnchorKind;
  readonly accepted?: true;
}

export interface ExtractiveResumeOverview {
  /** Accepted goal when present; otherwise the latest explicit user direction. */
  readonly activeTask?: ActivityItem;
  /** Latest successful tool observation. */
  readonly latestOutcome?: ActivityItem;
  /** Accepted open question when present; otherwise the latest observed failure. */
  readonly attention?: ActivityItem;
  /** Accepted next-step checkpoint only; never inferred from assistant prose. */
  readonly nextAction?: ActivityItem;
  readonly landmarks: readonly ActivityItem[];
}

export interface ResumeProjection {
  readonly sessionId: string;
  readonly leafId: string;
  readonly path: readonly string[];
  readonly chronology: readonly ActivityItem[];
  readonly anchors: readonly ActivityItem[];
  readonly claims: readonly ActivityItem[];
  readonly evidence: readonly ActivityItem[];
  /** The first human-authored intent, shown as context rather than an accepted checkpoint. */
  readonly observedIntent?: ActivityItem;
  /** The latest bounded tool observation, shown as evidence rather than a conclusion. */
  readonly latestEvidence?: ActivityItem;
  readonly goal?: ActivityItem;
  readonly decision?: ActivityItem;
  readonly question?: ActivityItem;
  readonly nextStep?: ActivityItem;
  readonly overview: ExtractiveResumeOverview;
  readonly diagnostics: readonly ResumeDiagnostic[];
}

export function activityTextForDisplay(item: ActivityItem): string {
  if (item.text !== undefined) return item.text;
  switch (item.kind) {
    case 'human':
      return 'No human-authored text was recorded for this event.';
    case 'assistant-claim':
      return 'No assistant prose was recorded for this event.';
    case 'tool-evidence':
      return 'Tool output is unavailable in the normalized record.';
    case 'compaction':
      return 'No conversation summary text was recorded.';
    case 'branch-summary':
      return 'No branch summary text was recorded.';
    case 'checkpoint':
      return 'No checkpoint text was recorded.';
    case 'omitted':
      return 'Entry content is unavailable in the normalized record.';
  }
}

interface RawRecord {
  readonly [key: string]: unknown;
}

export class PiSessionFormatError extends Error {
  readonly code: string;

  constructor(code: string, message: string) {
    super(message);
    this.name = 'PiSessionFormatError';
    this.code = code;
  }
}

export function createThinkingItem<T extends ThinkingItem>(item: T): T {
  if (item.id.trim().length === 0) {
    throw new PiSessionFormatError('invalid_thinking_item_id', 'A thinking item needs a stable identity.');
  }
  if (item.sources.length === 0) {
    throw new PiSessionFormatError('missing_thinking_item_source', 'A thinking item needs at least one source.');
  }

  const sources = Object.freeze(item.sources.map(freezeSourceReference));
  const sourceIdentities = sources.map(stableSerialize);
  if (new Set(sourceIdentities).size !== sourceIdentities.length) {
    throw new PiSessionFormatError('duplicate_thinking_item_source', 'Thinking item sources must be unique.');
  }
  if (item.derivation.kind === 'model-inference') {
    throw new PiSessionFormatError(
      'model_inference_not_authorized',
      'Model-inferred thinking items are not authorized in this slice.',
    );
  }
  assertEpistemicCombination(item.origin, item.derivation);

  const origin = Object.freeze({ ...item.origin });
  const derivation = Object.freeze({ ...item.derivation });
  const review = freezeReviewState(item.review);
  return Object.freeze({ ...item, origin, derivation, review, sources });
}

export function reduceThinkingItemReview<T extends ThinkingItem>(
  item: T,
  event: ThinkingItemReviewEvent,
): T;
export function reduceThinkingItemReview(
  item: ThinkingItem,
  event: ThinkingItemReviewEvent,
): ThinkingItem {
  const review: ReviewState = (() => {
    switch (event.kind) {
      case 'accept':
        return { kind: 'accepted' };
      case 'correct':
        if (event.text.trim().length === 0) {
          throw new PiSessionFormatError(
            'invalid_person_authored_revision',
            'A person-authored correction cannot be empty.',
          );
        }
        return {
          kind: 'corrected',
          replacement: {
            text: event.text,
            origin: { kind: 'person-authored' },
            derivation: { kind: 'recorded' },
          },
        };
      case 'dismiss':
        return { kind: 'dismissed' };
      case 'reset':
        return { kind: 'unreviewed' };
    }
  })();

  const validatedItem = createThinkingItem(item);
  if (stableSerialize(validatedItem.review) === stableSerialize(review)) return validatedItem;
  return createThinkingItem({ ...validatedItem, review });
}

function freezeSourceReference(source: SourceReference): SourceReference {
  if (source.sessionId.trim().length === 0 || source.entryId.trim().length === 0) {
    throw new PiSessionFormatError(
      'invalid_thinking_item_source',
      'Thinking item sources need session and entry identities.',
    );
  }
  const fragmentIds = source.fragmentIds === undefined
    ? undefined
    : Object.freeze([...source.fragmentIds]);
  if (
    fragmentIds !== undefined &&
    (fragmentIds.some(fragmentId => fragmentId.trim().length === 0) ||
      new Set(fragmentIds).size !== fragmentIds.length)
  ) {
    throw new PiSessionFormatError(
      'invalid_thinking_item_fragments',
      'Thinking item fragment identities must be non-empty and unique.',
    );
  }
  return Object.freeze({
    sessionId: source.sessionId,
    entryId: source.entryId,
    ...(fragmentIds === undefined ? {} : { fragmentIds }),
  });
}

function assertEpistemicCombination(origin: EpistemicOrigin, derivation: Derivation): void {
  const systemDerived = derivation.kind === 'deterministic' || derivation.kind === 'model-inference';
  if ((origin.kind === 'canopy-system') !== systemDerived) {
    throw new PiSessionFormatError(
      'invalid_epistemic_combination',
      'Recorded origins use recorded derivation; system output names its deterministic or model derivation.',
    );
  }
}

function freezeReviewState(review: ReviewState): ReviewState {
  if (review.kind !== 'corrected') return Object.freeze({ ...review });
  if (review.replacement.text.trim().length === 0) {
    throw new PiSessionFormatError(
      'invalid_person_authored_revision',
      'A person-authored correction cannot be empty.',
    );
  }
  return Object.freeze({
    kind: 'corrected',
    replacement: Object.freeze({
      text: review.replacement.text,
      origin: Object.freeze({ kind: 'person-authored' }),
      derivation: Object.freeze({ kind: 'recorded' }),
    }),
  });
}

const SENSITIVE_PATTERNS: readonly (readonly [SensitivePolicyReason, RegExp])[] = [
  ['private-key-header', /-----BEGIN [A-Z ]*PRIVATE KEY-----/i],
  ['known-token-prefix', /(?:^|\s)(?:(?:sk|rk|ghp|github_pat|xox[baprs])[-_][A-Za-z0-9_-]{8,}|AKIA[0-9A-Z]{12,})/],
  ['credential-header', /\bauthorization\s*:\s*\S+/i],
  ['credential-header', /\b(?:bearer|basic)\s+[A-Za-z0-9+/_=-]{12,}/i],
  ['credential-assignment', /\b(?:password|passwd|secret|api[_ -]?key|access[_ -]?token)\s*[:=]/i],
  ['credential-url', /\b[a-z][a-z0-9+.-]*:\/\/[^/\s:@]+:[^/\s@]+@/i],
  ['credential-url', /[?&](?:access_token|api_key|token|secret|password)=/i],
  ['email-address', /\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b/i],
  ['long-encoded-value', /\b[0-9a-f]{32,}\b/i],
  ['long-encoded-value', /\b[A-Za-z0-9+/_=-]{32,}\b/],
];

export function sensitivePolicyReasons(value: string): readonly SensitivePolicyReason[] {
  return [...new Set(SENSITIVE_PATTERNS.filter(([, pattern]) => pattern.test(value)).map(([reason]) => reason))];
}

export function isSensitiveText(value: string): boolean {
  return sensitivePolicyReasons(value).length > 0;
}

const ANCHOR_KINDS = new Set<AnchorKind>(['goal', 'decision', 'question', 'next-step']);
const AUTOMATIC_TOOL_RESULT_NAMES = new Set(['read', 'edit', 'test', 'bash', 'write']);
const ALLOWED_TOOL_PATH_NAMES = new Set(['read', 'edit', 'write']);
const ALLOWED_COMMAND_PREFIXES = new Set(['moon', 'npm', 'node', 'git']);

export function parsePiSessionJsonl(
  input: string,
  limits: typeof DEFAULT_LIMITS = DEFAULT_LIMITS,
): DecodedPiSession {
  assertByteLimit(input, limits.maxFileBytes, 'file_too_large', 'Session file');
  if (input.length === 0) {
    throw new PiSessionFormatError('empty_file', 'The session file is empty.');
  }

  const lines = input.split(/\r?\n/);
  if (lines[lines.length - 1] === '') lines.pop();
  if (lines.length === 0) {
    throw new PiSessionFormatError('empty_file', 'The session file is empty.');
  }

  const records = lines.map((line, index) => {
    if (line.trim().length === 0) {
      throw new PiSessionFormatError('blank_line', `Line ${index + 1} is blank.`);
    }
    assertByteLimit(
      line,
      limits.maxLineBytes,
      'line_too_large',
      `Line ${index + 1} exceeds the line limit.`,
    );
    try {
      const parsed: unknown = JSON.parse(line);
      if (!isRecord(parsed)) {
        throw new Error('not an object');
      }
      return parsed;
    } catch {
      throw new PiSessionFormatError('invalid_json', `Line ${index + 1} is not valid JSON.`);
    }
  });

  const header = decodeHeader(records[0]);
  const entryRecords = records.slice(1);
  if (entryRecords.length > limits.maxEntries) {
    throw new PiSessionFormatError(
      'too_many_entries',
      `The session contains more than ${limits.maxEntries} entries.`,
    );
  }

  const diagnostics: ResumeDiagnostic[] = [];
  const ids = new Set<string>();
  const entries = entryRecords.map((record, index) => {
    const entry = normalizeEntry(record, header.sessionId, diagnostics, limits, index + 2, header.cwd);
    if (ids.has(entry.id)) {
      throw new PiSessionFormatError('duplicate_id', `Entry ${entry.id} occurs more than once.`);
    }
    ids.add(entry.id);
    return entry;
  });

  validateTree(entries, limits.maxAncestryDepth);
  validateReferences(entries);
  const authorizedEntries = annotateToolResultAuthorization(entries, diagnostics);
  return { header, entries: authorizedEntries, diagnostics };
}

export function reducePiSession(session: DecodedPiSession): ReducedPiSession {
  const entriesByIdentity = new Map<string, { canonical: string; entry: NormalizedEntry }>();
  const diagnostics = [...session.diagnostics];

  for (const entry of session.entries) {
    const identity = `${session.header.sessionId}:${entry.id}`;
    const canonical = stableSerialize(entry);
    const previous = entriesByIdentity.get(identity);
    if (previous === undefined) {
      entriesByIdentity.set(identity, { canonical, entry });
      continue;
    }
    if (previous.canonical !== canonical) {
      throw new PiSessionFormatError(
        'identity_content_mismatch',
        `Entry ${entry.id} was replayed with different content.`,
      );
    }
    diagnostics.push({
      severity: 'warning',
      code: 'replay_noop',
      message: `Replay of entry ${entry.id} was ignored because its content matched.`,
      entryId: entry.id,
    });
  }

  const entries = [...entriesByIdentity.values()].map(value => value.entry);
  validateTree(entries, DEFAULT_LIMITS.maxAncestryDepth);
  validateReferences(entries);
  const children = buildChildren(entries);
  const terminalPaths = [...entries]
    .filter(entry => (children.get(entry.id)?.length ?? 0) === 0)
    .map(entry => ({
      leafId: entry.id,
      entryIds: pathToRoot(entry.id, entries).reverse(),
    }));

  return {
    header: session.header,
    entries,
    terminalPaths,
    diagnostics,
  };
}

export function projectResume(session: ReducedPiSession, leafId: string): ResumeProjection {
  const terminalPath = session.terminalPaths.find(path => path.leafId === leafId);
  if (terminalPath === undefined) {
    throw new PiSessionFormatError('unknown_leaf', `Terminal path ${leafId} does not exist.`);
  }

  const entriesById = new Map(session.entries.map(entry => [entry.id, entry]));
  const chronology = Object.freeze(terminalPath.entryIds
    .map(entryId => entriesById.get(entryId))
    .filter((entry): entry is NormalizedEntry => entry !== undefined)
    .map(entry => Object.freeze(toActivityItem(entry))));
  const anchors = Object.freeze(chronology.filter(item => item.kind === 'checkpoint'));
  const claims = Object.freeze(chronology.filter(item => item.kind === 'assistant-claim'));
  const evidence = Object.freeze(chronology.filter(item => item.kind === 'tool-evidence'));
  const observedIntent = chronology.find(item => item.kind === 'human' && item.text !== undefined);
  const latestEvidence = latestMatching(evidence, item => item.text !== undefined) ?? evidence[evidence.length - 1];
  const goal = latestAnchor(anchors, 'goal');
  const decision = latestAnchor(anchors, 'decision');
  const question = latestAnchor(anchors, 'question');
  const nextStep = latestAnchor(anchors, 'next-step');
  const latestUserDirection = latestMatching(
    chronology,
    item => item.kind === 'human' && item.text !== undefined,
  );
  const latestOutcome = latestMatching(
    evidence,
    item => item.evidenceStatus === 'observed',
  );
  const latestFailure = latestMatching(
    evidence,
    item => item.evidenceStatus === 'observed-failure',
  );
  const activeTask = goal ?? latestUserDirection;
  const attention = question ?? latestFailure;
  const landmarkIds = new Set([
    ...chronology
      .filter(item =>
        item.kind === 'human' ||
        item.kind === 'checkpoint' ||
        item.kind === 'compaction' ||
        item.kind === 'branch-summary' ||
        item.evidenceStatus === 'observed-failure')
      .slice(-6)
      .map(item => item.id),
    ...[activeTask, latestOutcome, attention, nextStep]
      .filter((item): item is ActivityItem => item !== undefined)
      .map(item => item.id),
  ]);
  const overview = Object.freeze({
    ...(activeTask === undefined ? {} : { activeTask }),
    ...(latestOutcome === undefined ? {} : { latestOutcome }),
    ...(attention === undefined ? {} : { attention }),
    ...(nextStep === undefined ? {} : { nextAction: nextStep }),
    landmarks: Object.freeze(chronology.filter(item => landmarkIds.has(item.id)).slice(-8)),
  });

  return Object.freeze({
    sessionId: session.header.sessionId,
    leafId,
    path: Object.freeze([...terminalPath.entryIds]),
    chronology,
    anchors,
    claims,
    evidence,
    ...(observedIntent === undefined ? {} : { observedIntent }),
    ...(latestEvidence === undefined ? {} : { latestEvidence }),
    goal,
    decision,
    question,
    nextStep,
    overview,
    diagnostics: Object.freeze(
      session.diagnostics.map(diagnostic => Object.freeze({ ...diagnostic })),
    ),
  });
}

export function stableSerialize(value: unknown): string {
  if (value === null || typeof value !== 'object') return JSON.stringify(value);
  if (Array.isArray(value)) return `[${value.map(stableSerialize).join(',')}]`;

  const record = value as Record<string, unknown>;
  return `{${Object.keys(record)
    .sort()
    .map(key => `${JSON.stringify(key)}:${stableSerialize(record[key])}`)
    .join(',')}}`;
}

function decodeHeader(record: RawRecord): SessionHeader {
  if (record.type !== 'session' || record.version !== 3) {
    throw new PiSessionFormatError(
      'unsupported_version',
      'The first line must be a pi session header with version 3.',
    );
  }
  if (
    typeof record.id !== 'string' ||
    record.id.length === 0 ||
    typeof record.timestamp !== 'string' ||
    Number.isNaN(Date.parse(record.timestamp)) ||
    typeof record.cwd !== 'string'
  ) {
    throw new PiSessionFormatError('invalid_header', 'The session header is incomplete.');
  }

  return {
    sessionId: record.id,
    version: 3,
    timestamp: record.timestamp,
    cwd: record.cwd,
    ...(typeof record.parentSession === 'string' ? { parentSession: record.parentSession } : {}),
  };
}

function normalizeEntry(
  record: RawRecord,
  sessionId: string,
  diagnostics: ResumeDiagnostic[],
  limits: typeof DEFAULT_LIMITS,
  lineNumber: number,
  sessionCwd: string,
): NormalizedEntry {
  const id = record.id;
  const parentId = record.parentId;
  const timestamp = record.timestamp;
  if (
    typeof id !== 'string' ||
    !/^[0-9a-f]{8}$/i.test(id) ||
    (parentId !== null && typeof parentId !== 'string') ||
    typeof timestamp !== 'string' ||
    Number.isNaN(Date.parse(timestamp))
  ) {
    throw new PiSessionFormatError('invalid_entry_identity', `Line ${lineNumber} has invalid entry identity.`);
  }

  const base = {
    id,
    parentId,
    timestamp,
    source: { sessionId, entryId: id },
  } as const;

  switch (record.type) {
    case 'message':
      return normalizeMessage(base, record.message, diagnostics, limits, sessionCwd);
    case 'bashExecution':
      return normalizeBashExecution(base, record, diagnostics, limits);
    case 'compaction':
      return {
        ...base,
        kind: 'compaction',
        summary: boundedExcerpt(record.summary, diagnostics, id, limits),
        ...(normalizeCompactionPaths(record.details, sessionCwd, diagnostics, id, limits) ?? {}),
        ...(typeof record.firstKeptEntryId === 'string'
          ? { firstKeptEntryId: record.firstKeptEntryId }
          : {}),
      };
    case 'branch_summary':
      return {
        ...base,
        kind: 'branchSummary',
        summary: boundedExcerpt(record.summary, diagnostics, id, limits),
        ...(typeof record.fromId === 'string' ? { fromId: record.fromId } : {}),
      };
    case 'custom':
      return normalizeCustom(base, record, diagnostics, limits);
    default:
      diagnostics.push({
        severity: 'warning',
        code: 'entry_omitted',
        message: `Entry ${id} of type ${String(record.type)} is retained as an omission.`,
        entryId: id,
      });
      return {
        ...base,
        kind: 'omitted',
        originalType: typeof record.type === 'string' ? record.type : 'unknown',
        reason: 'This entry type is not part of the Phase 0 allowlist.',
      };
  }
}

function normalizeMessage(
  base: Omit<EntryBase, 'source'> & { readonly source: SourceReference },
  rawMessage: unknown,
  diagnostics: ResumeDiagnostic[],
  limits: typeof DEFAULT_LIMITS,
  sessionCwd: string,
): NormalizedEntry {
  if (!isRecord(rawMessage) || !isMessageRole(rawMessage.role)) {
    diagnostics.push({
      severity: 'warning',
      code: 'message_omitted',
      message: `Message entry ${base.id} has a role outside the Phase 0 allowlist.`,
      entryId: base.id,
    });
    return {
      ...base,
      kind: 'omitted',
      originalType: 'message',
      reason: 'The message role is outside the Phase 0 allowlist.',
    };
  }

  const toolCalls = extractToolCalls(rawMessage.content, base.id, sessionCwd, diagnostics, limits);
  const toolCallId = typeof rawMessage.toolCallId === 'string' ? rawMessage.toolCallId : undefined;
  const toolName = typeof rawMessage.toolName === 'string' ? rawMessage.toolName : undefined;
  const extractedText = extractText(rawMessage.content);
  if (extractedText === undefined && rawMessage.content !== undefined) {
    diagnostics.push({
      severity: 'warning',
      code: 'content_unavailable',
      message: `No text content was recorded for entry ${base.id}.`,
      entryId: base.id,
    });
  }
  const text = boundedExcerpt(extractedText, diagnostics, base.id, limits);

  return {
    ...base,
    kind: 'message',
    role: rawMessage.role,
    ...(text === undefined ? {} : { text }),
    ...(toolCallId === undefined ? {} : { toolCallId }),
    ...(toolName === undefined ? {} : { toolName }),
    toolCalls,
    ...(typeof rawMessage.isError === 'boolean' ? { isError: rawMessage.isError } : {}),
    ...(rawMessage.role === 'toolResult'
      ? { outcome: rawMessage.isError === true ? 'failure' : 'success' }
      : {}),
  };
}

function normalizeBashExecution(
  base: Omit<EntryBase, 'source'> & { readonly source: SourceReference },
  record: RawRecord,
  diagnostics: ResumeDiagnostic[],
  limits: typeof DEFAULT_LIMITS,
): NormalizedEntry {
  const command = typeof record.command === 'string' ? record.command.trim() : '';
  const commandName = command.split(/\s+/, 1)[0] ?? '';
  const commandAllowed = isAllowedBashCommandText(command);
  const classification = classifyBashCommand(command);
  const rawCommandLabel = command;
  if (!commandAllowed) {
    diagnostics.push({
      severity: 'warning',
      code: 'command_requires_explicit_egress',
      message: `Command output from ${commandName || 'unknown command'} was retained for explicit use only.`,
      entryId: base.id,
    });
  }
  const commandLabel = boundedExcerpt(rawCommandLabel, diagnostics, base.id, limits);
  const output = boundedExcerpt(record.output, diagnostics, base.id, limits);
  return {
    ...base,
    kind: 'bashExecution',
    classification,
    ...(commandLabel === undefined ? {} : { commandLabel }),
    ...(output === undefined ? {} : { output }),
    automaticOutputAllowed:
      commandAllowed && commandLabel !== undefined && !isSensitiveText(commandLabel),
    ...(typeof record.exitCode === 'number' ? { exitCode: record.exitCode } : {}),
    cancelled: record.cancelled === true,
  };
}

function annotateToolResultAuthorization(
  entries: readonly NormalizedEntry[],
  diagnostics: ResumeDiagnostic[],
): readonly NormalizedEntry[] {
  const callsById = new Map<string, {
    readonly entryId: string;
    readonly name: string;
    readonly resultTextAllowed: boolean;
  }[]>();
  const entriesById = new Map(entries.map(entry => [entry.id, entry]));

  for (const entry of entries) {
    if (entry.kind !== 'message' || entry.role !== 'assistant') continue;
    for (const toolCall of entry.toolCalls) {
      const calls = callsById.get(toolCall.id) ?? [];
      calls.push({
        entryId: entry.id,
        name: toolCall.name,
        resultTextAllowed:
          toolCall.name !== 'bash' ||
          (toolCall.bashLabel !== undefined && !isSensitiveText(toolCall.bashLabel)),
      });
      callsById.set(toolCall.id, calls);
    }
  }

  return entries.map(entry => {
    if (entry.kind !== 'message' || entry.role !== 'toolResult' || entry.text === undefined) {
      return entry;
    }

    const calls = entry.toolCallId === undefined ? [] : callsById.get(entry.toolCallId) ?? [];
    const call = calls.length === 1 ? calls[0] : undefined;
    let ancestorId = entry.parentId;
    let callIsAncestor = false;
    while (ancestorId !== null) {
      if (ancestorId === call?.entryId) {
        callIsAncestor = true;
        break;
      }
      ancestorId = entriesById.get(ancestorId)?.parentId ?? null;
    }

    const automaticOutputAllowed =
      call !== undefined &&
      callIsAncestor &&
      call.name === entry.toolName &&
      call.resultTextAllowed &&
      entry.toolName !== undefined &&
      AUTOMATIC_TOOL_RESULT_NAMES.has(entry.toolName);
    if (!automaticOutputAllowed) {
      diagnostics.push({
        severity: 'warning',
        code: 'tool_output_requires_explicit_egress',
        message: `Tool output from ${entry.id} was retained for explicit use, but is unavailable to automatic model workflows.`,
        entryId: entry.id,
      });
    }
    return {
      ...entry,
      automaticOutputAllowed,
    };
  });
}

function normalizeCustom(
  base: Omit<EntryBase, 'source'> & { readonly source: SourceReference },
  record: RawRecord,
  diagnostics: ResumeDiagnostic[],
  limits: typeof DEFAULT_LIMITS,
): NormalizedEntry {
  const data = record.data;
  if (
    record.customType === 'canopy-checkpoint' &&
    isRecord(data) &&
    data.accepted === true &&
    typeof data.kind === 'string' &&
    ANCHOR_KINDS.has(data.kind as AnchorKind) &&
    typeof data.text === 'string'
  ) {
    const text = boundedExcerpt(data.text, diagnostics, base.id, limits);
    if (text !== undefined) {
      return {
        ...base,
        kind: 'checkpoint',
        anchorKind: data.kind as AnchorKind,
        text,
        accepted: true,
      };
    }
  }

  diagnostics.push({
    severity: 'warning',
    code: 'custom_omitted',
    message: `Custom entry ${base.id} was not an accepted checkpoint.`,
    entryId: base.id,
  });
  return {
    ...base,
    kind: 'omitted',
    originalType: 'custom',
    reason: 'Only accepted canopy-checkpoint entries are imported.',
  };
}

type ActivityItemContent = Omit<ActivityItem, 'origin' | 'derivation' | 'review' | 'sources'>;

function toActivityItem(entry: NormalizedEntry): ActivityItem {
  const source = freezeSourceReference(entry.source);
  return createThinkingItem({
    ...toActivityItemContent(entry),
    source,
    origin: activityOrigin(entry),
    derivation: activityDerivation(entry),
    review: { kind: 'unreviewed' },
    sources: [source],
  });
}

function toActivityItemContent(entry: NormalizedEntry): ActivityItemContent {
  switch (entry.kind) {
    case 'message':
      if (entry.role === 'user') {
        return {
          id: entry.id,
          kind: 'human',
          title: 'Human intent',
          timestamp: entry.timestamp,
          ...(entry.text === undefined ? {} : { text: entry.text }),
          source: entry.source,
        };
      }
      if (entry.role === 'assistant') {
        return {
          id: entry.id,
          kind: 'assistant-claim',
          title: entry.toolCalls.length > 0 ? `Assistant requested ${entry.toolCalls[0].name}` : 'Assistant claim',
          timestamp: entry.timestamp,
          ...(entry.text === undefined ? {} : { text: entry.text }),
          source: entry.source,
          evidenceStatus: 'claim',
        };
      }
      return {
        id: entry.id,
        kind: 'tool-evidence',
        title: `${entry.toolName ?? 'Tool'} ${entry.isError === true ? 'failed' : 'completed'}`,
        timestamp: entry.timestamp,
        ...(entry.text === undefined ? {} : { text: entry.text }),
        source: entry.source,
        evidenceStatus: entry.isError === true ? 'observed-failure' : 'observed',
      };
    case 'bashExecution':
      return {
        id: entry.id,
        kind: 'tool-evidence',
        title: entry.commandLabel === undefined ? 'Validation activity' : entry.commandLabel,
        timestamp: entry.timestamp,
        ...(entry.output === undefined ? {} : { text: entry.output }),
        source: entry.source,
        evidenceStatus: entry.exitCode === 0 && !entry.cancelled ? 'observed' : 'observed-failure',
      };
    case 'compaction':
      return {
        id: entry.id,
        kind: 'compaction',
        title: 'Conversation summary',
        timestamp: entry.timestamp,
        ...(entry.summary === undefined ? {} : { text: entry.summary }),
        source: entry.source,
      };
    case 'branchSummary':
      return {
        id: entry.id,
        kind: 'branch-summary',
        title: 'Branch summary',
        timestamp: entry.timestamp,
        ...(entry.summary === undefined ? {} : { text: entry.summary }),
        source: entry.source,
      };
    case 'checkpoint':
      return {
        id: entry.id,
        kind: 'checkpoint',
        title: anchorLabel(entry.anchorKind),
        timestamp: entry.timestamp,
        text: entry.text,
        source: entry.source,
        anchorKind: entry.anchorKind,
        accepted: true,
      };
    case 'omitted':
      return {
        id: entry.id,
        kind: 'omitted',
        title: `Omitted ${entry.originalType}`,
        timestamp: entry.timestamp,
        text: entry.reason,
        source: entry.source,
      };
  }
}

function activityOrigin(entry: NormalizedEntry): EpistemicOrigin {
  switch (entry.kind) {
    case 'message':
      switch (entry.role) {
        case 'user':
          return { kind: 'recorded-human' };
        case 'assistant':
          return { kind: 'assistant-claim' };
        case 'toolResult':
          return {
            kind: 'observed-tool',
            outcome: entry.isError === true || entry.outcome === 'failure' ? 'failure' : 'success',
            ...(entry.toolCallId === undefined ? {} : { toolCallId: entry.toolCallId }),
          };
      }
    case 'bashExecution':
      return {
        kind: 'observed-tool',
        outcome: entry.exitCode === 0 && !entry.cancelled ? 'success' : 'failure',
      };
    case 'checkpoint':
      return { kind: 'human-accepted-source' };
    case 'compaction':
    case 'branchSummary':
      return { kind: 'assistant-claim' };
    case 'omitted':
      return { kind: 'canopy-system' };
  }
}

function activityDerivation(entry: NormalizedEntry): Derivation {
  return entry.kind === 'omitted'
    ? {
        kind: 'deterministic',
        ruleId: 'normalized-entry-omission',
        ruleVersion: PKE_SENSITIVE_POLICY_VERSION,
      }
    : { kind: 'recorded' };
}

function latestMatching(
  items: readonly ActivityItem[],
  predicate: (item: ActivityItem) => boolean,
): ActivityItem | undefined {
  return [...items].reverse().find(predicate);
}

function latestAnchor(anchors: readonly ActivityItem[], kind: AnchorKind): ActivityItem | undefined {
  return latestMatching(anchors, anchor => anchor.anchorKind === kind);
}

function anchorLabel(kind: AnchorKind): string {
  switch (kind) {
    case 'goal':
      return 'Accepted goal';
    case 'decision':
      return 'Accepted decision';
    case 'question':
      return 'Open question';
    case 'next-step':
      return 'Next step';
  }
}

function extractText(content: unknown): string | undefined {
  if (typeof content === 'string') return content;
  if (!Array.isArray(content)) return undefined;
  return content
    .filter(isRecord)
    .filter(block => block.type === 'text' && typeof block.text === 'string')
    .map(block => block.text as string)
    .join('\n');
}

export interface SafePathParseResult {
  readonly ok: boolean;
  readonly path?: string;
  readonly reason?: 'empty' | 'absolute' | 'unsafe-traversal' | 'sensitive-segment' | 'invalid';
}

export function parseSafeRelativePathValue(value: unknown, cwd: string): SafePathParseResult {
  if (typeof value !== 'string' || value.length === 0 || value.includes('\0')) {
    return { ok: false, reason: 'empty' };
  }
  const normalized = value.split('\\').join('/');
  if (/^[A-Za-z]:[^/]/.test(normalized) || /^[A-Za-z][A-Za-z0-9+.-]*:\/\//.test(normalized)) {
    return { ok: false, reason: 'absolute' };
  }
  if (normalized.startsWith('/') || /^[A-Za-z]:\//.test(normalized)) {
    const base = cwd.split('\\').join('/').replace(/\/+$/, '');
    if (!normalized.startsWith(`${base}/`)) return { ok: false, reason: 'absolute' };
    return parseSafeRelativePathValue(normalized.slice(base.length + 1), '.',);
  }
  const output: string[] = [];
  for (const segment of normalized.split('/')) {
    if (segment === '' || segment === '.') continue;
    if (segment === '..') {
      if (output.length === 0) return { ok: false, reason: 'unsafe-traversal' };
      output.pop();
      continue;
    }
    if (sensitivePolicyReasons(segment).length > 0) return { ok: false, reason: 'sensitive-segment' };
    output.push(segment);
  }
  return output.length === 0 ? { ok: false, reason: 'empty' } : { ok: true, path: output.join('/') };
}

function parseSafeRelativePath(
  value: unknown,
  cwd: string,
  diagnostics: ResumeDiagnostic[],
  entryId: string,
  limits: typeof DEFAULT_LIMITS,
): string | undefined {
  const result = parseSafeRelativePathValue(value, cwd);
  if (!result.ok) {
    diagnostics.push({
      severity: 'warning',
      code: result.reason === 'sensitive-segment' ? 'path_omitted_sensitive' : 'path_omitted_unsafe',
      message: `Path from ${entryId} was omitted by the fail-closed path policy.`,
      entryId,
    });
    return undefined;
  }
  return boundedExcerpt(result.path, diagnostics, entryId, limits);
}

function extractToolCalls(
  content: unknown,
  entryId: string,
  sessionCwd: string,
  diagnostics: ResumeDiagnostic[],
  limits: typeof DEFAULT_LIMITS,
): readonly NormalizedToolCall[] {
  if (!Array.isArray(content)) return [];
  return content
    .filter(isRecord)
    .filter(
      block =>
        block.type === 'toolCall' &&
        typeof block.id === 'string' &&
        typeof block.name === 'string',
    )
    .map(block => {
      const name = block.name as string;
      const rawPath = ALLOWED_TOOL_PATH_NAMES.has(name)
        ? toolArgument(block, 'path') ?? toolArgument(block, 'filePath')
        : undefined;
      const path = rawPath === undefined
        ? undefined
        : parseSafeRelativePath(rawPath, sessionCwd, diagnostics, entryId, limits);
      const editCount = name === 'edit' ? boundedEditCount(block) : undefined;
      const rawCommand = name === 'bash' ? toolArgument(block, 'command') : undefined;
      const bashLabel = rawCommand !== undefined && isAllowedBashCommandText(rawCommand)
        ? boundedExcerpt(safeBashLabel(rawCommand), diagnostics, entryId, limits)
        : undefined;
      return {
        id: block.id as string,
        name,
        ...(path === undefined ? {} : { path }),
        ...(editCount === undefined ? {} : { editCount }),
        ...(name === 'bash'
          ? {
              bashClassification: classifyBashCommand(rawCommand ?? ''),
              ...(bashLabel === undefined ? {} : { bashLabel }),
            }
          : {}),
      };
    });
}

function normalizeCompactionPaths(
  rawDetails: unknown,
  cwd: string,
  diagnostics: ResumeDiagnostic[],
  entryId: string,
  limits: typeof DEFAULT_LIMITS,
): { readonly details: CompactionPaths } | undefined {
  if (!isRecord(rawDetails)) return undefined;
  const normalize = (value: unknown): readonly string[] => {
    if (!Array.isArray(value)) return [];
    return value.flatMap(item => {
      const parsed = parseSafeRelativePath(item, cwd, diagnostics, entryId, limits);
      return parsed === undefined ? [] : [parsed];
    });
  };
  const readFiles = normalize(rawDetails.readFiles);
  const modifiedFiles = normalize(rawDetails.modifiedFiles);
  if (readFiles.length === 0 && modifiedFiles.length === 0) return undefined;
  return { details: { readFiles, modifiedFiles } };
}

function toolArgument(block: RawRecord, name: string): string | undefined {
  if (typeof block[name] === 'string') return block[name] as string;
  const candidates = [block.arguments, block.input, block.params];
  for (const candidate of candidates) {
    if (isRecord(candidate) && typeof candidate[name] === 'string') return candidate[name] as string;
  }
  return undefined;
}

function boundedEditCount(block: RawRecord): number | undefined {
  const candidates = [block.editCount, block.arguments, block.input];
  for (const candidate of candidates) {
    if (typeof candidate === 'number' && Number.isInteger(candidate) && candidate >= 0 && candidate <= 128) {
      return candidate;
    }
    if (isRecord(candidate) && Array.isArray(candidate.edits)) return Math.min(candidate.edits.length, 128);
  }
  return undefined;
}

export function isAllowedBashCommandText(command: string): boolean {
  const trimmed = command.trim();
  if (trimmed.length === 0) return false;
  if (/(?:&&|\|\||[;|&\n\r`<>]|\$\()/.test(trimmed)) return false;
  const commandName = trimmed.split(/\s+/, 1)[0] ?? '';
  return ALLOWED_COMMAND_PREFIXES.has(commandName);
}

function safeBashLabel(command: string): string {
  return command.trim().split(/\s+/).slice(0, 4).join(' ');
}

function classifyBashCommand(command: string): BashClassification {
  const lower = command.toLowerCase();
  if (lower.startsWith('git ') || lower === 'git') return 'git';
  if (/\b(check|typecheck|lint|fmt|format)\b/.test(lower)) return 'lint';
  if (/\b(test|playwright)\b/.test(lower)) return 'test';
  if (/\b(build|compile|bundle)\b/.test(lower)) return 'build';
  return 'other';
}

function boundedExcerpt(
  value: unknown,
  diagnostics: ResumeDiagnostic[],
  entryId: string,
  limits: typeof DEFAULT_LIMITS,
): SafeExcerpt {
  if (typeof value !== 'string') return undefined;
  const text = value.trim();
  if (text.length === 0) return undefined;
  if (isSensitiveText(text)) {
    diagnostics.push({
      severity: 'warning',
      code: 'excerpt_contains_sensitive_pattern',
      message: `Text from ${entryId} was retained, but matches a sensitive-content warning pattern.`,
      entryId,
    });
  }
  if (text.length > limits.maxExcerptChars) {
    diagnostics.push({
      severity: 'warning',
      code: 'excerpt_truncated',
      message: `Text from ${entryId} was bounded to ${limits.maxExcerptChars} characters.`,
      entryId,
    });
  }
  return text.slice(0, limits.maxExcerptChars);
}

function validateTree(entries: readonly NormalizedEntry[], maxDepth: number): void {
  if (entries.length === 0) {
    throw new PiSessionFormatError('no_entries', 'The session has no entries.');
  }
  const ids = new Set(entries.map(entry => entry.id));
  const roots = entries.filter(entry => entry.parentId === null);
  if (roots.length !== 1) {
    throw new PiSessionFormatError('invalid_root', 'The session must have exactly one root entry.');
  }
  for (const entry of entries) {
    if (entry.parentId !== null && !ids.has(entry.parentId)) {
      throw new PiSessionFormatError(
        'missing_parent',
        `Entry ${entry.id} references missing parent ${entry.parentId}.`,
      );
    }
    const seen = new Set<string>();
    let current: NormalizedEntry | undefined = entry;
    let depth = 0;
    while (current !== undefined) {
      if (seen.has(current.id)) {
        throw new PiSessionFormatError('cycle', `Entry ${entry.id} participates in a cycle.`);
      }
      seen.add(current.id);
      depth += 1;
      if (depth > maxDepth) {
        throw new PiSessionFormatError('ancestry_too_deep', `Entry ${entry.id} exceeds the ancestry limit.`);
      }
      current = current.parentId === null ? undefined : entries.find(candidate => candidate.id === current?.parentId);
    }
  }
}

function validateReferences(entries: readonly NormalizedEntry[]): void {
  const ids = new Set(entries.map(entry => entry.id));
  for (const entry of entries) {
    if (
      entry.kind === 'compaction' &&
      entry.firstKeptEntryId !== undefined &&
      !ids.has(entry.firstKeptEntryId)
    ) {
      throw new PiSessionFormatError(
        'missing_reference',
        `Compaction ${entry.id} references missing entry ${entry.firstKeptEntryId}.`,
      );
    }
    if (entry.kind === 'branchSummary' && entry.fromId !== undefined && !ids.has(entry.fromId)) {
      throw new PiSessionFormatError(
        'missing_reference',
        `Branch summary ${entry.id} references missing entry ${entry.fromId}.`,
      );
    }
  }
}

function buildChildren(entries: readonly NormalizedEntry[]): Map<string, string[]> {
  const children = new Map<string, string[]>();
  for (const entry of entries) {
    if (entry.parentId === null) continue;
    const siblingIds = children.get(entry.parentId) ?? [];
    siblingIds.push(entry.id);
    children.set(entry.parentId, siblingIds);
  }
  return children;
}

function pathToRoot(leafId: string, entries: readonly NormalizedEntry[]): string[] {
  const byId = new Map(entries.map(entry => [entry.id, entry]));
  const path: string[] = [];
  let current = byId.get(leafId);
  while (current !== undefined) {
    path.push(current.id);
    current = current.parentId === null ? undefined : byId.get(current.parentId);
  }
  return path;
}

function assertByteLimit(input: string, limit: number, code: string, message: string): void {
  if (new TextEncoder().encode(input).byteLength > limit) {
    throw new PiSessionFormatError(code, message);
  }
}

function isRecord(value: unknown): value is RawRecord {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function isMessageRole(value: unknown): value is 'user' | 'assistant' | 'toolResult' {
  return value === 'user' || value === 'assistant' || value === 'toolResult';
}
