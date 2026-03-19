# Research Dossier: Tomux — tmux Progress Visualisation Plugin

**Generated**: 2026-03-19T00:30:00Z
**Research Query**: "Deep exploration of trex reference project for session discovery, DB schema, visualization patterns, tmux plugin conventions, agent contracts, and bash implementation"
**Mode**: Pre-Plan (informs plan-1b-specify)
**Location**: docs/plans/001-tmux-progress-plugin/research-dossier.md
**FlowSpace**: Not available
**Findings**: 70 across 7 subagents

---

## Executive Summary

### What We're Building
A **native tmux plugin** (pure bash + sqlite3) that reads the Copilot CLI session database and renders phase/task progress as coloured pip indicators in the tmux status bar and an optional detail pane.

### Reference Implementation
**trex** (at `~/GitHub/trex`) already solves session discovery, DB reading, and progress visualization — but in TypeScript/React for a browser frontend. Tomux reimplements the read-only data pipeline in pure bash for tmux.

### Key Insights
1. **Session discovery is solved**: Global `session-store.db` maps CWD → session UUID; process tree confirms copilot is running
2. **DB schema is stable**: `todos` + `session_state` tables with well-defined status values; `phases` table optional
3. **Phase grouping via ID prefix**: `todo.id.replace(/-[^-]+$/, '')` extracts phase key — critical contract
4. **sqlite3 queries are fast**: 10-13ms per query on macOS — well within tmux's 5-15s refresh cycle
5. **tmux plugin conventions are simple**: TPM sources `*.tmux` entry points; `#()` shell expansion drives status bar

### Quick Stats
- **Reference files analysed**: 50+ across trex
- **Real sessions examined**: 5 with 113 total todos
- **Platform**: macOS (Darwin ARM64), tmux 3.6a, sqlite3 3.50.4
- **Performance budget**: ~150ms per refresh cycle (budget: 1000ms)

---

## 1. Session Discovery (IA Findings)

### 1.1 Three-Step Matching Strategy

```
Terminal Pane
    ↓
Get pane PID via: tmux list-panes -F '#{pane_pid}'
    ↓
Walk process tree from pane PID (BFS, max depth 10)
    ↓
"copilot" in process names?
    ↓ YES                          ↓ NO
Get pane CWD via:                  Return null (no display)
  tmux display -p '#{pane_current_path}'
    ↓
Query ~/.copilot/session-store.db:
  SELECT id FROM sessions
  WHERE cwd = ?
  ORDER BY updated_at DESC LIMIT 1
    ↓ (fallback: parent dir match)
  SELECT id FROM sessions
  WHERE ? LIKE (cwd || '%')
  ORDER BY updated_at DESC LIMIT 1
    ↓
Read ~/.copilot/session-state/{uuid}/session.db
  → todos, session_state, (phases optional)
    ↓
Render pips
```

### 1.2 Process Tree Walking (Bash Translation)

**trex approach** (TypeScript): `ps -eo pid=,ppid=` then BFS from pane PID with MAX_DEPTH=10

**Bash equivalent**:
```bash
has_copilot_process() {
  local pane_pid="$1"
  # Get all processes; check if any child of pane contains "copilot"
  ps -eo pid=,ppid=,comm= 2>/dev/null | awk -v root="$pane_pid" '
    BEGIN { found=0; pids[root]=1 }
    { if ($2 in pids) { pids[$1]=1; if ($3 ~ /copilot/) found=1 } }
    END { exit !found }
  '
}
```

**Performance**: `ps -eo pid=,ppid=,comm=` takes ~92ms on macOS (tested).

### 1.3 CWD-to-Session Lookup

```bash
find_session_id() {
  local cwd="$1"
  local store="$HOME/.copilot/session-store.db"
  [[ -r "$store" ]] || return 1

  # Exact match first
  local sid
  sid=$(sqlite3 "$store" \
    "SELECT id FROM sessions WHERE cwd='$cwd' ORDER BY updated_at DESC LIMIT 1" 2>/dev/null)

  # Parent directory fallback
  if [[ -z "$sid" ]]; then
    sid=$(sqlite3 "$store" \
      "SELECT id FROM sessions WHERE '$cwd' LIKE (cwd||'%') ORDER BY updated_at DESC LIMIT 1" 2>/dev/null)
  fi

  echo "$sid"
}
```

### 1.4 Platform Differences

| Concern | macOS | Linux/WSL |
|---------|-------|-----------|
| Process listing | `ps -eo pid=,ppid=,comm=` | Same |
| CWD detection | `lsof -d cwd -Fn -p PID` (fallback) | `readlink /proc/PID/cwd` |
| sqlite3 | Pre-installed (3.50.4) | Usually installed |
| `-readonly` flag | Not available — use file permissions | Not available |

**Gotcha**: sqlite3 `-readonly` flag doesn't exist on macOS. Use `PRAGMA query_only = ON;` instead.

---

## 2. Database Schema & Data Model (DC Findings)

### 2.1 Global Session Store

**Path**: `~/.copilot/session-store.db` (41 sessions found)

```sql
CREATE TABLE sessions (
  id TEXT PRIMARY KEY,
  cwd TEXT,
  repository TEXT,
  branch TEXT,
  summary TEXT,
  created_at TEXT DEFAULT (datetime('now')),
  updated_at TEXT DEFAULT (datetime('now')),
  host_type TEXT
);
CREATE INDEX idx_sessions_cwd ON sessions(cwd);
```

### 2.2 Per-Session Database

**Path**: `~/.copilot/session-state/{uuid}/session.db`

```sql
CREATE TABLE todos (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  description TEXT,
  status TEXT DEFAULT 'pending'
    CHECK(status IN ('pending','in_progress','done','blocked')),
  created_at TEXT DEFAULT (datetime('now')),
  updated_at TEXT DEFAULT (datetime('now'))
);

CREATE TABLE todo_deps (
  todo_id TEXT NOT NULL,
  depends_on TEXT NOT NULL,
  PRIMARY KEY (todo_id, depends_on)
);

CREATE TABLE session_state (
  key TEXT PRIMARY KEY,
  value TEXT
);
```

**Optional (not always present)**:
```sql
CREATE TABLE phases (
  id TEXT PRIMARY KEY,
  name TEXT,
  ordinal INTEGER,
  status TEXT
);
```

### 2.3 Phase Grouping Algorithm

**Critical contract**: Todos are grouped into phases by ID prefix extraction:

```
todo.id.replace(/-[^-]+$/, '') → phase key

Examples:
  'ph1-t01'      → 'ph1'
  'ph1-scaffold'  → 'ph1'
  'ph2-t03'      → 'ph2'
```

If a `phases` table exists, the phase key is matched to `phases.id`. Otherwise, the prefix itself becomes the phase display name.

### 2.4 Session State Keys

| Key | Example Value | Purpose |
|-----|---------------|---------|
| `current_skill` | `plan-6` | Active skill/command ID |
| `workflow_phase` | `Execution` | Human-readable stage |
| `status` | `in_progress` | Current status |
| `activity` | `Implementing phase` | Free-text for display |
| `plan_name` | `Visualisation Plugin` | Plan title |
| `plan_slug` | `025-vis-plugins` | Plan folder |
| `phase_heading` | `Phase 3: Rendering` | Active phase name |
| `phase_number` | `3` | Phase ordinal |
| `total_phases` | `5` | Total phase count |
| `current_task_id` | `T004` | Active task |
| `current_task_title` | `Wire panel clicks` | Active task name |

### 2.5 Real Data Samples

Found 5 sessions with todos (113 total). Example from a real session:

```
ph1-t01  | Create package scaffold   | done
ph1-t02  | Install dependencies      | done
ph1-t03  | Configure build           | done
ph2-t01  | Implement core rendering  | in_progress
ph2-t02  | Add colour support        | pending
ph2-t03  | Test cross-platform       | pending
```

**todo_deps usage**: Only 7% of sessions (low adoption).

---

## 3. Visualization Patterns (PS Findings)

### 3.1 Colour Palette (trex → tmux mapping)

| State | trex Colour | tmux Name | tmux 256 |
|-------|-------------|-----------|----------|
| Phase complete | `#22c55e` (green) | `green` | `colour46` |
| Task complete | `#3b82f6` (blue/cyan) | `blue` | `colour33` |
| In progress | `#f59e0b` (amber) | `yellow` | `colour220` |
| Blocked | `#ef4444` (red) | `red` | `colour196` |
| Warning/question | — | `yellow` | `colour226` |
| Pending | `#9ca3af` (gray) | `white` | `colour247` |

**User request**: Amber for in-progress, yellow for warnings. These are distinct on 256-colour terminals: `colour214` (amber) vs `colour226` (yellow).

### 3.2 Unicode Characters (Tier 1: 99% terminal support)

| Purpose | Filled | Empty | Notes |
|---------|--------|-------|-------|
| Default pips | ■ (U+25A0) | □ (U+25A1) | Best balance of size/visibility |
| Small pips | ▪ (U+25AA) | ▫ (U+25AB) | More compact |
| Circles | ● (U+25CF) | ○ (U+25CB) | Alternative style |
| Bars | ▰ (U+25B0) | ▱ (U+25B1) | Horizontal feel |

**Status icons** (for pane detail view):
- ✓ (U+2713) — done
- ◐ (U+25D0) — in progress
- ✕ (U+2715) — blocked
- ○ (U+25CB) — pending

### 3.3 tmux Format String Syntax

```bash
# Colour directives
#[fg=green]■#[fg=blue]■#[fg=yellow]■#[fg=default]□□

# With 256-colour indices
#[fg=colour46]■#[fg=colour33]■#[fg=colour220]■#[fg=colour247]□□
```

### 3.4 Overflow Strategy

| Items | Display |
|-------|---------|
| ≤ threshold (default 10) | Individual pips: `■■■□□□` |
| > threshold | Fraction: `3/20` with colour |

Thresholds configurable separately for phases and tasks.

---

## 4. tmux Plugin Conventions (QT Findings)

### 4.1 Plugin Structure (from real TPM plugins)

```
tomux/
├── tomux.tmux              # Entry point (executable, #!/usr/bin/env bash)
├── scripts/
│   ├── helpers.sh          # get_tmux_option(), platform detection
│   ├── status.sh           # Status bar renderer (called by #())
│   ├── pane.sh             # Pane detail view
│   ├── session_discovery.sh
│   └── db_query.sh
└── tests/
```

### 4.2 Entry Point Pattern

```bash
#!/usr/bin/env bash
CURRENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$CURRENT_DIR/scripts/helpers.sh"

main() {
  # Register format string variable
  local status_cmd="#($CURRENT_DIR/scripts/status.sh)"

  # Read user's current status-right, inject our variable
  local interpolated_options
  interpolated_options="$(get_tmux_option "@tomux_interpolated_options" "status-right")"
  for opt in $interpolated_options; do
    local current_val
    current_val="$(tmux show-option -gqv "$opt")"
    local new_val="${current_val//\#\{tomux_status\}/$status_cmd}"
    tmux set-option -g "$opt" "$new_val"
  done

  # Bind detail pane toggle
  local toggle_key
  toggle_key="$(get_tmux_option "@tomux_toggle_key" "T")"
  tmux bind-key "$toggle_key" run-shell "$CURRENT_DIR/scripts/pane.sh toggle"
}
main
```

### 4.3 Format String Interpolation

The `#{tomux_status}` marker in the user's `.tmux.conf` gets replaced with `#(path/to/status.sh)` at plugin load time. tmux then calls that script on every status-interval refresh.

**User's current tmux**:
- Version: **3.6a**
- status-interval: **15 seconds**
- status-right: `"#{?window_bigger,...} \"#{=21:pane_title}\" %H:%M %d-%b-%y"`

### 4.4 Caching Pattern

```bash
# tmux environment variables for caching
tmux set-environment -g TOMUX_CACHE_DATA "serialized_data"
tmux set-environment -g TOMUX_CACHE_TIME "$(date +%s)"

# Read cache
cached=$(tmux show-environment -g TOMUX_CACHE_DATA 2>/dev/null | cut -d= -f2-)
cache_time=$(tmux show-environment -g TOMUX_CACHE_TIME 2>/dev/null | cut -d= -f2-)
now=$(date +%s)
if (( now - cache_time < refresh_interval )); then
  echo "$cached"  # Use cache
fi
```

### 4.5 Keybindings Tested

```bash
tmux bind-key T run-shell "/path/to/pane.sh toggle"   # prefix+T → toggle detail pane
tmux bind-key R run-shell "/path/to/status.sh refresh" # prefix+R → force refresh
```

---

## 5. Agent Guidance Contract (IC Findings)

### 5.1 Session State Injection (22 skills)

All 22 Copilot CLI skills have `<!-- SESSION_STATE_BEGIN/END -->` blocks that execute on skill entry:

```sql
INSERT OR REPLACE INTO session_state (key, value) VALUES
  ('current_skill', 'plan-6'),
  ('workflow_phase', 'Execution'),
  ('status', 'in_progress'),
  ('activity', 'Implementing phase');
```

### 5.2 Todo ID Naming Contract

```
✅ CORRECT: 'ph1-t01', 'ph1-scaffold', 'ph2-t01'
❌ WRONG:   'plan-033-ph1', 't01', 'task-1'
```

The grouping algorithm strips the LAST `-segment` to get the phase prefix. Long prefixes like `plan-033` cause misgrouping.

### 5.3 TOMUX_AGENT_GUIDANCE.md Requirements

The guidance file must instruct agents to:
1. Create `session_state` table if not exists (idempotent)
2. Use SHORT phase IDs: `ph1`, `ph2` (not `plan-033-ph1`)
3. Create todos with format `{phase_id}-{task_id}`
4. Update `session_state` with activity context on each skill entry
5. Use standard status values: `pending`, `in_progress`, `done`, `blocked`
6. Update todo status as work progresses (`in_progress` → `done`)
7. For batch operations (20 questions), create individual todos
8. For parallel subagents, each gets a phase-prefixed todo

---

## 6. Design Decisions from trex (DE Findings)

### 6.1 Plan 034 — Session Matching (Key Decisions)

| Decision | Chosen | Rejected | Why |
|----------|--------|----------|-----|
| Session matching | CWD + process tree | lsof file handles | Copilot opens DB on-demand, lsof unreliable |
| Process detection | Walk from pane PID | Global pgrep | Need per-pane isolation |
| CWD source | tmux format strings | /proc or lsof | More portable, tmux-native |
| Polling interval | 3-5 seconds | Event-driven | No reliable tmux hook for CWD change |

### 6.2 ADR-0014 — Session State System

- **Four-layer architecture**: Schema → Injection → Reading → Visualisation
- **Keys are all strings** — no types, no schema validation at DB level
- **Idempotent writes** — `INSERT OR REPLACE` ensures re-runs are safe
- **Graceful degradation** — missing tables return null, never crash

### 6.3 Plugin Architecture Pattern (IDataCollector)

```typescript
interface IDataCollector {
  id: string           // Plugin identifier
  interval: number     // Polling interval (ms)
  processMatch(procs: string[]): boolean  // Should this collector run?
  collectForSession(pid, cwd, procs): Promise<unknown>  // Collect data
}
```

Tomux's bash equivalent: a single `status.sh` script that combines process matching, session lookup, and rendering.

---

## 7. Bash Implementation (PL Findings)

### 7.1 Performance Budget (Tested)

| Component | Time | Notes |
|-----------|------|-------|
| `ps -eo pid=,ppid=,comm=` | 92ms | Full process list |
| `sqlite3` simple query | 10-13ms | Single SELECT |
| `sqlite3` complex query | 13ms | JOIN or multiple SELECTs |
| tmux command | 10ms | `display-message`, `show-option` |
| Shell overhead | 20ms | Script startup, variable init |
| **Total per refresh** | **~150ms** | Budget: 1000ms ✅ |

### 7.2 Critical Gotchas

1. **`#[fg=green]` doesn't render in `#()` output** — tmux interprets `#[...]` directives in format strings, but the script output via `#()` IS treated as a format string, so it DOES work. However, test carefully.

2. **Tilde expansion fails in double quotes**: Use `"$HOME/.copilot/"` not `"~/.copilot/"`

3. **Pipes create subshells** — variables set inside `while read` are lost:
   ```bash
   # BAD: $result is empty after loop
   query | while read line; do result="$line"; done
   # GOOD: use process substitution
   while read line; do result="$line"; done < <(query)
   ```

4. **sqlite3 has no `-readonly` flag on macOS** — use `PRAGMA query_only = ON;`

5. **Cache via tmux environment** — `tmux set-environment -g` persists across pane refreshes

### 7.3 Recommended Query Pattern

```bash
query_todos() {
  local db="$1"
  command -v sqlite3 >/dev/null 2>&1 || return 1
  [[ -r "$db" ]] || return 1

  sqlite3 "$db" <<'SQL' 2>/dev/null
.timeout 1000
SELECT COALESCE(
  (SELECT name FROM sqlite_master WHERE type='table' AND name='todos'),
  'NOTABLE'
);
SQL

  # If table exists, query
  sqlite3 "$db" <<'SQL' 2>/dev/null
.timeout 1000
.mode csv
.separator |
SELECT id, title, COALESCE(status,'pending') FROM todos ORDER BY created_at;
SQL
}
```

---

## Modification Considerations

### ✅ Safe to Build
- Status bar pip rendering (pure string building)
- Configuration via `@tomux_*` options
- SQLite queries against session.db
- Overflow fraction mode

### ⚠️ Build with Caution
- Process tree walking (platform differences)
- tmux pane management (layout restoration)
- Cache invalidation (stale data display)

### 🚫 Do Not Touch
- Copilot session databases (read-only, P-1)
- User's existing status bar content (P-6)
- tmux core configuration

---

## External Research Opportunities

### Research Opportunity 1: tmux Status Bar Multi-Line Support

**Why Needed**: User wants configurable status bar line (main bar vs extra line above). tmux `status` option supports 2-5 lines in recent versions but documentation is sparse.

**Ready-to-use prompt**:
```
/deepresearch "How does tmux multi-line status bar work? Specifically: (1) the 'status' option values for 2-5 lines, (2) 'status-format[N]' for formatting individual lines, (3) which tmux version introduced this, (4) how do plugins target specific status lines, (5) any known issues with multi-line status in tmux 3.2+?"
```

### Research Opportunity 2: tmux Pane Toggle Pattern

**Why Needed**: User wants a toggleable detail pane (show/hide) that preserves layout. Need a robust pattern that handles edge cases.

**Ready-to-use prompt**:
```
/deepresearch "What is the best pattern for implementing a toggleable sidebar/bottom pane in tmux via a plugin? Specifically: (1) how to save and restore pane layout, (2) how tmux-sidebar plugin handles this, (3) how to detect if the detail pane already exists, (4) how to identify a plugin-owned pane across sessions, (5) how to auto-close the pane when tmux exits."
```

---

## 8. Deep Research: Multi-Line Status Bar (External)

**Full report**: `deep-research-multiline-status.md`

### Critical Findings

1. **Introduced in tmux 2.9** (May 2019). `status N` accepts `off`, `on`, `2`, `3`, `4`, `5`
2. **Line numbering**: Line 0 = topmost, Line 1 = bottommost (for `status 2`). This is counterintuitive — index 0 is furthest from pane content
3. **`status-format[N]` replaces `status-left`/`status-right`**: When multi-line is enabled, each line is fully defined by `status-format[N]` — the traditional `status-left`/`status-right` only control line 0's defaults
4. **`#()` works in status-format[N]**: Shell expansion works identically to status-left/right
5. **Alignment directives**: `#[align=left]`, `#[align=centre]`, `#[align=right]` within each line
6. **Append with `-a` flag**: `tmux set -ag status-format[1] "content"` appends without overwriting
7. **Per-line styling**: Each line can have independent `#[fg=...,bg=...]` colours
8. **Performance**: Same `status-interval` governs all lines. Shell commands cached between refreshes
9. **Max 5 lines** supported

### Plugin Integration Pattern

```bash
# Safe: detect current line count, only add if needed
current_status=$(tmux show-option -gqv status)
if [[ "$current_status" != "2" && "$current_status" != "3" ]]; then
  # Save original and upgrade to 2 lines
  tmux set-option -g @tomux_original_status "$current_status"
  tmux set-option -g status 2
fi
# Set our content on line 1 (bottom line)
tmux set-option -g status-format[1] \
  "#[align=right]#($CURRENT_DIR/scripts/status.sh)"
```

### Gotcha: Restoring on Uninstall

Plugin should save original `status` value in `@tomux_original_status` and restore it when disabled/uninstalled.

---

## 9. Deep Research: Pane Toggle with Hotkey (External)

**Full report**: `deep-research-pane-toggle.md`

### Critical Findings

1. **Best identification strategy**: Combine window user option (`@tomux_detail_pane_id`) with pane title (`select-pane -T 'tomux-detail'`) for robust detection
2. **Layout preservation**: For simple splits, tmux auto-restores when pane is killed. For complex layouts, save `#{window_layout}` before split, restore with `select-layout`
3. **Auto-refresh script**: `split-window -v -l 10 "while true; do clear; ./render.sh; sleep 5; done"`
4. **Focus management**: Capture original pane ID before split, `select-pane -t $original` after creating detail pane
5. **`remain-on-exit on`**: Set on detail pane to prevent flash-close on script errors
6. **Popup alternative**: `display-popup -E -h 80% -w 80%` for overlay-style detail (no layout disruption)
7. **tmux-resurrect exclusion**: Detail pane should NOT be persisted by session save plugins

### Complete Toggle Function

```bash
tomux_toggle_detail() {
  local win=$(tmux display-message -p '#{window_id}')
  local cur=$(tmux display-message -p '#{pane_id}')
  local stored=$(tmux show-window-option -t "$win" -qv @tomux_detail_pane_id)
  local position=$(get_tmux_option "@tomux_pane_position" "bottom")
  local size=$(get_tmux_option "@tomux_pane_size" "12")

  # If detail pane exists and is valid, kill it
  if [[ -n "$stored" ]]; then
    if tmux list-panes -t "$win" -F '#{pane_id}' | grep -qF "$stored"; then
      tmux kill-pane -t "$stored"
      tmux set-window-option -t "$win" @tomux_detail_pane_id ''
      return 0
    fi
  fi

  # Create detail pane
  local split_flag="-v"
  [[ "$position" == "right" ]] && split_flag="-h"

  tmux split-window $split_flag -l "$size" -t "$cur" \
    "$CURRENT_DIR/scripts/pane.sh"
  local new_pane=$(tmux display-message -p '#{pane_id}')

  # Mark as ours
  tmux select-pane -t "$new_pane" -T "tomux-detail"
  tmux set-window-option -t "$win" @tomux_detail_pane_id "$new_pane"

  # Return focus to original pane
  tmux select-pane -t "$cur"
}
```

### Hotkey Binding

```bash
# In tomux.tmux entry point
local toggle_key=$(get_tmux_option "@tomux_toggle_key" "T")
tmux bind-key "$toggle_key" run-shell "$CURRENT_DIR/scripts/toggle.sh"
```

### Edge Cases Handled

- **User closes pane manually**: Stale ID detected via `list-panes` check; new pane created
- **Rapid double-press**: Second press sees pane exists → kills it (natural debounce)
- **Script crash**: `remain-on-exit on` keeps pane visible with error
- **Single-pane window**: Split works normally — original pane shrinks, detail appears

---

## Next Steps

1. **Run `/plan-1b-specify`** to create the feature specification
2. All external research gaps are now filled
3. The research dossier + 2 deep research reports will be referenced throughout planning and implementation

---

**Research Complete**: 2026-03-19T00:35:00Z
**Deep Research Added**: 2026-03-19T00:45:00Z
**Report Location**: docs/plans/001-tmux-progress-plugin/research-dossier.md
