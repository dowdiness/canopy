// SQLite-backed operation store for the dev relay server.
//
// Provides persistent storage for CRDT operations so late joiners
// can replay history even after server restarts.

import Database from "better-sqlite3";
import { join } from "path";

const DEFAULT_DB_PATH = join(import.meta.dirname ?? __dirname, "canopy-relay.db");

export interface OpStore {
  insertOp(roomId: string, op: string): void;
  getOps(roomId: string): string[];
  evictOldOps(roomId: string, maxOps: number): void;
  clearRoom(roomId: string): void;
  close(): void;
}

export function createStore(dbPath: string = DEFAULT_DB_PATH): OpStore {
  const db = new Database(dbPath);
  db.pragma("journal_mode = WAL");

  db.exec(`
    CREATE TABLE IF NOT EXISTS operations (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      room_id TEXT NOT NULL,
      data TEXT NOT NULL
    )
  `);
  db.exec(`
    CREATE INDEX IF NOT EXISTS idx_ops_room ON operations(room_id)
  `);

  const insertStmt = db.prepare(
    "INSERT INTO operations (room_id, data) VALUES (?, ?)"
  );
  const getOpsStmt = db.prepare(
    "SELECT data FROM operations WHERE room_id = ? ORDER BY id"
  );
  const countStmt = db.prepare(
    "SELECT COUNT(*) as cnt FROM operations WHERE room_id = ?"
  );
  const evictStmt = db.prepare(`
    DELETE FROM operations WHERE room_id = ? AND id <= (
      SELECT id FROM operations WHERE room_id = ? ORDER BY id
      LIMIT 1 OFFSET ?
    )
  `);
  const clearStmt = db.prepare("DELETE FROM operations WHERE room_id = ?");

  return {
    insertOp(roomId: string, op: string): void {
      insertStmt.run(roomId, typeof op === "string" ? op : JSON.stringify(op));
    },

    getOps(roomId: string): string[] {
      return (getOpsStmt.all(roomId) as { data: string }[]).map((r) => r.data);
    },

    evictOldOps(roomId: string, maxOps: number): void {
      const row = countStmt.get(roomId) as { cnt: number } | undefined;
      if (row && row.cnt > maxOps) {
        const excess = row.cnt - maxOps;
        evictStmt.run(roomId, roomId, excess - 1);
      }
    },

    clearRoom(roomId: string): void {
      clearStmt.run(roomId);
    },

    close(): void {
      db.close();
    },
  };
}
