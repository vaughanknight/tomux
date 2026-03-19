# Workshop: Agent Guidance Contract

**Type**: Data Model + Integration Pattern
**Plan**: 001-tmux-progress-plugin
**Spec**: [tmux-progress-plugin-spec.md](../tmux-progress-plugin-spec.md)
**Created**: 2026-03-19
**Status**: Draft
**Version**: 1.0.0

**Related Documents**:
- [Research Dossier §5 — Agent Guidance Contract](../research-dossier.md)
- [trex ADR-0014 — Session State System](../../../../GitHub/trex/docs/adr/0014-session-state-system.md)
- [trex session-state-apply.md](../../../../GitHub/trex/scripts/session-state-apply.md)

---

## Purpose

Define the precise data contract between the Copilot CLI agent (the writer) and the Tomux tmux plugin (the reader). This contract governs how the agent creates, updates, and cleans up todo/phase/session_state data so that Tomux can render meaningful progress visualisations.

Getting this contract wrong means either: (a) the agent writes data Tomux can't parse → blank display, or (b) stale/orphaned data accumulates → misleading display.

## Key Questions Addressed

1. What exact SQL should agents execute at each lifecycle point?
2. How should batch operations (20 questions) be structured as todos?
3. How should parallel subagent work be tracked?
4. Should the guidance file be a skill/command or documentation?
5. When and how should old todos be cleaned up?
6. How should Tomux handle stale data from crashed sessions?
7. How do we version the contract for forward compatibility?
8. What naming convention enables automatic phase grouping?

---

## 1. Contract Overview

```
┌─────────────────────────────────────────────────────────┐
│  TOMUX_AGENT_GUIDANCE.md  (in project root)             │
│  ┌───────────────────────────────────────────────────┐  │
│  │  Essential Contract (v1.0.0)                      │  │
│  │  • Table schemas                                  │  │
│  │  • ID naming rules                                │  │
│  │  • Status values                                  │  │
│  │  • Cleanup rules                                  │  │
│  └───────────────────────────────────────────────────┘  │
│  ┌───────────────────────────────────────────────────┐  │
│  │  Worked Examples (optional reading)               │  │
│  │  • 20 Questions workflow                          │  │
│  │  • Parallel Subagents workflow                    │  │
│  │  • Multi-Phase Plan workflow                      │  │
│  └───────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────┘
          │ reads                          │ reads
          ▼                                ▼
┌──────────────────┐            ┌──────────────────────┐
│  Copilot CLI      │──writes──▶│  session.db          │
│  (agent)          │           │  • todos             │
│                   │           │  • phases            │
│  Skills invoke    │           │  • session_state     │
│  /tomux-init      │           │  • todo_deps         │
│  once per project │           └──────────┬───────────┘
└──────────────────┘                       │ reads (only)
                                           ▼
                                ┌──────────────────────┐
                                │  Tomux Plugin         │
                                │  (bash + sqlite3)     │
                                │  • status bar pips    │
                                │  • detail pane        │
                                └──────────────────────┘
```

### Data Flow Rules

| Rule | Description |
|------|-------------|
| **R-1** | Tomux NEVER writes to the session database |
| **R-2** | Agent creates/updates data following the contract in TOMUX_AGENT_GUIDANCE.md |
| **R-3** | Phase status is read from the `phases` table (agent maintains it) |
| **R-4** | Task progress is read from the `todos` table |
| **R-5** | Live context (activity, current skill) is read from `session_state` |
| **R-6** | Phase grouping requires the `phases` table — without it, todos display flat |
| **R-7** | Old todos are DELETEd when a new plan starts (clean slate) |
| **R-8** | Agent warns user if clearing incomplete todos (status bar flash) |

---

## 2. Table Schemas

### 2.1 Required Tables

These tables are created by the Copilot CLI automatically. The agent should verify they exist via `CREATE TABLE IF NOT EXISTS`.

```sql
-- Already created by Copilot CLI
CREATE TABLE IF NOT EXISTS todos (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  description TEXT,
  status TEXT DEFAULT 'pending'
    CHECK(status IN ('pending', 'in_progress', 'done', 'blocked')),
  created_at TEXT DEFAULT (datetime('now')),
  updated_at TEXT DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS todo_deps (
  todo_id TEXT NOT NULL,
  depends_on TEXT NOT NULL,
  PRIMARY KEY (todo_id, depends_on),
  FOREIGN KEY (todo_id) REFERENCES todos(id),
  FOREIGN KEY (depends_on) REFERENCES todos(id)
);
```

### 2.2 Tomux-Enhanced Tables

These tables are created by the agent when it reads TOMUX_AGENT_GUIDANCE.md. They enable phase grouping and live context display.

```sql
-- Agent creates these on first use (idempotent)
CREATE TABLE IF NOT EXISTS phases (
  id TEXT PRIMARY KEY,       -- Short ID: 'ph1', 'ph2', 'research'
  name TEXT,                 -- Display name: 'Phase 1: Scaffold'
  ordinal INTEGER,           -- Sort order: 1, 2, 3...
  status TEXT DEFAULT 'pending'
    CHECK(status IN ('pending', 'in_progress', 'done', 'blocked'))
);

CREATE TABLE IF NOT EXISTS session_state (
  key TEXT PRIMARY KEY,
  value TEXT
);
```

### 2.3 Status Values

| Status | Meaning | Pip Colour |
|--------|---------|-----------|
| `pending` | Not yet started | Empty (default fg) |
| `in_progress` | Actively being worked | Amber (colour214) |
| `done` | Completed | Green (phases) / Blue (tasks) |
| `blocked` | Blocked on dependency or external factor | Red |

---

## 3. ID Naming Convention

### 3.1 Phase IDs

```
✅ CORRECT: 'ph1', 'ph2', 'research', 'clarify', 'polish'
❌ WRONG:   'plan-033-ph1', 'phase-1', 'p033'
```

Phase IDs MUST be short. They appear in todo ID prefixes.

### 3.2 Todo IDs

```
✅ CORRECT: 'ph1-t01', 'ph1-scaffold', 'research-ia', 'clarify-batch1'
❌ WRONG:   't01', 'task-1', 'my-task' (no phase prefix → flat display)
```

**Format**: `{phase_id}-{task_identifier}`

The phase prefix is extracted by stripping the LAST `-segment`:
```
'ph1-t01'       → phase 'ph1'
'research-ia'   → phase 'research'
'clarify-batch1' → phase 'clarify'
```

### 3.3 Grouping Rule

**Tomux groups todos into phases ONLY when the `phases` table exists and contains matching phase IDs.** Without a phases table, all todos display as flat pips (no phase grouping).

This means:
- Projects with TOMUX_AGENT_GUIDANCE.md → agent creates phases → grouped display
- Projects WITHOUT guidance → agent writes plain todos → flat display (still works!)
- A hint appears: `tomux: add TOMUX_AGENT_GUIDANCE.md for phase grouping`

---

## 4. Session State Keys

| Key | Example Value | Purpose | Who Sets |
|-----|---------------|---------|----------|
| `current_skill` | `plan-6` | Active skill/command | Agent (on skill entry) |
| `workflow_phase` | `Execution` | Human-readable workflow stage | Agent (on skill entry) |
| `status` | `in_progress` | Current execution status | Agent |
| `activity` | `Implementing phase 3` | Free-text for display | Agent |
| `plan_name` | `Tomux Plugin` | Active plan title | Agent (on plan start) |
| `phase_heading` | `Phase 3: Rendering` | Active phase display name | Agent |
| `phase_number` | `3` | Active phase ordinal | Agent |
| `total_phases` | `5` | Total phase count | Agent |
| `total_tasks` | `12` | Total tasks in active phase | Agent |

**Tomux reads**: `activity`, `phase_heading`, `phase_number`, `total_phases`, `total_tasks`
**Tomux ignores**: `current_skill`, `workflow_phase`, `status` (these are for trex/other tools)

### 4.1 Activity Display

The `activity` value appears in the status bar when `@tomux_show_activity` is enabled. Agents should write descriptive but concise values.

Tomux truncates to `@tomux_activity_max_length` (default: 30 chars).

```
✅ GOOD: 'Implementing Phase 3: Rendering'
✅ GOOD: 'Asking 20 clarification questions'
✅ GOOD: 'Research: 5/7 agents complete'
❌ BAD:  'im' (too short to be useful)
❌ BAD:  'Currently implementing phase 3 of the tomux progress...' (too long, gets truncated)
```

---

## 5. Lifecycle Operations

### 5.1 Clean Slate (New Plan)

When the agent starts a new plan or a new set of work, it MUST clear old data first.

```sql
-- Step 1: Check if old incomplete todos exist
SELECT COUNT(*) FROM todos WHERE status NOT IN ('done', 'blocked');

-- Step 2a: If incomplete todos exist → warn user (flash in status bar)
--   Agent says: "⚠ Clearing 8 incomplete todos from previous plan."
--   Then update session_state to trigger the flash:
INSERT OR REPLACE INTO session_state (key, value)
  VALUES ('tomux_warning', 'Clearing 8 incomplete todos');

-- Step 2b: Clear everything
DELETE FROM todo_deps;
DELETE FROM todos;
DELETE FROM phases;

-- Step 3: Create new phases
INSERT INTO phases (id, name, ordinal, status) VALUES
  ('ph1', 'Phase 1: Core Infrastructure', 1, 'pending'),
  ('ph2', 'Phase 2: Status Bar Rendering', 2, 'pending'),
  ('ph3', 'Phase 3: TPM Integration', 3, 'pending');

-- Step 4: Create new todos
INSERT INTO todos (id, title, status) VALUES
  ('ph1-t01', 'Create helpers.sh', 'pending'),
  ('ph1-t02', 'Implement session discovery', 'pending'),
  ('ph1-t03', 'Build DB query layer', 'pending'),
  ('ph2-t01', 'Implement pip rendering', 'pending'),
  ('ph2-t02', 'Add overflow logic', 'pending');

-- Step 5: Update session_state context
INSERT OR REPLACE INTO session_state (key, value) VALUES
  ('plan_name', 'Tomux Progress Plugin'),
  ('phase_heading', 'Phase 1: Core Infrastructure'),
  ('phase_number', '1'),
  ('total_phases', '3'),
  ('total_tasks', '3'),
  ('activity', 'Starting Phase 1: Core Infrastructure');
```

### 5.2 Task Progress

As the agent works through tasks:

```sql
-- Starting a task
UPDATE todos SET status = 'in_progress', updated_at = datetime('now')
  WHERE id = 'ph1-t01';
UPDATE phases SET status = 'in_progress' WHERE id = 'ph1';
INSERT OR REPLACE INTO session_state (key, value)
  VALUES ('activity', 'Creating helpers.sh');

-- Completing a task
UPDATE todos SET status = 'done', updated_at = datetime('now')
  WHERE id = 'ph1-t01';

-- Completing a phase (all tasks done)
UPDATE phases SET status = 'done' WHERE id = 'ph1';
UPDATE phases SET status = 'in_progress' WHERE id = 'ph2';
INSERT OR REPLACE INTO session_state (key, value) VALUES
  ('phase_heading', 'Phase 2: Status Bar Rendering'),
  ('phase_number', '2'),
  ('total_tasks', '2'),
  ('activity', 'Starting Phase 2: Status Bar Rendering');

-- Blocking a task
UPDATE todos SET status = 'blocked', updated_at = datetime('now')
  WHERE id = 'ph2-t02';
```

### 5.3 Dynamic Growth

When new todos emerge mid-plan (e.g., user's answers spawn more questions):

```sql
-- Add new batch todos to existing phase
INSERT INTO todos (id, title, status) VALUES
  ('clarify-batch5', 'Follow-up: Architecture details (Q21-25)', 'pending'),
  ('clarify-batch6', 'Follow-up: Platform concerns (Q26-30)', 'pending');

-- Update session_state to reflect new total
INSERT OR REPLACE INTO session_state (key, value)
  VALUES ('total_tasks', '6');

-- Pips auto-update: was ■■■■□ (4 batches), now ■■■■□□ (6 batches)
```

---

## 6. Worked Examples

### Workflow 1: "20 Questions" Clarification

The agent needs to ask the user 20 clarification questions, grouped into batches.

```
┌─────────────────────────────────────────────────────────┐
│ STEP 1: Agent creates phase + batch todos               │
│                                                         │
│   phases: ('clarify', 'Clarification', 1, 'pending')   │
│   todos:  clarify-batch1  'Scope (Q1-5)'    pending    │
│           clarify-batch2  'UI (Q6-10)'      pending    │
│           clarify-batch3  'Data (Q11-15)'   pending    │
│           clarify-batch4  'Platform (Q16-20)' pending  │
│                                                         │
│   Status bar: □□□□                                      │
└─────────────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────┐
│ STEP 2: Agent asks batch 1 (Q1-5)                       │
│                                                         │
│   UPDATE todos SET status='in_progress'                 │
│     WHERE id='clarify-batch1';                          │
│   UPDATE phases SET status='in_progress'                │
│     WHERE id='clarify';                                 │
│                                                         │
│   Status bar: ■□□□  (1 amber, 3 empty)                  │
└─────────────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────┐
│ STEP 3: User answers → batch 1 done                     │
│                                                         │
│   UPDATE todos SET status='done'                        │
│     WHERE id='clarify-batch1';                          │
│                                                         │
│   Status bar: ■□□□  (1 blue, 3 empty)                   │
└─────────────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────┐
│ STEP 4: Answers spawn 2 more batches                    │
│                                                         │
│   INSERT INTO todos (id, title, status) VALUES          │
│     ('clarify-batch5', 'Follow-up (Q21-25)', 'pending'),│
│     ('clarify-batch6', 'Follow-up (Q26-30)', 'pending');│
│   UPDATE session_state SET value='6'                    │
│     WHERE key='total_tasks';                            │
│                                                         │
│   Status bar: ■□□□□□  (1 done, 5 pending — grew!)      │
└─────────────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────┐
│ STEP 5: Continue through remaining batches              │
│                                                         │
│   Status bar progression:                               │
│   ■■□□□□ → ■■■□□□ → ■■■■□□ → ■■■■■□ → ■■■■■■          │
│                                                         │
│   Phase: ■  (done when all batches complete)            │
└─────────────────────────────────────────────────────────┘
```

### Workflow 2: "7 Parallel Research Subagents"

The agent launches 7 explore agents to research different aspects, then synthesises findings.

```
┌─────────────────────────────────────────────────────────┐
│ STEP 1: Agent creates 3 phases                          │
│                                                         │
│   phases: ('setup', 'Setup', 1, 'pending')              │
│           ('research', 'Research', 2, 'pending')        │
│           ('synthesis', 'Synthesis', 3, 'pending')      │
│                                                         │
│   todos:  setup-prep     'Prepare prompts'   pending    │
│           research-ia    'Process tree (IA)'  pending   │
│           research-dc    'DB schema (DC)'     pending   │
│           research-ps    'Viz patterns (PS)'  pending   │
│           research-qt    'tmux conventions'   pending   │
│           research-ic    'Agent contracts'    pending   │
│           research-de    'Documentation'      pending   │
│           research-pl    'Bash patterns'      pending   │
│           synthesis-doc  'Write dossier'      pending   │
│                                                         │
│   Status bar: □□□ □□□□□□□□□  (3 phases, 9 tasks)        │
└─────────────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────┐
│ STEP 2: Setup phase completes                           │
│                                                         │
│   UPDATE todos SET status='done'                        │
│     WHERE id='setup-prep';                              │
│   UPDATE phases SET status='done' WHERE id='setup';     │
│   UPDATE phases SET status='in_progress'                │
│     WHERE id='research';                                │
│                                                         │
│   Status bar: ■□□ ■□□□□□□□□  (phase 1 done)             │
└─────────────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────┐
│ STEP 3: Launch all 7 agents (all in_progress at once)   │
│                                                         │
│   UPDATE todos SET status='in_progress'                 │
│     WHERE id LIKE 'research-%';                         │
│                                                         │
│   Status bar: ■■□ ■■■■■■■□□  (7 amber simultaneously!) │
└─────────────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────┐
│ STEP 4: Agents complete one by one                      │
│                                                         │
│   UPDATE todos SET status='done'                        │
│     WHERE id='research-ia';  -- first back              │
│   UPDATE todos SET status='done'                        │
│     WHERE id='research-dc';  -- second back             │
│   ...                                                   │
│                                                         │
│   Status bar: ■■□ ■■■■■■■□□                             │
│   → ■■□ ■■■■■■■■□ → ■■□ ■■■■■■■■■                      │
│   (blue fills replace amber as agents complete)         │
└─────────────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────┐
│ STEP 5: All research done, synthesis begins             │
│                                                         │
│   UPDATE phases SET status='done' WHERE id='research';  │
│   UPDATE phases SET status='in_progress'                │
│     WHERE id='synthesis';                               │
│   UPDATE todos SET status='in_progress'                 │
│     WHERE id='synthesis-doc';                           │
│                                                         │
│   Status bar: ■■■ ■□  (all phases visible, 1 task left) │
│   (active phase switches to synthesis)                  │
└─────────────────────────────────────────────────────────┘
```

### Workflow 3: "5-Phase Plan Implementation"

Standard plan-based development with the `/plan-*` command suite.

```
┌─────────────────────────────────────────────────────────┐
│ STEP 1: Clear old + create 5 phases                     │
│                                                         │
│   ⚠ "Clearing 3 incomplete todos from previous plan"    │
│   DELETE FROM todos; DELETE FROM phases;                 │
│                                                         │
│   phases: ph1 'Core Infrastructure'    1  pending       │
│           ph2 'Status Bar Rendering'   2  pending       │
│           ph3 'TPM Integration'        3  pending       │
│           ph4 'Detail Pane'            4  pending       │
│           ph5 'Agent Guidance'         5  pending       │
│                                                         │
│   todos: (created per-phase as implementation begins)   │
│                                                         │
│   Status bar: □□□□□  (5 phase pips, no tasks yet)       │
└─────────────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────┐
│ STEP 2: Phase 1 tasks created (plan-5-phase-tasks)      │
│                                                         │
│   INSERT INTO todos (id, title, status) VALUES           │
│     ('ph1-t01', 'Create helpers.sh', 'pending'),        │
│     ('ph1-t02', 'Session discovery', 'pending'),        │
│     ('ph1-t03', 'DB query layer', 'pending');           │
│                                                         │
│   Status bar: ■□□□□ □□□  (phase 1 active, 3 tasks)      │
└─────────────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────┐
│ STEP 3: Work through phase 1 tasks                      │
│                                                         │
│   Status bar: ■□□□□ ■□□ → ■□□□□ ■■□ → ■□□□□ ■■■        │
│   (task pips fill up as each completes)                 │
│                                                         │
│   Phase 1 all done:                                     │
│   UPDATE phases SET status='done' WHERE id='ph1';       │
│   Status bar: ■□□□□  (phase 1 green, no active tasks)  │
└─────────────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────┐
│ STEP 4: Move to phase 2, create its tasks               │
│                                                         │
│   DELETE FROM todos WHERE id LIKE 'ph1-%';  -- cleanup  │
│   UPDATE phases SET status='in_progress' WHERE id='ph2';│
│   INSERT INTO todos ... (ph2-t01, ph2-t02, etc.)        │
│                                                         │
│   Status bar: ■■□□□ □□□□  (phase 1 done, phase 2 new)  │
│                                                         │
│   Repeat for phases 3, 4, 5...                          │
└─────────────────────────────────────────────────────────┘
```

**Why DELETE old phase tasks?** Phase 1's tasks are history — showing them inflates the task count. The phase pip (green ■) already records that phase 1 is done. Per-phase cleanup keeps the task display focused on current work.

---

## 7. Staleness Detection

Tomux handles stale/orphaned data through two mechanisms:

### 7.1 Timestamp-Based Staleness

If `session_state` hasn't been updated in a configurable period (default: 10 minutes):

```bash
# In status.sh
last_update=$(sqlite3 "$db" "SELECT value FROM session_state
  WHERE key='activity'" 2>/dev/null)
# Compare updated_at of most recent todo change
last_todo_update=$(sqlite3 "$db" "SELECT MAX(updated_at) FROM todos" 2>/dev/null)
now=$(date -u +"%Y-%m-%d %H:%M:%S")
# If stale → dim the display or show ◌ (dotted circle)
```

### 7.2 Process-Based Staleness

If the copilot process is no longer in the pane's process tree:

```bash
# In status.sh
if ! has_copilot_process "$pane_pid"; then
  # Copilot exited — data may be stale
  # Show dimmed pips or idle indicator
fi
```

### 7.3 Recovery

Stale data is NOT destructive. The agent can rebuild state from conversation context at any time. The version warning (`⚠ TOMUX: guidance v1 outdated`) is informational, not blocking.

---

## 8. File Distribution

### 8.1 TOMUX_AGENT_GUIDANCE.md (Project Root)

Template file users copy into their project. The `/tomux-init` skill creates this automatically.

**Layered structure**:
1. **Version header** (semantic versioning)
2. **Essential contract** (tables, IDs, status values, cleanup rules)
3. **Worked examples** (optional — agent can skim or read deeply)

### 8.2 /tomux-init Skill (~/.claude/commands/tomux.md)

Run once per project. The skill:
1. Asks the user which instructions file to update (`.github/copilot-instructions.md`, `AGENTS.md`, or both)
2. Creates `TOMUX_AGENT_GUIDANCE.md` from the template (ships with plugin at `~/.tmux/plugins/tomux/templates/`)
3. Adds a brief pointer to the chosen instructions file
4. Creates the `phases` and `session_state` tables in the session DB

### 8.3 Global Default (~/.config/tomux/agent-guidance.md)

Fallback when no project-level `TOMUX_AGENT_GUIDANCE.md` exists. Installed by `/tomux-init --global`. Project-level file takes precedence.

### 8.4 Instructions File Pointer

Added by `/tomux-init` to the user's chosen file:

```markdown
## Tomux Progress Tracking

This project uses [Tomux](https://github.com/vaughanknight/tomux) for
tmux-based progress visualisation. Read `TOMUX_AGENT_GUIDANCE.md` in the
project root for the data contract — it defines how to create structured
todos and phases that Tomux can display.
```

---

## 9. Versioning

### 9.1 Semantic Versioning

The guidance file includes a version header:

```markdown
<!-- tomux-guidance-version: 1.0.0 -->
# Tomux Agent Guidance
...
```

Tomux reads this version and compares against its expected version:

| Situation | Action |
|-----------|--------|
| Versions match | Normal operation |
| Guidance minor version behind | Normal operation (backward compatible) |
| Guidance major version behind | Show warning: `⚠ TOMUX: guidance v1 → update to v2` |
| No version header | Treat as v1.0.0 (legacy) |

### 9.2 Version Detection (Bash)

```bash
guidance_version() {
  local guidance_file="$1"
  grep -m1 'tomux-guidance-version:' "$guidance_file" 2>/dev/null \
    | sed 's/.*version: *\([0-9.]*\).*/\1/'
}

expected_version="1.0.0"
actual=$(guidance_version "$GUIDANCE_FILE")
if [[ "${actual%%.*}" -lt "${expected_version%%.*}" ]]; then
  echo "#[fg=yellow]⚠ TOMUX: guidance v${actual} → update to v${expected_version}"
fi
```

---

## 10. Open Questions

### Q1: Per-phase task cleanup?

**RESOLVED**: YES — when moving to a new phase, DELETE the previous phase's completed tasks. Phase pips already record completion. This keeps the task display focused on current work and prevents the "73 todos" problem from trex.

### Q2: Phase status source?

**RESOLVED**: Read from the `phases` table. The agent is responsible for updating phase status. This is simpler and more explicit than calculating from task counts.

### Q3: Flat display without guidance?

**RESOLVED**: Show all todos as flat pips with a hint: `tomux: add TOMUX_AGENT_GUIDANCE.md for phase grouping`. This ensures Tomux works immediately even without structured data.

### Q4: Amber vs Yellow on 16-colour terminals?

**RESOLVED** (plan-2-clarify): Default to 256-colour codes (`colour214` for amber, `colour226` for yellow). Accept they look the same on 16-colour terminals. Users can override via `@tomux_colour_*` options if needed. No auto-detection or dual palette.

---

## 11. Quick Reference

### SQL Cheat Sheet (for agent guidance)

```sql
-- Create tables (idempotent)
CREATE TABLE IF NOT EXISTS phases (...);
CREATE TABLE IF NOT EXISTS session_state (...);

-- Clean slate
DELETE FROM todo_deps; DELETE FROM todos; DELETE FROM phases;

-- New phase
INSERT INTO phases (id, name, ordinal, status) VALUES ('ph1', '...', 1, 'pending');

-- New todo
INSERT INTO todos (id, title, status) VALUES ('ph1-t01', '...', 'pending');

-- Start task
UPDATE todos SET status='in_progress' WHERE id='ph1-t01';
UPDATE phases SET status='in_progress' WHERE id='ph1';

-- Complete task
UPDATE todos SET status='done' WHERE id='ph1-t01';

-- Complete phase
UPDATE phases SET status='done' WHERE id='ph1';

-- Update context
INSERT OR REPLACE INTO session_state (key, value) VALUES
  ('activity', '...'), ('phase_heading', '...'), ('total_tasks', '...');

-- Dynamic growth
INSERT INTO todos (id, title, status) VALUES ('clarify-batch5', '...', 'pending');
INSERT OR REPLACE INTO session_state (key, value) VALUES ('total_tasks', '6');
```

### ID Format Cheat Sheet

```
Phase IDs:  ph1, ph2, research, clarify, polish  (SHORT, no hyphens)
Todo IDs:   {phase}-{task}  →  ph1-t01, research-ia, clarify-batch1
Status:     pending | in_progress | done | blocked
```

---

*Workshop ready for review. Incorporate into `/plan-3-architect` for phase planning.*
