CREATE TABLE IF NOT EXISTS commands (
  id TEXT PRIMARY KEY,            -- idempotency_key
  tool TEXT NOT NULL,
  args TEXT NOT NULL,             -- JSON canónico ya validado
  status TEXT NOT NULL DEFAULT 'pending',  -- pending | applied | rejected
  reason TEXT,
  created_at INTEGER NOT NULL,
  done_at INTEGER
);
CREATE INDEX IF NOT EXISTS commands_status ON commands(status, created_at);
CREATE TABLE IF NOT EXISTS summaries (key TEXT PRIMARY KEY, json TEXT NOT NULL, updated_at INTEGER NOT NULL);
CREATE TABLE IF NOT EXISTS audit (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  ts INTEGER NOT NULL, actor TEXT NOT NULL, tool TEXT NOT NULL, ok INTEGER NOT NULL, detail TEXT
);
