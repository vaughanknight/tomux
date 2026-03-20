---
description: Initialize a project for Tomux progress tracking. Copies TOMUX_AGENT_GUIDANCE.md, updates agent instructions files, and creates database tables for phase/task visualisation in tmux.
---

<!-- SESSION_STATE_BEGIN -->
<!-- Auto-managed by session-state-apply. Do not edit manually. -->
<!-- On skill entry, the agent should FIRST create tables, THEN update session_state: -->
<!-- sql: CREATE TABLE IF NOT EXISTS session_state (key TEXT PRIMARY KEY, value TEXT); CREATE TABLE IF NOT EXISTS phases (id TEXT PRIMARY KEY, name TEXT, ordinal INTEGER, status TEXT DEFAULT 'pending'); INSERT OR REPLACE INTO session_state (key, value) VALUES ('current_skill', 'tomux-init'), ('workflow_phase', 'Setup'), ('status', 'in_progress'), ('activity', 'Initializing Tomux tracking'); -->
<!-- SESSION_STATE_END -->

# /tomux-init — Initialize Tomux Progress Tracking

````md
User input (optional project path or flags):

$ARGUMENTS

You are setting up Tomux progress tracking for this project. Tomux is a tmux plugin
that visualises AI agent progress as coloured pip indicators (■□) in the tmux status bar.

## What This Skill Does

1. **Checks** if `TOMUX_AGENT_GUIDANCE.md` already exists in the project root
2. **Copies** the guidance template if missing (from the tmux plugin or creates inline)
3. **Updates** the project's agent instructions file with a brief pointer
4. **Creates** database tables (`phases`, `session_state`) if they don't exist

## Step 1: Check for existing guidance file

Look for `TOMUX_AGENT_GUIDANCE.md` in the current working directory.

- If it **exists**: Tell the user it's already set up. Ask if they want to overwrite.
- If it **doesn't exist**: Proceed to Step 2.

## Step 2: Copy or create TOMUX_AGENT_GUIDANCE.md

Check if the template exists at `~/.tmux/plugins/tomux/templates/TOMUX_AGENT_GUIDANCE.md`.

- If the template **exists**: Copy it to the project root.
- If the template **doesn't exist**: Create the guidance file inline using the
  Essential Contract below.

## Step 3: Update agent instructions file

Ask the user (via ask_user tool) which file to add the Tomux pointer to:

Options:
- `.github/copilot-instructions.md` (GitHub Copilot standard)
- `AGENTS.md` (generic)
- Both
- Skip (don't add a pointer)

Then check if the pointer already exists (search for "Tomux Progress Tracking" in the file).
- If it **already exists**: Skip — tell the user the pointer is already there.
- If it **doesn't exist**: Append this block to the chosen file(s), creating the file if it doesn't exist:

```markdown

## Tomux Progress Tracking

This project uses [Tomux](https://github.com/vaughanknight/tomux) for
tmux-based progress visualisation. Read `TOMUX_AGENT_GUIDANCE.md` in the
project root for the data contract — it defines how to create structured
todos and phases that Tomux can display as coloured pips in the tmux status bar.

When working on tasks, follow the guidance to:
- Create phases with short IDs (ph1, ph2, etc.)
- Create todos with phase-prefixed IDs (ph1-t01, ph2-scaffold)
- Update session_state with activity context
- Clean up old todos when starting new work
```

## Step 4: Create database tables

Execute the following SQL to ensure the required tables exist:

```sql
CREATE TABLE IF NOT EXISTS phases (
  id TEXT PRIMARY KEY,
  name TEXT,
  ordinal INTEGER,
  status TEXT DEFAULT 'pending'
);

-- session_state may already exist from Copilot CLI
CREATE TABLE IF NOT EXISTS session_state (
  key TEXT PRIMARY KEY,
  value TEXT
);
```

Then set initial session state:

```sql
INSERT OR REPLACE INTO session_state (key, value) VALUES
  ('activity', 'Tomux initialized'),
  ('status', 'in_progress');
```

## Step 5: Confirm success

Tell the user:
- ✅ TOMUX_AGENT_GUIDANCE.md created (or already existed)
- ✅ Instructions pointer added to [chosen file]
- ✅ Database tables ready
- 📋 Tomux will show pips in your tmux status bar when you start working

## Essential Contract (for inline creation if template not found)

If you need to create the guidance file inline, include at minimum:

```markdown
<!-- tomux-guidance-version: 1.0.0 -->
# Tomux Agent Guidance

> Follow these rules so Tomux can visualise your progress in tmux.

## Table Setup (run once, idempotent)

\```sql
CREATE TABLE IF NOT EXISTS phases (
  id TEXT PRIMARY KEY, name TEXT, ordinal INTEGER,
  status TEXT DEFAULT 'pending'
);
CREATE TABLE IF NOT EXISTS session_state (
  key TEXT PRIMARY KEY, value TEXT
);
\```

## Phase IDs — use SHORT names
- ✅ ph1, ph2, research, clarify
- ❌ plan-033-ph1, phase-1

## Todo IDs — prefix with phase ID
- ✅ ph1-t01, research-ia, clarify-batch1
- ❌ t01, task-1

## Status Values
pending | in_progress | done | blocked

## Clean Slate — when starting new work
DELETE FROM todo_deps; DELETE FROM todos; DELETE FROM phases;
Then INSERT new phases and todos.

## Session State — update on each skill entry
INSERT OR REPLACE INTO session_state (key, value) VALUES
  ('activity', 'What you are doing right now'),
  ('phase_heading', 'Phase N: Name'),
  ('phase_number', 'N'),
  ('total_phases', 'N'),
  ('total_tasks', 'N');
```

## Global Default

If the user runs `/tomux-init --global`, copy the guidance to
`~/.config/tomux/agent-guidance.md` (create the directory if needed).
This serves as a fallback when no project-level file exists.

````
