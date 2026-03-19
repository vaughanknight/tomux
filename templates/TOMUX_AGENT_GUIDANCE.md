<!-- tomux-guidance-version: 1.0.0 -->
# Tomux Agent Guidance

> This file instructs the AI agent to create structured progress data
> that the Tomux tmux plugin can visualise. Read and follow these rules.
>
> **Reading priority:** The *Essential Contract* section is all you need.
> The *Worked Examples* and *SQL Cheat Sheet* are reference material.

---

## Essential Contract

### Table Setup (Idempotent)

Run these on **every skill entry**. The `todos` and `todo_deps` tables already
exist in the Copilot CLI session database — do **not** recreate them.

```sql
CREATE TABLE IF NOT EXISTS phases (
  id      TEXT PRIMARY KEY,   -- Short ID: 'ph1', 'research', 'clarify'
  name    TEXT,               -- Display name: 'Phase 1: Scaffold'
  ordinal INTEGER,            -- Sort order: 1, 2, 3 …
  status  TEXT DEFAULT 'pending'
    CHECK(status IN ('pending','in_progress','done','blocked'))
);

CREATE TABLE IF NOT EXISTS session_state (
  key   TEXT PRIMARY KEY,
  value TEXT
);
```

### Phase IDs

Use **short** identifiers. Tomux renders these as pips — long names waste space.

| ✅ Good | ❌ Bad |
|---------|--------|
| `ph1`, `ph2` | `plan-033-ph1` |
| `research`, `clarify` | `phase-1`, `p033` |
| `polish` | `my-long-phase-name` |

Create phases with:

```sql
INSERT INTO phases (id, name, ordinal, status)
VALUES ('ph1', 'Phase 1: Scaffold', 1, 'pending');
```

### Todo IDs

Format: **`{phase_id}-{task_id}`**

Tomux groups todos under phases by stripping the **last** hyphen-segment:

| Todo ID | → Extracted Phase |
|---------|-------------------|
| `ph1-t01` | `ph1` |
| `ph1-scaffold` | `ph1` |
| `research-ia` | `research` |
| `clarify-batch1` | `clarify` |

The prefix before the last hyphen **must** match an existing phase `id`.

### Status Values

All tables use the same four statuses:

```
pending  →  in_progress  →  done
                          →  blocked
```

Update **both** the `todos` row and the parent `phases` row as you work:

```sql
UPDATE todos  SET status = 'in_progress', updated_at = datetime('now') WHERE id = 'ph1-t01';
UPDATE phases SET status = 'in_progress' WHERE id = 'ph1';
```

When all tasks in a phase are done, mark the phase done:

```sql
UPDATE phases SET status = 'done' WHERE id = 'ph1';
```

### Session State Keys

Update these on **every skill entry** so the status bar stays current:

| Key | Example Value | Purpose |
|-----|---------------|---------|
| `activity` | `"Implementing Phase 3: Rendering"` | Current work description (shown in status bar) |
| `phase_heading` | `"Phase 3: Rendering"` | Active phase display name |
| `phase_number` | `"3"` | Active phase ordinal |
| `total_phases` | `"5"` | Total number of phases |
| `total_tasks` | `"12"` | Total tasks in the active phase |

```sql
INSERT OR REPLACE INTO session_state (key, value) VALUES
  ('activity',      'Implementing Phase 3: Rendering'),
  ('phase_heading', 'Phase 3: Rendering'),
  ('phase_number',  '3'),
  ('total_phases',  '5'),
  ('total_tasks',   '12');
```

**Activity text tips:**
- Keep it under 30 characters (truncated by `@tomux_activity_max_length`)
- Be descriptive: `"Research: 5/7 agents done"` not `"working"`

### Clean Slate Rule

When starting a **new plan or task list**, delete old data first:

```sql
DELETE FROM todos;
DELETE FROM phases;
DELETE FROM todo_deps;
DELETE FROM session_state;
```

> ⚠️ If there are **incomplete** todos (status ≠ `done`), warn the user
> before clearing: *"Clearing N incomplete tasks from previous plan."*

### Per-Phase Task Cleanup

When advancing to a new phase, **delete the previous phase's completed todos**.
The phase pip already records that the phase was done — individual task rows
are no longer needed and clutter the display.

```sql
-- Moving from ph1 → ph2: clean up ph1 tasks
DELETE FROM todos WHERE id LIKE 'ph1-%';
UPDATE phases SET status = 'done' WHERE id = 'ph1';
UPDATE phases SET status = 'in_progress' WHERE id = 'ph2';
```

---

## Worked Examples

### Example 1: Clarification Questions (Dynamic Batches)

A skill that asks the user questions in batches, adding more as needed.

```sql
-- Step 1: Setup tables (idempotent)
CREATE TABLE IF NOT EXISTS phases (id TEXT PRIMARY KEY, name TEXT, ordinal INTEGER, status TEXT DEFAULT 'pending');
CREATE TABLE IF NOT EXISTS session_state (key TEXT PRIMARY KEY, value TEXT);

-- Step 2: Clean slate
DELETE FROM todos;
DELETE FROM phases;
DELETE FROM todo_deps;

-- Step 3: Create the single phase
INSERT INTO phases (id, name, ordinal, status)
VALUES ('clarify', 'Clarification', 1, 'in_progress');

-- Step 4: First batch of questions
INSERT INTO todos (id, title, status) VALUES
  ('clarify-q01', 'Auth strategy: JWT vs session?', 'pending'),
  ('clarify-q02', 'Target Node.js version?',        'pending'),
  ('clarify-q03', 'Need WebSocket support?',         'pending');

INSERT OR REPLACE INTO session_state (key, value) VALUES
  ('activity',      'Asking 3 clarification questions'),
  ('phase_heading', 'Clarification'),
  ('phase_number',  '1'),
  ('total_phases',  '1'),
  ('total_tasks',   '3');

-- Step 5: User answers first two
UPDATE todos SET status = 'done', updated_at = datetime('now') WHERE id = 'clarify-q01';
UPDATE todos SET status = 'done', updated_at = datetime('now') WHERE id = 'clarify-q02';

-- Step 6: Answer to q03 spawns 2 follow-up questions
UPDATE todos SET status = 'done', updated_at = datetime('now') WHERE id = 'clarify-q03';

INSERT INTO todos (id, title, status) VALUES
  ('clarify-q04', 'WebSocket: binary or text frames?', 'pending'),
  ('clarify-q05', 'Need reconnection handling?',       'pending');

-- Update total_tasks to reflect new count
INSERT OR REPLACE INTO session_state (key, value) VALUES
  ('activity',    'Asking 2 follow-up questions'),
  ('total_tasks', '5');

-- Step 7: All done
UPDATE todos SET status = 'done', updated_at = datetime('now') WHERE id IN ('clarify-q04', 'clarify-q05');
UPDATE phases SET status = 'done' WHERE id = 'clarify';

INSERT OR REPLACE INTO session_state (key, value) VALUES
  ('activity', 'Clarification complete');
```

**Tomux displays:** `■■■□□` → `■■■■■` (5 blue pips filling in as questions resolve)

---

### Example 2: Parallel Research Subagents

A skill that launches 7 explore agents in parallel across 3 phases.

```sql
-- Step 1: Setup & clean slate
CREATE TABLE IF NOT EXISTS phases (id TEXT PRIMARY KEY, name TEXT, ordinal INTEGER, status TEXT DEFAULT 'pending');
CREATE TABLE IF NOT EXISTS session_state (key TEXT PRIMARY KEY, value TEXT);
DELETE FROM todos;
DELETE FROM phases;
DELETE FROM todo_deps;

-- Step 2: Create 3 phases
INSERT INTO phases (id, name, ordinal, status) VALUES
  ('setup',     'Setup',     1, 'done'),
  ('research',  'Research',  2, 'in_progress'),
  ('synthesis', 'Synthesis', 3, 'pending');

-- Step 3: Create 7 research agent todos — all launched simultaneously
INSERT INTO todos (id, title, status) VALUES
  ('research-auth',    'Research: auth patterns',      'in_progress'),
  ('research-db',      'Research: database schema',    'in_progress'),
  ('research-api',     'Research: API conventions',    'in_progress'),
  ('research-testing', 'Research: test infrastructure','in_progress'),
  ('research-deploy',  'Research: deployment setup',   'in_progress'),
  ('research-perf',    'Research: performance budget', 'in_progress'),
  ('research-sec',     'Research: security audit',     'in_progress');

INSERT OR REPLACE INTO session_state (key, value) VALUES
  ('activity',      'Research: 0/7 agents complete'),
  ('phase_heading', 'Research'),
  ('phase_number',  '2'),
  ('total_phases',  '3'),
  ('total_tasks',   '7');

-- Step 4: Agents complete one by one
UPDATE todos SET status = 'done', updated_at = datetime('now') WHERE id = 'research-db';
INSERT OR REPLACE INTO session_state (key, value) VALUES ('activity', 'Research: 1/7 agents complete');

UPDATE todos SET status = 'done', updated_at = datetime('now') WHERE id = 'research-auth';
INSERT OR REPLACE INTO session_state (key, value) VALUES ('activity', 'Research: 2/7 agents complete');

-- ... repeat for each agent ...

UPDATE todos SET status = 'done', updated_at = datetime('now') WHERE id = 'research-sec';
INSERT OR REPLACE INTO session_state (key, value) VALUES ('activity', 'Research: 7/7 agents complete');

-- Step 5: Move to synthesis phase (clean up research tasks)
DELETE FROM todos WHERE id LIKE 'research-%';
UPDATE phases SET status = 'done' WHERE id = 'research';
UPDATE phases SET status = 'in_progress' WHERE id = 'synthesis';

INSERT INTO todos (id, title, status) VALUES
  ('synthesis-t01', 'Compile findings', 'in_progress');

INSERT OR REPLACE INTO session_state (key, value) VALUES
  ('activity',      'Synthesising research'),
  ('phase_heading', 'Synthesis'),
  ('phase_number',  '3'),
  ('total_tasks',   '1');
```

**Tomux displays:** `■●○ ●●●●●●●` → `■■○ ■■■■■■■` → `■■● □` (phases fill, then tasks)

---

### Example 3: Multi-Phase Plan Implementation

A typical 5-phase feature implementation.

```sql
-- Step 1: Setup & clean slate
CREATE TABLE IF NOT EXISTS phases (id TEXT PRIMARY KEY, name TEXT, ordinal INTEGER, status TEXT DEFAULT 'pending');
CREATE TABLE IF NOT EXISTS session_state (key TEXT PRIMARY KEY, value TEXT);
DELETE FROM todos;
DELETE FROM phases;
DELETE FROM todo_deps;

-- Step 2: Create all 5 phases upfront
INSERT INTO phases (id, name, ordinal, status) VALUES
  ('ph1', 'Scaffold',       1, 'pending'),
  ('ph2', 'Core Logic',     2, 'pending'),
  ('ph3', 'API Routes',     3, 'pending'),
  ('ph4', 'Tests',          4, 'pending'),
  ('ph5', 'Documentation',  5, 'pending');

INSERT OR REPLACE INTO session_state (key, value) VALUES
  ('activity',      'Starting Phase 1: Scaffold'),
  ('phase_heading', 'Phase 1: Scaffold'),
  ('phase_number',  '1'),
  ('total_phases',  '5'),
  ('total_tasks',   '3');

-- Step 3: Phase 1 tasks
UPDATE phases SET status = 'in_progress' WHERE id = 'ph1';

INSERT INTO todos (id, title, status) VALUES
  ('ph1-t01', 'Create project structure',  'pending'),
  ('ph1-t02', 'Install dependencies',      'pending'),
  ('ph1-t03', 'Configure build toolchain', 'pending');

-- Step 4: Work through Phase 1
UPDATE todos SET status = 'in_progress', updated_at = datetime('now') WHERE id = 'ph1-t01';
UPDATE todos SET status = 'done',        updated_at = datetime('now') WHERE id = 'ph1-t01';
UPDATE todos SET status = 'in_progress', updated_at = datetime('now') WHERE id = 'ph1-t02';
UPDATE todos SET status = 'done',        updated_at = datetime('now') WHERE id = 'ph1-t02';
UPDATE todos SET status = 'in_progress', updated_at = datetime('now') WHERE id = 'ph1-t03';
UPDATE todos SET status = 'done',        updated_at = datetime('now') WHERE id = 'ph1-t03';

-- Step 5: Advance to Phase 2 (per-phase cleanup)
DELETE FROM todos WHERE id LIKE 'ph1-%';
UPDATE phases SET status = 'done' WHERE id = 'ph1';
UPDATE phases SET status = 'in_progress' WHERE id = 'ph2';

INSERT INTO todos (id, title, status) VALUES
  ('ph2-t01', 'Implement data models',    'pending'),
  ('ph2-t02', 'Add business logic',       'pending'),
  ('ph2-t03', 'Wire up event handlers',   'pending'),
  ('ph2-t04', 'Add error handling',       'pending');

INSERT OR REPLACE INTO session_state (key, value) VALUES
  ('activity',      'Implementing Phase 2: Core Logic'),
  ('phase_heading', 'Phase 2: Core Logic'),
  ('phase_number',  '2'),
  ('total_tasks',   '4');

-- Step 6: Work through Phase 2 ...
-- (same pattern: update todo status, then advance phase)

-- Step 7: Continue through Phases 3-5 with the same pattern:
--   1. Delete previous phase's todos
--   2. Mark previous phase 'done'
--   3. Mark current phase 'in_progress'
--   4. INSERT current phase's todos
--   5. UPDATE session_state
--   6. Work through todos
```

**Tomux displays at Phase 2:** `■●□□□ ■■□□` (1 phase done, 1 in-progress, 3 pending; 2/4 tasks done)

---

## SQL Cheat Sheet

### Tables Setup

```sql
CREATE TABLE IF NOT EXISTS phases (
  id TEXT PRIMARY KEY, name TEXT, ordinal INTEGER,
  status TEXT DEFAULT 'pending' CHECK(status IN ('pending','in_progress','done','blocked'))
);
CREATE TABLE IF NOT EXISTS session_state (key TEXT PRIMARY KEY, value TEXT);
```

### Insert Phase

```sql
INSERT INTO phases (id, name, ordinal, status)
VALUES ('ph1', 'Phase 1: Scaffold', 1, 'pending');
```

### Insert Todo

```sql
INSERT INTO todos (id, title, description, status)
VALUES ('ph1-t01', 'Create project structure', 'Set up src/ dir with index.ts', 'pending');
```

### Insert Dependency

```sql
INSERT INTO todo_deps (todo_id, depends_on) VALUES ('ph2-t01', 'ph1-t03');
```

### Update Status

```sql
UPDATE todos  SET status = 'in_progress', updated_at = datetime('now') WHERE id = 'ph1-t01';
UPDATE todos  SET status = 'done',        updated_at = datetime('now') WHERE id = 'ph1-t01';
UPDATE phases SET status = 'done' WHERE id = 'ph1';
```

### Update Session State

```sql
INSERT OR REPLACE INTO session_state (key, value) VALUES ('activity', 'Working on auth');
```

### Clean Slate

```sql
DELETE FROM todos;
DELETE FROM phases;
DELETE FROM todo_deps;
DELETE FROM session_state;
```

### Per-Phase Cleanup

```sql
DELETE FROM todos WHERE id LIKE 'ph1-%';
```

### Query Ready Todos (No Pending Dependencies)

```sql
SELECT t.* FROM todos t
WHERE t.status = 'pending'
AND NOT EXISTS (
  SELECT 1 FROM todo_deps td
  JOIN todos dep ON td.depends_on = dep.id
  WHERE td.todo_id = t.id AND dep.status != 'done'
);
```
