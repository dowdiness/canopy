function attributeSchema(name, valueSchema) {
  return {
    type: 'object',
    additionalProperties: false,
    required: ['name', 'value'],
    properties: {
      name: { const: name },
      value: valueSchema,
    },
  };
}

function componentSchema(name, attributes, children) {
  return {
    type: 'object',
    additionalProperties: false,
    required: ['type', 'name', 'attributes', 'children'],
    properties: {
      type: { const: 'component' },
      name: { const: name },
      attributes: {
        type: 'array',
        prefixItems: attributes,
        items: false,
      },
      children,
    },
  };
}

const NON_EMPTY_STRING = { type: 'string', minLength: 1, maxLength: 1024 };
const EMPTY_CHILDREN = { type: 'array', maxItems: 0 };
const COLUMN = componentSchema(
  'column',
  [attributeSchema('field', NON_EMPTY_STRING), attributeSchema('label', NON_EMPTY_STRING)],
  EMPTY_CHILDREN,
);
const FILTER = componentSchema(
  'filter',
  [
    attributeSchema('field', NON_EMPTY_STRING),
    attributeSchema('operator', { type: 'string', enum: ['eq', 'neq', 'contains', 'gt', 'lt'] }),
  ],
  EMPTY_CHILDREN,
);
const SUMMARY = componentSchema(
  'summary',
  [
    attributeSchema('field', NON_EMPTY_STRING),
    attributeSchema('aggregation', { type: 'string', enum: ['count', 'sum', 'average', 'min', 'max'] }),
  ],
  EMPTY_CHILDREN,
);

function tableChildren(columnCount) {
  return {
    type: 'array',
    prefixItems: [
      ...Array.from({ length: columnCount }, () => ({ $ref: '#/$defs/column' })),
      { $ref: '#/$defs/filter' },
      { $ref: '#/$defs/summary' },
    ],
    items: false,
  };
}

export const GENUI_CANDIDATE_SCHEMA = deepFreeze({
  $schema: 'https://json-schema.org/draft/2020-12/schema',
  ...componentSchema(
    'stack',
    [],
    {
      type: 'array',
      prefixItems: [
        componentSchema(
          'text',
          [attributeSchema('value', NON_EMPTY_STRING)],
          EMPTY_CHILDREN,
        ),
        componentSchema(
          'table',
          [
            attributeSchema('data', NON_EMPTY_STRING),
            attributeSchema('selection', NON_EMPTY_STRING),
          ],
          {
            oneOf: [tableChildren(2), tableChildren(3), tableChildren(4)],
          },
        ),
      ],
      items: false,
    },
  ),
  $defs: {
    column: COLUMN,
    filter: FILTER,
    summary: SUMMARY,
  },
});

function deepFreeze(value) {
  if (value !== null && typeof value === 'object' && !Object.isFrozen(value)) {
    for (const child of Object.values(value)) deepFreeze(child);
    Object.freeze(value);
  }
  return value;
}
