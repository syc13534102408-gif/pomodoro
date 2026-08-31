CREATE TABLE IF NOT EXISTS sync_backups (
  device_code TEXT PRIMARY KEY,
  payload TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

-- 诊断用：记录 Worker 收到的每一次请求，便于排查路由匹配问题。
CREATE TABLE IF NOT EXISTS request_log (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  ts TEXT NOT NULL,
  method TEXT,
  path TEXT,
  status INTEGER,
  origin TEXT,
  ua TEXT
);
