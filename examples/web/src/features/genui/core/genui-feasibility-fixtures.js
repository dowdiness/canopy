import orders from './fixtures/orders.json' with { type: 'json' };
import inventory from './fixtures/inventory.json' with { type: 'json' };
import { INCIDENTS_CSV } from './fixtures/incidents-csv.js';

const FILTER_OPERATORS = Object.freeze(['eq', 'lt']);
const AGGREGATIONS = Object.freeze(['count', 'sum', 'average', 'min', 'max']);

function freezeFixture(fixture) {
  return Object.freeze({
    ...fixture,
    fields: Object.freeze([...fixture.fields]),
    numericFields: Object.freeze([...fixture.numericFields]),
    source: deepFreeze(fixture.source),
  });
}

export const GENUI_FEASIBILITY_FIXTURES = Object.freeze([
  freezeFixture({
    caseId: 'orders-pending-attention',
    question: 'Which pending orders require attention, and how much value is tied up?',
    sourceFormat: 'json-array',
    binding: 'orders',
    selectionKey: 'id',
    fields: ['id', 'name', 'status', 'amount'],
    numericFields: ['amount'],
    taskValue: 'pending',
    source: orders,
  }),
  freezeFixture({
    caseId: 'inventory-low-stock',
    question: 'Which inventory items are below 10 units, and what is their total on-hand?',
    sourceFormat: 'json-nested-items',
    binding: 'inventory',
    selectionKey: 'sku',
    fields: ['sku', 'product', 'category', 'on_hand'],
    numericFields: ['on_hand'],
    taskValue: 10,
    source: inventory,
  }),
  freezeFixture({
    caseId: 'incidents-critical-resolution',
    question: 'Which critical incidents took longest to resolve, and what was their average resolution time?',
    sourceFormat: 'restricted-csv',
    binding: 'incidents',
    selectionKey: 'incident_id',
    fields: ['incident_id', 'service', 'severity', 'resolution_minutes'],
    numericFields: ['resolution_minutes'],
    taskValue: 'critical',
    source: INCIDENTS_CSV,
  }),
]);

export function getFeasibilityFixture(caseId) {
  const fixture = GENUI_FEASIBILITY_FIXTURES.find((candidate) => candidate.caseId === caseId);
  if (fixture === undefined) {
    throw new Error(`Unknown feasibility case: ${caseId}`);
  }
  return fixture;
}

export function normalizeTrustedFixture(fixture) {
  validateFixtureDeclaration(fixture);
  const sourceRows = decodeTrustedRows(fixture);
  const stableKeys = new Set();
  const rows = sourceRows.map((sourceRow, index) => {
    const keys = Object.keys(sourceRow);
    if (!arraysEqual(keys, fixture.fields)) {
      throw new Error(`Trusted row ${index + 1} fields do not match the fixture declaration`);
    }

    const values = fixture.fields.map((field) => {
      const value = sourceRow[field];
      assertJsonScalar(value, `Trusted row ${index + 1} field ${field}`);
      return Object.freeze([field, value]);
    });
    const stableKey = sourceRow[fixture.selectionKey];
    if (typeof stableKey !== 'string' || stableKey.length === 0) {
      throw new Error(`Trusted row ${index + 1} has an invalid stable key`);
    }
    if (stableKeys.has(stableKey)) {
      throw new Error(`Trusted fixture contains duplicate stable key ${stableKey}`);
    }
    stableKeys.add(stableKey);
    return Object.freeze({ stable_key: stableKey, values: Object.freeze(values) });
  });

  return Object.freeze({
    schema_version: 1,
    case_id: fixture.caseId,
    source_format: fixture.sourceFormat,
    binding: fixture.binding,
    selection_key: fixture.selectionKey,
    fields: Object.freeze([...fixture.fields]),
    rows: Object.freeze(rows),
    task_value: fixture.taskValue,
  });
}

export function normalizedDatasetJsonForFixture(fixture) {
  return JSON.stringify(normalizeTrustedFixture(fixture));
}

export function capabilitiesJsonForFixture(fixture) {
  const dataset = normalizeTrustedFixture(fixture);
  return JSON.stringify({
    bindings: [
      {
        name: dataset.binding,
        fields: dataset.fields,
        selection_keys: [dataset.selection_key],
      },
    ],
    filter_operators: FILTER_OPERATORS,
    aggregations: AGGREGATIONS,
  });
}

function validateFixtureDeclaration(fixture) {
  if (fixture === null || typeof fixture !== 'object') {
    throw new Error('Trusted fixture declaration must be an object');
  }
  for (const field of ['caseId', 'sourceFormat', 'binding', 'selectionKey']) {
    if (typeof fixture[field] !== 'string' || fixture[field].length === 0) {
      throw new Error(`Trusted fixture ${field} must be a non-empty string`);
    }
  }
  if (!['json-array', 'json-nested-items', 'restricted-csv'].includes(fixture.sourceFormat)) {
    throw new Error(`Unsupported trusted source format: ${fixture.sourceFormat}`);
  }
  if (!Array.isArray(fixture.fields) || fixture.fields.length === 0) {
    throw new Error('Trusted fixture fields must be a non-empty array');
  }
  if (fixture.fields.some((field) => typeof field !== 'string' || field.length === 0)) {
    throw new Error('Trusted fixture field names must be non-empty strings');
  }
  if (new Set(fixture.fields).size !== fixture.fields.length) {
    throw new Error('Trusted fixture field names must be unique');
  }
  if (!fixture.fields.includes(fixture.selectionKey)) {
    throw new Error('Trusted fixture selection key must be a declared field');
  }
  if (!Array.isArray(fixture.numericFields) || fixture.numericFields.some((field) => !fixture.fields.includes(field))) {
    throw new Error('Trusted fixture numeric fields must be declared fields');
  }
  assertJsonScalar(fixture.taskValue, 'Trusted fixture task value');
}

function decodeTrustedRows(fixture) {
  switch (fixture.sourceFormat) {
    case 'json-array':
      if (!Array.isArray(fixture.source)) {
        throw new Error('Trusted JSON array source must be an array');
      }
      return fixture.source;
    case 'json-nested-items':
      if (
        fixture.source === null ||
        typeof fixture.source !== 'object' ||
        Array.isArray(fixture.source) ||
        !arraysEqual(Object.keys(fixture.source), ['items']) ||
        !Array.isArray(fixture.source.items)
      ) {
        throw new Error('Trusted nested JSON source must contain exactly one items array');
      }
      return fixture.source.items;
    case 'restricted-csv':
      return decodeRestrictedCsv(fixture.source, fixture.fields, fixture.numericFields);
    default:
      throw new Error(`Unsupported trusted source format: ${fixture.sourceFormat}`);
  }
}

function decodeRestrictedCsv(source, fields, numericFields) {
  if (typeof source !== 'string' || source.includes('"')) {
    throw new Error('Restricted CSV source must be an unquoted string');
  }
  const lines = source.trimEnd().split(/\r?\n/);
  if (lines.length < 2 || !arraysEqual(lines[0].split(','), fields)) {
    throw new Error('Restricted CSV header does not match the fixture declaration');
  }

  return lines.slice(1).map((line, index) => {
    const cells = line.split(',');
    if (cells.length !== fields.length || cells.some((cell) => cell.length === 0)) {
      throw new Error(`Restricted CSV row ${index + 2} is malformed`);
    }
    return Object.fromEntries(fields.map((field, fieldIndex) => {
      if (!numericFields.includes(field)) {
        return [field, cells[fieldIndex]];
      }
      const value = Number(cells[fieldIndex]);
      if (!Number.isFinite(value)) {
        throw new Error(`Restricted CSV row ${index + 2} field ${field} is not finite`);
      }
      return [field, value];
    }));
  });
}

function assertJsonScalar(value, label) {
  const valid =
    value === null ||
    typeof value === 'string' ||
    typeof value === 'boolean' ||
    (typeof value === 'number' && Number.isFinite(value));
  if (!valid) {
    throw new Error(`${label} must be a finite JSON scalar`);
  }
}

function arraysEqual(left, right) {
  return left.length === right.length && left.every((value, index) => value === right[index]);
}

function deepFreeze(value) {
  if (value !== null && typeof value === 'object' && !Object.isFrozen(value)) {
    for (const child of Object.values(value)) {
      deepFreeze(child);
    }
    Object.freeze(value);
  }
  return value;
}
