import ordersFixture from './fixtures/orders.json';
import ordersCsvFixture from './fixtures/orders.csv?raw';

export type OrderStatus = 'paid' | 'pending' | 'review';

export interface OrderRow {
  readonly id: string;
  readonly name: string;
  readonly status: OrderStatus;
  readonly amount: number;
}

export interface OrderView {
  readonly query: string;
  readonly rows: readonly OrderRow[];
  readonly selected: OrderRow | null;
  readonly selectedVisible: boolean;
}

export interface OrderSummary {
  readonly count: number;
  readonly totalAmount: number;
  readonly averageAmount: number;
}

// Host-owned fixture data. The candidate can reference this binding but never
// receives ownership of the rows or the selection state.
export const ORDER_ROWS: readonly OrderRow[] = ordersFixture.map((row) => ({
  id: row.id,
  name: row.name,
  status: toOrderStatus(row.status),
  amount: row.amount,
}));

export const ORDERS_CSV_FIXTURE = ordersCsvFixture;

function toOrderStatus(value: string): OrderStatus {
  switch (value) {
    case 'paid':
    case 'pending':
    case 'review':
      return value;
    default:
      throw new Error(`Unsupported order status in fixture: ${value}`);
  }
}

/** Purely derive the visible rows from the host-owned query. */
export function filterOrders(
  rows: readonly OrderRow[],
  query: string,
): readonly OrderRow[] {
  const normalized = query.trim().toLowerCase();
  if (normalized.length === 0) return [...rows];
  return rows.filter((row) =>
    [row.id, row.name, row.status].some((value) =>
      value.toLowerCase().includes(normalized),
    ),
  );
}

/**
 * Derive the table view without changing host-owned rows or selection.
 * Selection remains valid while its row is filtered out, so clearing a filter
 * restores the same selected row instead of losing user state.
 */
export function deriveOrderView(
  rows: readonly OrderRow[],
  query: string,
  selectedId: string | null,
): OrderView {
  const visibleRows = filterOrders(rows, query);
  const selected = selectedId === null
    ? null
    : rows.find((row) => row.id === selectedId) ?? null;
  return {
    query,
    rows: visibleRows,
    selected,
    selectedVisible: selected !== null && visibleRows.some((row) => row.id === selected.id),
  };
}

/** Select only an existing host-owned row. */
export function selectOrder(
  rows: readonly OrderRow[],
  id: string,
): string | null {
  return rows.some((row) => row.id === id) ? id : null;
}

/** Derive aggregate values for the currently visible rows. */
export function summarizeOrders(rows: readonly OrderRow[]): OrderSummary {
  const totalAmount = rows.reduce((total, row) => total + row.amount, 0);
  return {
    count: rows.length,
    totalAmount,
    averageAmount: rows.length === 0 ? 0 : totalAmount / rows.length,
  };
}

/**
 * Parse the Phase 4 CSV fixture at the host boundary.
 *
 * V1 deliberately accepts the simple comma-separated fixture shape only:
 * values may not contain escaped commas or quoted fields.
 */
export function parseOrdersCsv(csv: string): readonly OrderRow[] {
  const lines = csv.trim().split(/\r?\n/).filter((line) => line.trim().length > 0);
  if (lines.length === 0 || lines[0] !== 'id,name,status,amount') {
    throw new Error('Orders CSV must start with id,name,status,amount');
  }

  return lines.slice(1).map((line, index) => {
    const columns = line.split(',');
    if (columns.length !== 4 || columns.some((column) => column.trim().length === 0)) {
      throw new Error(`Invalid orders CSV row ${index + 2}`);
    }
    const [id, name, status, amountText] = columns;
    const amount = Number(amountText);
    if (!Number.isFinite(amount)) {
      throw new Error(`Invalid order amount on CSV row ${index + 2}`);
    }
    return { id, name, status: toOrderStatus(status), amount };
  });
}
