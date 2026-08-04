function attribute(name, value) {
  return { name, value };
}

function component(name, attributes = [], children = []) {
  return { type: 'component', name, attributes, children };
}

function column(field, label) {
  return component('column', [attribute('field', field), attribute('label', label)]);
}

function recordedCandidate(title, binding, selectionKey, columns, filter, summary) {
  return deepFreeze(component('stack', [], [
    component('text', [attribute('value', title)]),
    component(
      'table',
      [attribute('data', binding), attribute('selection', selectionKey)],
      [
        ...columns.map(([field, label]) => column(field, label)),
        component('filter', [attribute('field', filter.field), attribute('operator', filter.operator)]),
        component('summary', [attribute('field', summary.field), attribute('aggregation', summary.aggregation)]),
      ],
    ),
  ]));
}

export const RECORDED_FEASIBILITY_CANDIDATES = Object.freeze({
  'orders-pending-attention': recordedCandidate(
    'Pending orders requiring attention',
    'orders',
    'id',
    [['id', 'Order'], ['name', 'Customer'], ['amount', 'Amount']],
    { field: 'status', operator: 'eq' },
    { field: 'amount', aggregation: 'sum' },
  ),
  'inventory-low-stock': recordedCandidate(
    'Inventory below reorder threshold',
    'inventory',
    'sku',
    [['sku', 'SKU'], ['product', 'Product'], ['on_hand', 'On hand']],
    { field: 'on_hand', operator: 'lt' },
    { field: 'on_hand', aggregation: 'sum' },
  ),
  'incidents-critical-resolution': recordedCandidate(
    'Critical incident resolution',
    'incidents',
    'incident_id',
    [['incident_id', 'Incident'], ['service', 'Service'], ['resolution_minutes', 'Resolution minutes']],
    { field: 'severity', operator: 'eq' },
    { field: 'resolution_minutes', aggregation: 'average' },
  ),
});

export function getRecordedFeasibilityCandidate(caseId) {
  const candidate = RECORDED_FEASIBILITY_CANDIDATES[caseId];
  if (candidate === undefined) {
    throw new Error(`Unknown recorded feasibility candidate: ${caseId}`);
  }
  return candidate;
}

export function recordedFeasibilityCandidateJson(caseId) {
  return JSON.stringify(getRecordedFeasibilityCandidate(caseId));
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
