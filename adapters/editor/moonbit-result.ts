/** The structural JavaScript representation emitted for MoonBit Result. */
export type MoonBitResult<T, E> =
  | { readonly $tag: 1; readonly _0: T }
  | { readonly $tag: 0; readonly _0: E };

export type CanopyHostErrorCode =
  | 'ParserFailure'
  | 'DisposedHandle'
  | 'HostOperationFailure';

export class CanopyHostError extends Error {
  readonly code: CanopyHostErrorCode;
  readonly operation: string;
  readonly handleInvalidated: boolean;

  constructor(
    code: CanopyHostErrorCode,
    operation: string,
    handleInvalidated: boolean,
  ) {
    super('Canopy host operation failed');
    this.name = 'CanopyHostError';
    this.code = code;
    this.operation = operation;
    this.handleInvalidated = handleInvalidated;
    Object.setPrototypeOf(this, new.target.prototype);
  }
}

type AnyFunction = (...args: any[]) => any;
type FunctionKey<T> = {
  [K in keyof T]-?: T[K] extends AnyFunction ? K : never;
}[keyof T] & string;
type ResultValue<T> = T extends { readonly $tag: 1; readonly _0: infer Value }
  ? Value
  : T extends { readonly $tag: 0; readonly _0: any }
    ? never
    : T;
type AdaptedFunction<T> = T extends (...args: infer Args) => infer Return
  ? (...args: Args) => ResultValue<Return>
  : T;

/**
 * The host-facing shape of a generated module after structural Result exports
 * have been unwrapped. Raw generated modules remain free to expose Result.
 */
export type AdaptedMoonBitModule<T extends object> = {
  [K in keyof T]: AdaptedFunction<T[K]>;
};

export interface MoonBitModuleAdapterOptions<
  T extends object,
  CreateKeys extends readonly FunctionKey<T>[] = readonly FunctionKey<T>[],
  DestroyKeys extends readonly FunctionKey<T>[] = readonly FunctionKey<T>[],
  TryDestroyKeys extends readonly FunctionKey<T>[] = readonly FunctionKey<T>[],
> {
  readonly createFunctions?: CreateKeys;
  readonly destroyFunctions?: DestroyKeys;
  readonly tryDestroyFunctions?: TryDestroyKeys;
  readonly initialHandles?: readonly number[];
}

function isMoonBitResult(value: unknown): value is MoonBitResult<unknown, unknown> {
  if (typeof value !== 'object' || value === null) return false;
  const candidate = value as { $tag?: unknown; _0?: unknown };
  return (
    (candidate.$tag === 0 || candidate.$tag === 1) &&
    Object.prototype.hasOwnProperty.call(candidate, '_0')
  );
}

type ClassifiedResult =
  | { readonly kind: 'value'; readonly value: unknown }
  | { readonly kind: 'failure' };

function ifMoonBitResultValue(value: unknown): ClassifiedResult {
  if (!isMoonBitResult(value)) return { kind: 'value', value };
  if (value.$tag === 1) return { kind: 'value', value: value._0 };
  return { kind: 'failure' };
}

/**
 * Wrap one generated MoonBit module at its imperative host boundary.
 *
 * Result classification and unwrapping are pure. The shell owns only the
 * invalid-handle Set and best-effort destruction after a terminal Err.
 */
export function adaptMoonBitModule<
  T extends object,
  const CreateKeys extends readonly FunctionKey<T>[],
  const DestroyKeys extends readonly FunctionKey<T>[],
  const TryDestroyKeys extends readonly FunctionKey<T>[],
>(
  raw: T,
  options: MoonBitModuleAdapterOptions<
    T,
    CreateKeys,
    DestroyKeys,
    TryDestroyKeys
  > = {},
): AdaptedMoonBitModule<T> {
  const createNames = new Set<string>(options.createFunctions ?? []);
  const destroyNames = new Set<string>(options.destroyFunctions ?? []);
  const tryDestroyNames = new Set<string>(options.tryDestroyFunctions ?? []);
  const ownedHandles = new Set<number>(options.initialHandles ?? []);
  const invalidatedHandles = new Set<number>();
  const pendingCleanupHandles = new Set<number>();
  const adapted: Record<string, unknown> = Object.assign(
    Object.create(null) as Record<string, unknown>,
    raw,
  );

  const destroyHandle = (handle: number, forceInvalidation: boolean): boolean => {
    if (!ownedHandles.has(handle)) return true;
    if (
      invalidatedHandles.has(handle) &&
      !pendingCleanupHandles.has(handle)
    ) return true;
    let destroyed = false;
    const cleanupNames = tryDestroyNames.size > 0 ? tryDestroyNames : destroyNames;
    for (const name of cleanupNames) {
      const destroy = raw[name as keyof T];
      if (typeof destroy !== 'function') continue;
      try {
        // Current FFI destructors return false when coordinator dependencies
        // refuse teardown. Legacy destructors return Unit, which counts as
        // successful best-effort cleanup.
        destroyed = destroy.call(raw, handle) !== false;
      } catch {
        destroyed = false;
      }
      break;
    }
    if (destroyed) {
      ownedHandles.delete(handle);
      pendingCleanupHandles.delete(handle);
      invalidatedHandles.add(handle);
    } else if (forceInvalidation) {
      // The JS handle is terminal immediately, but coordinator teardown may be
      // refused while dependents remain. Keep ownership so a later explicit
      // destroy can retry cleanup without permitting any other operation.
      invalidatedHandles.add(handle);
      pendingCleanupHandles.add(handle);
    }
    return destroyed;
  };

  for (const [name, member] of Object.entries(raw)) {
    if (typeof member !== 'function') continue;
    adapted[name] = (...args: unknown[]) => {
      const handle = args[0];
      const hasNumericHandle = typeof handle === 'number';
      const isOwnedHandle = hasNumericHandle && ownedHandles.has(handle);
      if (
        hasNumericHandle &&
        invalidatedHandles.has(handle) &&
        !destroyNames.has(name) &&
        !tryDestroyNames.has(name)
      ) {
        throw new CanopyHostError('DisposedHandle', name, true);
      }
      if (
        (destroyNames.has(name) || tryDestroyNames.has(name)) &&
        hasNumericHandle
      ) {
        return destroyHandle(handle, false);
      }

      let result: unknown;
      try {
        result = member.apply(raw, args);
      } catch {
        if (isOwnedHandle) destroyHandle(handle, true);
        throw new CanopyHostError(
          'HostOperationFailure',
          name,
          isOwnedHandle,
        );
      }
      const value = ifMoonBitResultValue(result);
      if (value.kind === 'failure') {
        if (isOwnedHandle) destroyHandle(handle, true);
        throw new CanopyHostError('ParserFailure', name, isOwnedHandle);
      }
      if (createNames.has(name) && typeof value.value === 'number') {
        invalidatedHandles.delete(value.value);
        pendingCleanupHandles.delete(value.value);
        ownedHandles.add(value.value);
      }
      return value.value;
    };
  }

  return adapted as AdaptedMoonBitModule<T>;
}
