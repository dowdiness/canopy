import assert from 'node:assert/strict';
import test from 'node:test';
import {
  adaptMoonBitModule,
  CanopyHostError,
  type MoonBitResult,
} from '../moonbit-result.ts';

type RawModule = {
  create: (name: string) => MoonBitResult<number, { secret: string }>;
  read: (handle: number) => MoonBitResult<string, { secret: string }>;
  destroy: (handle: number) => boolean | undefined;
};

const ok = <T>(value: T): MoonBitResult<T, never> => ({ $tag: 1, _0: value });
const err = (secret: string): MoonBitResult<never, { secret: string }> => ({
  $tag: 0,
  _0: { secret },
});

function expectHostError(
  action: () => unknown,
  expected: Pick<CanopyHostError, 'code' | 'operation' | 'handleInvalidated'>,
): CanopyHostError {
  let thrown: unknown;
  try {
    action();
  } catch (error) {
    thrown = error;
  }
  assert.ok(thrown instanceof CanopyHostError);
  assert.deepEqual(
    {
      code: thrown.code,
      operation: thrown.operation,
      handleInvalidated: thrown.handleInvalidated,
    },
    expected,
  );
  return thrown;
}

test('unwraps Ok values without changing the app-facing return shape', () => {
  const raw: RawModule = {
    create: () => ok(41),
    read: () => ok('text'),
    destroy: () => undefined,
  };
  const module = adaptMoonBitModule(raw, {
    createFunctions: ['create'],
    destroyFunctions: ['destroy'],
  });

  assert.equal(module.create('editor'), 41);
  assert.equal(module.read(41), 'text');
});

test('throws a stable redacted error for Err values', () => {
  const raw: RawModule = {
    create: () => err('private parser details'),
    read: () => ok('unused'),
    destroy: () => undefined,
  };
  const module = adaptMoonBitModule(raw, {
    createFunctions: ['create'],
    destroyFunctions: ['destroy'],
  });

  const error = expectHostError(
    () => module.create('editor'),
    {
      code: 'ParserFailure',
      operation: 'create',
      handleInvalidated: false,
    },
  );
  assert.equal(error.name, 'CanopyHostError');
  assert.equal(error.message, 'Canopy host operation failed');
  assert.doesNotMatch(String(error), /_0|private parser details/);
  assert.doesNotMatch(JSON.stringify(error), /private parser details/);
});

test('destroys and invalidates a handle when an operation returns Err', () => {
  const destroyed: number[] = [];
  const raw: RawModule = {
    create: () => ok(7),
    read: () => err('terminal failure'),
    destroy: handle => {
      destroyed.push(handle);
      return undefined;
    },
  };
  const module = adaptMoonBitModule(raw, {
    createFunctions: ['create'],
    destroyFunctions: ['destroy'],
  });
  const handle = module.create('editor');

  expectHostError(
    () => module.read(handle),
    {
      code: 'ParserFailure',
      operation: 'read',
      handleInvalidated: true,
    },
  );
  assert.deepEqual(destroyed, [handle]);
});

test('explicit destroy is idempotent and invalidates the handle', () => {
  const destroyed: number[] = [];
  const raw: RawModule = {
    create: () => ok(7),
    read: () => ok('text'),
    destroy: handle => {
      destroyed.push(handle);
      return undefined;
    },
  };
  const module = adaptMoonBitModule(raw, {
    createFunctions: ['create'],
    destroyFunctions: ['destroy'],
  });
  const handle = module.create('editor');

  module.destroy(handle);
  module.destroy(handle);

  assert.deepEqual(destroyed, [handle]);
  expectHostError(
    () => module.read(handle),
    {
      code: 'DisposedHandle',
      operation: 'read',
      handleInvalidated: true,
    },
  );
});

test('keeps an owned handle usable when confirmed destroy is refused', () => {
  let legacyDestroyCalls = 0;
  let confirmedDestroyCalls = 0;
  const raw = {
    create: (_name: string) => ok(7),
    read: (_handle: number) => ok('text'),
    destroy: (_handle: number) => {
      legacyDestroyCalls += 1;
    },
    tryDestroy: (_handle: number) => {
      confirmedDestroyCalls += 1;
      return false;
    },
  };
  const module = adaptMoonBitModule(raw, {
    createFunctions: ['create'],
    destroyFunctions: ['destroy'],
    tryDestroyFunctions: ['tryDestroy'],
  });
  const handle = module.create('editor');

  assert.equal(module.destroy(handle), false);
  assert.equal(module.read(handle), 'text');
  assert.equal(legacyDestroyCalls, 0);
  assert.equal(confirmedDestroyCalls, 1);
});

test('invalidates a handle created before the adapter was installed', () => {
  const destroyed: number[] = [];
  const raw: RawModule = {
    create: () => ok(7),
    read: () => err('terminal failure'),
    destroy: handle => {
      destroyed.push(handle);
      return undefined;
    },
  };
  const module = adaptMoonBitModule(raw, {
    createFunctions: ['create'],
    destroyFunctions: ['destroy'],
    initialHandles: [0],
  });

  expectHostError(
    () => module.read(0),
    {
      code: 'ParserFailure',
      operation: 'read',
      handleInvalidated: true,
    },
  );
  assert.deepEqual(destroyed, [0]);
});

test('retries refused cleanup without reopening a terminal handle', () => {
  let cleanupAttempts = 0;
  const raw = {
    create: (_name: string) => ok(7),
    read: (_handle: number) => err('terminal failure'),
    destroy: (_handle: number) => undefined,
    tryDestroy: (_handle: number) => {
      cleanupAttempts += 1;
      return cleanupAttempts > 1;
    },
  };
  const module = adaptMoonBitModule(raw, {
    createFunctions: ['create'],
    destroyFunctions: ['destroy'],
    tryDestroyFunctions: ['tryDestroy'],
  });
  const handle = module.create('editor');

  assert.throws(() => module.read(handle), CanopyHostError);
  expectHostError(
    () => module.read(handle),
    {
      code: 'DisposedHandle',
      operation: 'read',
      handleInvalidated: true,
    },
  );
  assert.equal(module.destroy(handle), true);
  assert.equal(cleanupAttempts, 2);
});

test('rejects repeated operations without re-entering a failed module', () => {
  let reads = 0;
  const raw: RawModule = {
    create: () => ok(7),
    read: () => {
      reads += 1;
      return err('terminal failure');
    },
    destroy: () => undefined,
  };
  const module = adaptMoonBitModule(raw, {
    createFunctions: ['create'],
    destroyFunctions: ['destroy'],
  });
  const handle = module.create('editor');

  assert.throws(() => module.read(handle), CanopyHostError);
  expectHostError(
    () => module.read(handle),
    {
      code: 'DisposedHandle',
      operation: 'read',
      handleInvalidated: true,
    },
  );
  assert.equal(reads, 1);
});

test('does not destroy an unowned numeric argument', () => {
  const destroyed: number[] = [];
  const raw: RawModule = {
    create: () => ok(7),
    read: () => err('unknown handle'),
    destroy: handle => {
      destroyed.push(handle);
      return undefined;
    },
  };
  const module = adaptMoonBitModule(raw, {
    createFunctions: ['create'],
    destroyFunctions: ['destroy'],
  });

  expectHostError(
    () => module.read(99),
    {
      code: 'ParserFailure',
      operation: 'read',
      handleInvalidated: false,
    },
  );
  module.destroy(99);
  assert.deepEqual(destroyed, []);
});

test('create failure does not destroy a nonexistent handle', () => {
  const destroyed: number[] = [];
  const raw: RawModule = {
    create: () => err('secret create failure'),
    read: () => ok('unused'),
    destroy: handle => {
      destroyed.push(handle);
      return undefined;
    },
  };
  const module = adaptMoonBitModule(raw, {
    createFunctions: ['create'],
    destroyFunctions: ['destroy'],
  });

  assert.throws(() => module.create('editor'), CanopyHostError);
  assert.deepEqual(destroyed, []);
});
