import assert from 'node:assert/strict';
import test from 'node:test';

import { GENUI_RECIPE_SCHEMA, parseGenUiRecipe } from './genui-spike-recipe.js';

const validRecipe = {
  kind: 'filtered_orders',
  title: 'Pending orders requiring attention',
  filter: {
    field: 'status',
    operator: 'equals',
    value: 'pending',
  },
  columns: ['id', 'name', 'amount'],
  summary: {
    field: 'amount',
    aggregation: 'sum',
    label: 'Pending value',
  },
};

test('accepts the bounded filtered-orders recipe', () => {
  assert.deepEqual(parseGenUiRecipe(validRecipe), {
    ok: true,
    value: validRecipe,
  });
});

test('rejects a column outside the host field allowlist', () => {
  const result = parseGenUiRecipe({
    ...validRecipe,
    columns: ['id', 'name', 'customer_email'],
  });

  assert.equal(result.ok, false);
  assert.match(result.error, /columns/);
});

test('rejects extra properties instead of silently ignoring them', () => {
  const result = parseGenUiRecipe({
    ...validRecipe,
    answer: 'Vertex renewal and $1,540',
  });

  assert.equal(result.ok, false);
  assert.match(result.error, /properties/);
});

test('rejects unknown recipe variants', () => {
  const result = parseGenUiRecipe({
    ...validRecipe,
    kind: 'arbitrary_html',
  });

  assert.equal(result.ok, false);
  assert.match(result.error, /kind/);
});
test('rejects a filter that cannot answer the fixed pending-orders question', () => {
  const result = parseGenUiRecipe({
    ...validRecipe,
    filter: { ...validRecipe.filter, value: 'paid' },
  });

  assert.equal(result.ok, false);
  assert.match(result.error, /pending/);
});

test('rejects columns that omit an answer required by the fixed case', () => {
  for (const columns of [['name', 'amount'], ['id', 'name']]) {
    const result = parseGenUiRecipe({ ...validRecipe, columns });
    assert.equal(result.ok, false);
    assert.match(result.error, /id.*amount/);
  }
});

test('provider schema requires the fields needed for the fixed answer', () => {
  assert.deepEqual(GENUI_RECIPE_SCHEMA.properties.columns.allOf, [
    { contains: { const: 'id' } },
    { contains: { const: 'amount' } },
  ]);
});
