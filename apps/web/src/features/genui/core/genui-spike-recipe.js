const ORDER_FIELDS = new Set(['id', 'name', 'status', 'amount']);

export const GENUI_RECIPE_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['kind', 'title', 'filter', 'columns', 'summary'],
  properties: {
    kind: { const: 'filtered_orders' },
    title: { type: 'string', minLength: 1, maxLength: 80 },
    filter: {
      type: 'object',
      additionalProperties: false,
      required: ['field', 'operator', 'value'],
      properties: {
        field: { const: 'status' },
        operator: { const: 'equals' },
        value: { const: 'pending' },
      },
    },
    columns: {
      type: 'array',
      minItems: 2,
      maxItems: 4,
      uniqueItems: true,
      items: { enum: [...ORDER_FIELDS] },
      allOf: [
        { contains: { const: 'id' } },
        { contains: { const: 'amount' } },
      ],
    },
    summary: {
      type: 'object',
      additionalProperties: false,
      required: ['field', 'aggregation', 'label'],
      properties: {
        field: { const: 'amount' },
        aggregation: { const: 'sum' },
        label: { type: 'string', minLength: 1, maxLength: 40 },
      },
    },
  },
};

function isRecord(value) {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function hasExactProperties(value, expected) {
  const keys = Object.keys(value);
  return keys.length === expected.length && keys.every((key) => expected.includes(key));
}

function invalid(error) {
  return { ok: false, error };
}

export function parseGenUiRecipe(input) {
  if (!isRecord(input) || !hasExactProperties(input, ['kind', 'title', 'filter', 'columns', 'summary'])) {
    return invalid('Recipe properties do not match the allowlist.');
  }
  if (input.kind !== 'filtered_orders') {
    return invalid('Recipe kind must be filtered_orders.');
  }
  if (typeof input.title !== 'string' || input.title.trim().length === 0 || input.title.length > 80) {
    return invalid('Recipe title must contain 1–80 characters.');
  }
  if (!isRecord(input.filter) || !hasExactProperties(input.filter, ['field', 'operator', 'value'])) {
    return invalid('Recipe filter properties do not match the allowlist.');
  }
  if (input.filter.field !== 'status' || input.filter.operator !== 'equals' || input.filter.value !== 'pending') {
    return invalid('Recipe filter must select pending orders for the fixed development question.');
  }
  if (
    !Array.isArray(input.columns) ||
    input.columns.length < 2 ||
    input.columns.length > 4 ||
    !input.columns.every((field) => ORDER_FIELDS.has(field)) ||
    new Set(input.columns).size !== input.columns.length
  ) {
    return invalid('Recipe columns must contain 2–4 unique allowed order fields.');
  }
  if (!input.columns.includes('id') || !input.columns.includes('amount')) {
    return invalid('Recipe columns must include both id and amount to support the fixed development answer.');
  }
  if (!isRecord(input.summary) || !hasExactProperties(input.summary, ['field', 'aggregation', 'label'])) {
    return invalid('Recipe summary properties do not match the allowlist.');
  }
  if (
    input.summary.field !== 'amount' ||
    input.summary.aggregation !== 'sum' ||
    typeof input.summary.label !== 'string' ||
    input.summary.label.trim().length === 0 ||
    input.summary.label.length > 40
  ) {
    return invalid('Recipe summary must provide a short label for the amount sum.');
  }

  return {
    ok: true,
    value: {
      kind: input.kind,
      title: input.title.trim(),
      filter: {
        field: input.filter.field,
        operator: input.filter.operator,
        value: input.filter.value,
      },
      columns: [...input.columns],
      summary: {
        field: input.summary.field,
        aggregation: input.summary.aggregation,
        label: input.summary.label.trim(),
      },
    },
  };
}
