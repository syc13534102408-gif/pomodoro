CREATE TABLE IF NOT EXISTS sync_backups (
  device_code TEXT PRIMARY KEY,
  payload TEXT NOT NULL,
  updated_at TEXT NOT NULL
);
