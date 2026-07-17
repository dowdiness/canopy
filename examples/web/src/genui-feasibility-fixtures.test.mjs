import assert from 'node:assert/strict';
import test from 'node:test';

import {
  GENUI_FEASIBILITY_FIXTURES,
  capabilitiesJsonForFixture,
  getFeasibilityFixture,
  normalizeTrustedFixture,
  normalizedDatasetJsonForFixture,
} from './genui-feasibility-fixtures.js';
import {
  getRecordedFeasibilityCandidate,
  recordedFeasibilityCandidateJson,
} from './genui-recorded-candidates.js';

const CASES = [
  {
    caseId: 'orders-pending-attention',
    sourceFormat: 'json-array',
    binding: 'orders',
    selectionKey: 'id',
    fields: ['id', 'name', 'status', 'amount'],
    taskValue: 'pending',
    stableKeys: ['ord-1001', 'ord-1002', 'ord-1003', 'ord-1004', 'ord-1005', 'ord-1006'],
  },
  {
    caseId: 'inventory-low-stock',
    sourceFormat: 'json-nested-items',
    binding: 'inventory',
    selectionKey: 'sku',
    fields: ['sku', 'product', 'category', 'on_hand'],
    taskValue: 10,
    stableKeys: ['sku-001', 'sku-002', 'sku-003', 'sku-004'],
  },
  {
    caseId: 'incidents-critical-resolution',
    sourceFormat: 'restricted-csv',
    binding: 'incidents',
    selectionKey: 'incident_id',
    fields: ['incident_id', 'service', 'severity', 'resolution_minutes'],
    taskValue: 'critical',
    stableKeys: ['inc-001', 'inc-002', 'inc-003', 'inc-004'],
  },
];

test('freezes exactly three feasibility fixture contracts', () => {
  assert.equal(Object.isFrozen(GENUI_FEASIBILITY_FIXTURES), true);
  assert.deepEqual(GENUI_FEASIBILITY_FIXTURES.map((fixture) => fixture.caseId), CASES.map((entry) => entry.caseId));

  for (const expected of CASES) {
    const fixture = getFeasibilityFixture(expected.caseId);
    assert.equal(fixture.sourceFormat, expected.sourceFormat);
    assert.equal(fixture.binding, expected.binding);
    assert.equal(fixture.selectionKey, expected.selectionKey);
    assert.deepEqual(fixture.fields, expected.fields);
    assert.equal(fixture.taskValue, expected.taskValue);
    assert.equal(Object.isFrozen(fixture), true);
    assert.equal(Object.isFrozen(fixture.fields), true);
  }
});

test('normalizes each trusted source into the exact ordered dataset wire shape', () => {
  for (const expected of CASES) {
    const fixture = getFeasibilityFixture(expected.caseId);
    const dataset = JSON.parse(normalizedDatasetJsonForFixture(fixture));

    assert.deepEqual(Object.keys(dataset), [
      'schema_version',
      'case_id',
      'source_format',
      'binding',
      'selection_key',
      'fields',
      'rows',
      'task_value',
    ]);
    assert.equal(dataset.schema_version, 1);
    assert.equal(dataset.case_id, expected.caseId);
    assert.equal(dataset.source_format, expected.sourceFormat);
    assert.equal(dataset.binding, expected.binding);
    assert.equal(dataset.selection_key, expected.selectionKey);
    assert.deepEqual(dataset.fields, expected.fields);
    assert.deepEqual(dataset.rows.map((row) => row.stable_key), expected.stableKeys);
    assert.deepEqual(dataset.rows.map((row) => row.values.map(([field]) => field)), expected.stableKeys.map(() => expected.fields));
    assert.equal(dataset.task_value, expected.taskValue);
    assert.equal(dataset.rows.every((row) => row.values.find(([field]) => field === expected.selectionKey)[1] === row.stable_key), true);
  }
});

test('preserves native JSON scalars and freezes normalized values', () => {
  const inventory = normalizeTrustedFixture(getFeasibilityFixture('inventory-low-stock'));
  const firstValues = Object.fromEntries(inventory.rows[0].values);

  assert.equal(typeof firstValues.on_hand, 'number');
  assert.equal(firstValues.on_hand, 4);
  assert.equal(Object.isFrozen(inventory), true);
  assert.equal(Object.isFrozen(inventory.rows), true);
  assert.equal(Object.isFrozen(inventory.rows[0].values), true);
});

test('derives capabilities exactly from the normalized dataset declaration', () => {
  for (const expected of CASES) {
    const fixture = getFeasibilityFixture(expected.caseId);
    assert.deepEqual(JSON.parse(capabilitiesJsonForFixture(fixture)), {
      bindings: [
        {
          name: expected.binding,
          fields: expected.fields,
          selection_keys: [expected.selectionKey],
        },
      ],
      filter_operators: ['eq', 'lt'],
      aggregations: ['count', 'sum', 'average', 'min', 'max'],
    });
  }
});

test('rejects unknown case IDs', () => {
  assert.throws(() => getFeasibilityFixture('missing-case'), /Unknown feasibility case/);
});

test('rejects malformed trusted rows before candidate interpretation', () => {
  const base = getFeasibilityFixture('orders-pending-attention');
  const cases = [
    { ...base, source: [{ id: 'ord-1', name: 'A', status: 'pending' }] },
    { ...base, source: [{ id: 'ord-1', name: 'A', status: 'pending', amount: 1, extra: true }] },
    { ...base, source: [{ id: 'ord-1', name: 'A', status: 'pending', amount: Number.POSITIVE_INFINITY }] },
    { ...base, source: [{ id: '', name: 'A', status: 'pending', amount: 1 }] },
    {
      ...base,
      source: [
        { id: 'ord-1', name: 'A', status: 'pending', amount: 1 },
        { id: 'ord-1', name: 'B', status: 'paid', amount: 2 },
      ],
    },
    { ...base, selectionKey: 'missing' },
    { ...base, fields: ['name', 'id', 'status', 'amount'] },
  ];

  for (const fixture of cases) {
    assert.throws(() => normalizeTrustedFixture(fixture));
  }
});

test('restricted CSV rejects quoting and malformed rows', () => {
  const base = getFeasibilityFixture('incidents-critical-resolution');
  const cases = [
    { ...base, source: 'incident_id,service,severity,resolution_minutes\n"inc-1",api,critical,10\n' },
    { ...base, source: 'incident_id,service,severity,resolution_minutes\ninc-1,api,critical\n' },
    { ...base, source: 'incident_id,service,severity,resolution_minutes\ninc-1,api,critical,NaN\n' },
    { ...base, source: 'service,incident_id,severity,resolution_minutes\napi,inc-1,critical,10\n' },
  ];

  for (const fixture of cases) {
    assert.throws(() => normalizeTrustedFixture(fixture));
  }
});

test('recorded controls use the frozen direct Stack/Text/Table shape', () => {
  const expectations = [
    ['orders-pending-attention', 'orders', 'id', ['id', 'name', 'amount'], 'status', 'eq', 'amount', 'sum'],
    ['inventory-low-stock', 'inventory', 'sku', ['sku', 'product', 'on_hand'], 'on_hand', 'lt', 'on_hand', 'sum'],
    ['incidents-critical-resolution', 'incidents', 'incident_id', ['incident_id', 'service', 'resolution_minutes'], 'severity', 'eq', 'resolution_minutes', 'average'],
  ];

  for (const [caseId, binding, selectionKey, fields, filterField, operator, summaryField, aggregation] of expectations) {
    const candidate = getRecordedFeasibilityCandidate(caseId);
    assert.equal(Object.isFrozen(candidate), true);
    assert.equal(candidate.name, 'stack');
    assert.deepEqual(candidate.attributes, []);
    assert.equal(candidate.children.length, 2);
    assert.deepEqual(candidate.children[0], {
      type: 'component',
      name: 'text',
      attributes: [{ name: 'value', value: candidate.children[0].attributes[0].value }],
      children: [],
    });

    const table = candidate.children[1];
    assert.equal(table.name, 'table');
    assert.deepEqual(table.attributes, [
      { name: 'data', value: binding },
      { name: 'selection', value: selectionKey },
    ]);
    assert.deepEqual(
      table.children.filter((child) => child.name === 'column').map((column) => column.attributes[0].value),
      fields,
    );
    assert.deepEqual(table.children.at(-2), {
      type: 'component',
      name: 'filter',
      attributes: [
        { name: 'field', value: filterField },
        { name: 'operator', value: operator },
      ],
      children: [],
    });
    assert.deepEqual(table.children.at(-1), {
      type: 'component',
      name: 'summary',
      attributes: [
        { name: 'field', value: summaryField },
        { name: 'aggregation', value: aggregation },
      ],
      children: [],
    });
    assert.deepEqual(JSON.parse(recordedFeasibilityCandidateJson(caseId)), candidate);
  }
});

test('recorded controls reject unknown cases', () => {
  assert.throws(() => getRecordedFeasibilityCandidate('missing-case'), /Unknown recorded feasibility candidate/);
});
