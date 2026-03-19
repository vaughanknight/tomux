#!/usr/bin/env bash
# gen-fixtures.sh — Generate reproducible SQLite test fixture databases
# Run: bash tests/fixtures/gen-fixtures.sh
set -euo pipefail
FIXTURE_DIR="$(cd "$(dirname "$0")" && pwd)"

rm -f "$FIXTURE_DIR"/*.db

# --- basic.db: 1 phase, 3 tasks (2 done, 1 in_progress) ---
sqlite3 "$FIXTURE_DIR/basic.db" <<'SQL'
CREATE TABLE phases (id TEXT PRIMARY KEY, name TEXT, ordinal INTEGER, status TEXT);
CREATE TABLE todos (id TEXT PRIMARY KEY, title TEXT NOT NULL, description TEXT,
  status TEXT DEFAULT 'pending', created_at TEXT DEFAULT (datetime('now')),
  updated_at TEXT DEFAULT (datetime('now')));
CREATE TABLE todo_deps (todo_id TEXT NOT NULL, depends_on TEXT NOT NULL, PRIMARY KEY (todo_id, depends_on));
CREATE TABLE session_state (key TEXT PRIMARY KEY, value TEXT);

INSERT INTO phases VALUES ('ph1', 'Phase 1: Core', 1, 'in_progress');
INSERT INTO todos (id, title, status) VALUES
  ('ph1-t01', 'Create helpers.sh', 'done'),
  ('ph1-t02', 'Session discovery', 'done'),
  ('ph1-t03', 'DB query layer', 'in_progress');
INSERT INTO session_state (key, value) VALUES
  ('activity', 'Implementing DB query layer'),
  ('phase_heading', 'Phase 1: Core'),
  ('phase_number', '1'),
  ('total_phases', '3'),
  ('total_tasks', '3');
SQL

# --- multiphase.db: 3 phases, mixed statuses ---
sqlite3 "$FIXTURE_DIR/multiphase.db" <<'SQL'
CREATE TABLE phases (id TEXT PRIMARY KEY, name TEXT, ordinal INTEGER, status TEXT);
CREATE TABLE todos (id TEXT PRIMARY KEY, title TEXT NOT NULL, description TEXT,
  status TEXT DEFAULT 'pending', created_at TEXT DEFAULT (datetime('now')),
  updated_at TEXT DEFAULT (datetime('now')));
CREATE TABLE todo_deps (todo_id TEXT NOT NULL, depends_on TEXT NOT NULL, PRIMARY KEY (todo_id, depends_on));
CREATE TABLE session_state (key TEXT PRIMARY KEY, value TEXT);

INSERT INTO phases VALUES
  ('ph1', 'Phase 1: Core', 1, 'done'),
  ('ph2', 'Phase 2: Rendering', 2, 'in_progress'),
  ('ph3', 'Phase 3: Integration', 3, 'pending');
INSERT INTO todos (id, title, status) VALUES
  ('ph2-t01', 'Render pips', 'done'),
  ('ph2-t02', 'Overflow logic', 'done'),
  ('ph2-t03', 'Colour mapping', 'in_progress'),
  ('ph2-t04', 'Caching', 'pending'),
  ('ph2-t05', 'Staleness', 'pending');
INSERT INTO session_state (key, value) VALUES
  ('activity', 'Implementing colour mapping'),
  ('phase_heading', 'Phase 2: Rendering'),
  ('phase_number', '2'),
  ('total_phases', '3'),
  ('total_tasks', '5');
SQL

# --- overflow.db: 1 phase, 15 tasks (tests fraction mode) ---
sqlite3 "$FIXTURE_DIR/overflow.db" <<'SQL'
CREATE TABLE phases (id TEXT PRIMARY KEY, name TEXT, ordinal INTEGER, status TEXT);
CREATE TABLE todos (id TEXT PRIMARY KEY, title TEXT NOT NULL, description TEXT,
  status TEXT DEFAULT 'pending', created_at TEXT DEFAULT (datetime('now')),
  updated_at TEXT DEFAULT (datetime('now')));
CREATE TABLE session_state (key TEXT PRIMARY KEY, value TEXT);

INSERT INTO phases VALUES ('ph1', 'Phase 1: Big Phase', 1, 'in_progress');
INSERT INTO todos (id, title, status) VALUES
  ('ph1-t01', 'Task 1', 'done'), ('ph1-t02', 'Task 2', 'done'),
  ('ph1-t03', 'Task 3', 'done'), ('ph1-t04', 'Task 4', 'done'),
  ('ph1-t05', 'Task 5', 'done'), ('ph1-t06', 'Task 6', 'done'),
  ('ph1-t07', 'Task 7', 'done'), ('ph1-t08', 'Task 8', 'in_progress'),
  ('ph1-t09', 'Task 9', 'pending'), ('ph1-t10', 'Task 10', 'pending'),
  ('ph1-t11', 'Task 11', 'pending'), ('ph1-t12', 'Task 12', 'pending'),
  ('ph1-t13', 'Task 13', 'pending'), ('ph1-t14', 'Task 14', 'pending'),
  ('ph1-t15', 'Task 15', 'blocked');
SQL

# --- flat-nophases.db: No phases table, 5 flat todos ---
sqlite3 "$FIXTURE_DIR/flat-nophases.db" <<'SQL'
CREATE TABLE todos (id TEXT PRIMARY KEY, title TEXT NOT NULL, description TEXT,
  status TEXT DEFAULT 'pending', created_at TEXT DEFAULT (datetime('now')),
  updated_at TEXT DEFAULT (datetime('now')));
CREATE TABLE session_state (key TEXT PRIMARY KEY, value TEXT);

INSERT INTO todos (id, title, status) VALUES
  ('setup-repo', 'Create repository', 'done'),
  ('setup-deps', 'Install dependencies', 'done'),
  ('impl-core', 'Implement core', 'in_progress'),
  ('impl-tests', 'Write tests', 'pending'),
  ('docs-readme', 'Write README', 'pending');
INSERT INTO session_state (key, value) VALUES
  ('activity', 'Implementing core logic');
SQL

# --- empty.db: Empty session (tables exist but no rows) ---
sqlite3 "$FIXTURE_DIR/empty.db" <<'SQL'
CREATE TABLE todos (id TEXT PRIMARY KEY, title TEXT NOT NULL, description TEXT,
  status TEXT DEFAULT 'pending', created_at TEXT DEFAULT (datetime('now')),
  updated_at TEXT DEFAULT (datetime('now')));
CREATE TABLE session_state (key TEXT PRIMARY KEY, value TEXT);
SQL

# --- session-store.db: Mock global session index ---
sqlite3 "$FIXTURE_DIR/session-store.db" <<'SQL'
CREATE TABLE sessions (id TEXT PRIMARY KEY, cwd TEXT, repository TEXT,
  branch TEXT, summary TEXT, created_at TEXT DEFAULT (datetime('now')),
  updated_at TEXT DEFAULT (datetime('now')), host_type TEXT);
CREATE INDEX idx_sessions_cwd ON sessions(cwd);

INSERT INTO sessions (id, cwd, repository, updated_at) VALUES
  ('aaaa-1111', '/home/user/project-a', 'user/project-a', '2026-03-19T10:00:00Z'),
  ('bbbb-2222', '/home/user/project-b', 'user/project-b', '2026-03-19T09:00:00Z'),
  ('cccc-3333', '/home/user/project-a/subdir', 'user/project-a', '2026-03-18T10:00:00Z');
SQL

echo "✅ Generated 6 fixture databases in $FIXTURE_DIR"
ls -la "$FIXTURE_DIR"/*.db
