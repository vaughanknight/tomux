# Tomux — Architecture

**Version**: 1.0.0
**Last updated**: 2026-03-18
**Derives from**: [constitution.md](./constitution.md)

---

## 1. System Overview

```
┌─────────────────────────────────────────────────────────┐
│                    tmux status bar                       │
│  ... user content ... ■■■□□ ■■□□□□ ... user content ... │
│                       ↑phases ↑tasks                    │
└──────────────────────────┬──────────────────────────────┘
                           │ #() shell expansion
                           │ (every N seconds)
┌──────────────────────────▼──────────────────────────────┐
│                    scripts/status.sh                     │
│  1. Discover session (CWD → session-store.db → UUID)    │
│  2. Query session.db (todos, session_state)              │
│  3. Render pips (phases + tasks)                         │
│  4. Output tmux format string                            │
└──────────────────────────┬──────────────────────────────┘
                           │ sqlite3 -readonly
              ┌────────────┴────────────┐
              ▼                         ▼
┌──────────────────────┐  ┌──────────────────────────────┐
│ ~/.copilot/          │  │ ~/.copilot/session-state/     │
│  session-store.db    │  │  {uuid}/session.db            │
│  (global index)      │  │  (per-session todos/phases)   │
│                      │  │                               │
│  sessions:           │  │  todos: id,title,status       │
│    id, cwd,          │  │  session_state: key,value     │
│    updated_at        │  │  todo_deps: todo_id,dep       │
└──────────────────────┘  └──────────────────────────────┘
```

## 2. Component Boundaries

### Entry Point (`tomux.tmux`)

- **Responsibility**: TPM integration, option registration, keybindings
- **Calls**: `scripts/*.sh` helpers
- **MUST NOT**: Query databases directly, render UI directly
- **Boundary**: Sets up tmux format variables; delegates all work

### Status Bar Renderer (`scripts/status.sh`)

- **Responsibility**: Produce a tmux format string for the status bar
- **Called by**: tmux `#()` format string expansion
- **Inputs**: tmux `@tomux_*` options, Copilot session DB
- **Output**: tmux format string with coloured pips
- **MUST**: Complete within 1 second (tmux blocks on `#()`)
- **MUST**: Cache results between refresh intervals
- **Boundary**: Calls `session_discovery.sh` and `db_query.sh`

### Pane Detail View (`scripts/pane.sh`)

- **Responsibility**: Render full task list in a tmux pane
- **Called by**: Keybinding (e.g., `prefix + T`) or always-on pane
- **Output**: Terminal text with ANSI colours
- **MUST**: Refresh on configurable interval
- **MUST**: Show phase names, task names, status icons
- **Boundary**: Calls `session_discovery.sh` and `db_query.sh`

### Session Discovery (`scripts/session_discovery.sh`)

- **Responsibility**: Map current working directory to Copilot session
- **Algorithm**:
  1. Get CWD from tmux pane (`#{pane_current_path}`)
  2. Query `~/.copilot/session-store.db` for session UUID by CWD
  3. Optionally: walk process tree to verify copilot is running
  4. Return path to `~/.copilot/session-state/{uuid}/session.db`
- **MUST**: Handle missing DB, missing table, no match
- **Boundary**: Pure discovery — no rendering, no state mutation

### DB Query Layer (`scripts/db_query.sh`)

- **Responsibility**: Execute SQLite queries and return structured data
- **MUST**: Use `sqlite3 -readonly` (or equivalent)
- **MUST**: Check table existence before querying
- **MUST**: Set timeout to avoid blocking on locked databases
- **Output**: Pipe-delimited rows for bash parsing
- **Boundary**: Database access only — no rendering

### Shared Helpers (`scripts/helpers.sh`)

- **Responsibility**: tmux option reading, colour formatting, pip
  character rendering, overflow logic
- **MUST**: Be sourced (not executed) by other scripts
- **Boundary**: Pure functions with no side effects

## 3. Data Flow

### Status Bar Refresh Cycle

```
tmux (every status-interval seconds)
  → evaluates #(scripts/status.sh)
    → session_discovery.sh
      → sqlite3 session-store.db (CWD → UUID)
    → db_query.sh
      → sqlite3 session.db (todos + session_state)
    → helpers.sh
      → render_pips() → coloured format string
  → tmux displays result in status bar
```

### Pane Detail Refresh Cycle

```
User presses prefix+T (or pane auto-refreshes)
  → scripts/pane.sh runs in a tmux pane
    → session_discovery.sh (same as above)
    → db_query.sh (same as above)
    → renders full task table with ANSI colours
    → sleeps for refresh_interval
    → loops
```

## 4. Integration Contracts

### With Copilot CLI (read-only)

| Database | Access | Tables Used |
|----------|--------|-------------|
| `~/.copilot/session-store.db` | Read-only | `sessions` (id, cwd, updated_at) |
| `~/.copilot/session-state/{uuid}/session.db` | Read-only | `todos`, `session_state`, `todo_deps` |

**Contract**: Tomux depends on these table schemas. If Copilot CLI
changes them, Tomux must adapt. Version-detect by checking table
existence and column presence.

### With tmux (format strings)

| Variable | Type | Content |
|----------|------|---------|
| `#{@tomux_status}` | Format string | Compact pip display for status bar |
| `@tomux_*` | User options | All configuration (see README) |

### With TOMUX_AGENT_GUIDANCE.md

The agent guidance file tells AI agents to:
1. Check if `todos` table exists in session DB
2. Create structured todos with phase-prefixed IDs
3. Update `session_state` with activity context
4. Use consistent status values: pending, in_progress, done, blocked

## 5. Anti-Patterns

| Anti-Pattern | Why It's Wrong | Do Instead |
|--------------|---------------|------------|
| Writing to `status-right` directly | Overwrites user config (violates P-6) | Set `@tomux_status` variable; user embeds it |
| Running sqlite3 without checking existence | Errors shown in status bar | Use three-gate guard pattern (see idioms.md §2) |
| Spawning background daemons | Complexity, orphan processes | Use tmux `#()` polling (status bar) or `watch`-style loop (pane) |
| Parsing JSON in bash | Fragile, slow, needs jq | Use sqlite3 pipe-delimited output with `IFS='|'` |
| Hardcoding colour codes | Breaks user themes | Use tmux colour names and `@tomux_colour_*` options |
| Global variables in helpers | Namespace pollution | Use `local` in functions, prefix globals with `_tomux_` |

## 6. Platform Considerations

| Concern | macOS | Linux | WSL |
|---------|-------|-------|-----|
| sqlite3 | Pre-installed | Usually installed | Usually installed |
| Process tree | `ps -o ppid= -p` | Same | Same |
| CWD detection | `lsof -p` fallback | `/proc/{pid}/cwd` | `/proc/{pid}/cwd` |
| tmux passthrough | `allow-passthrough on` | Same | Same |
| Colour support | 256-colour typical | 256 or truecolour | Depends on terminal |

## 7. Deployment Model

```
User installs via TPM:
  set -g @plugin 'vaughanknight/tomux'

TPM clones to:
  ~/.tmux/plugins/tomux/

User adds to .tmux.conf:
  set -g status-right "#{@tomux_status} | %H:%M"

On tmux start:
  TPM sources tomux.tmux
  → registers @tomux_* defaults
  → sets @tomux_status = "#(~/.tmux/plugins/tomux/scripts/status.sh)"
  → binds prefix+T to toggle detail pane
```

<!-- USER CONTENT START -->
<!-- Add project-specific architecture notes here. -->
<!-- USER CONTENT END -->
