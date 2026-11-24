import { createRequire } from "node:module";
const { DatabaseSync } = createRequire(import.meta.url)("node:sqlite");
import { readFileSync } from "node:fs";
import type { DB, Stmt } from "../src/index";

// Adaptador mínimo node:sqlite -> interfaz D1 (para tests locales sin Cloudflare).
export function memDB(): DB {
  const db = new DatabaseSync(":memory:");
  db.exec(readFileSync(new URL("../schema.sql", import.meta.url), "utf8"));
  const mk = (sql: string, v: unknown[] = []): Stmt => ({
    bind: (...x) => mk(sql, x),
    first: async () => (db.prepare(sql).get(...(v as any[])) as any) ?? null,
    all: async () => ({ results: db.prepare(sql).all(...(v as any[])) as any[] }),
    run: async () => db.prepare(sql).run(...(v as any[])),
  });
  return { prepare: (s) => mk(s) };
}
