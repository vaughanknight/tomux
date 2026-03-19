# Tomux — Idioms

**Version**: 1.0.0
**Last updated**: 2026-03-18
**Derives from**: [constitution.md](./constitution.md), [rules.md](./rules.md)

---

## 1. tmux Option Pattern

All configurable values use tmux user options with the `@tomux_` prefix
and a helper function to read with defaults:

```bash
# Standard option-read idiom
get_tmux_option() {
  local option="$1"
  local default_value="$2"
  local value
  value=$(tmux show-option -gqv "$option")
  echo "${value:-$default_value}"
}

# Usage
refresh=$(get_tmux_option "@tomux_refresh_interval" "5")
pip_filled=$(get_tmux_option "@tomux_pip_filled" "■")
pip_empty=$(get_tmux_option "@tomux_pip_empty" "□")
```

## 2. Graceful DB Access Pattern

Every database access follows a three-gate guard:

```bash
query_session_db() {
  local db_path="$1"
  local query="$2"

  # Gate 1: sqlite3 available?
  command -v sqlite3 >/dev/null 2>&1 || return 1

  # Gate 2: DB file exists and is readable?
  [[ -r "$db_path" ]] || return 1

  # Gate 3: Required table exists?
  local has_table
  has_table=$(sqlite3 "$db_path" \
    "SELECT COUNT(*) FROM sqlite_master
     WHERE type='table' AND name='todos'" 2>/dev/null)
  [[ "$has_table" == "1" ]] || return 1

  # Safe to query
  sqlite3 -readonly "$db_path" "$query" 2>/dev/null
}
```

## 3. Session Discovery Pattern

Matches the trex approach — CWD-based lookup in the global session store:

```bash
find_session_id() {
  local cwd="$1"
  local store="$HOME/.copilot/session-store.db"

  # Exact CWD match, most recent session
  local session_id
  session_id=$(sqlite3 -readonly "$store" \
    "SELECT id FROM sessions
     WHERE cwd = '$cwd'
     ORDER BY updated_at DESC LIMIT 1" 2>/dev/null)

  if [[ -z "$session_id" ]]; then
    # Fallback: parent directory match
    session_id=$(sqlite3 -readonly "$store" \
      "SELECT id FROM sessions
       WHERE '$cwd' LIKE (cwd || '%')
       ORDER BY updated_at DESC LIMIT 1" 2>/dev/null)
  fi

  echo "$session_id"
}
```

## 4. Pip Rendering Pattern

Core rendering idiom — builds a string of filled/empty pips with
ANSI colour codes:

```bash
render_pips() {
  local done="$1"
  local in_progress="$2"
  local total="$3"
  local done_colour="$4"      # e.g., "green" or "blue"
  local progress_colour="$5"  # e.g., "yellow"
  local pip_filled pip_empty
  pip_filled=$(get_tmux_option "@tomux_pip_filled" "■")
  pip_empty=$(get_tmux_option "@tomux_pip_empty" "□")

  local result=""
  local i
  for ((i = 0; i < total; i++)); do
    if ((i < done)); then
      result+="#[fg=${done_colour}]${pip_filled}"
    elif ((i < done + in_progress)); then
      result+="#[fg=${progress_colour}]${pip_filled}"
    else
      result+="#[fg=default]${pip_empty}"
    fi
  done
  result+="#[fg=default]"
  echo "$result"
}
```

## 5. Overflow Pattern

When item count exceeds the configurable threshold, switch to fraction:

```bash
render_with_overflow() {
  local done="$1"
  local in_progress="$2"
  local total="$3"
  local threshold="$4"
  local done_colour="$5"
  local progress_colour="$6"

  if ((total > threshold)); then
    # Compact fraction mode
    echo "#[fg=${done_colour}]${done}#[fg=default]/${total}"
  else
    render_pips "$done" "$in_progress" "$total" \
      "$done_colour" "$progress_colour"
  fi
}
```

## 6. Status Bar Integration Pattern

Never overwrite the user's status bar. Provide a format string variable:

```bash
# In tomux.tmux (entry point)
tmux set-option -g @tomux_status \
  "#(${CURRENT_DIR}/scripts/status.sh)"

# User adds to their .tmux.conf:
# set -g status-right "... #{@tomux_status} ..."
```

## 7. Complexity Score Calibration Examples

| Change | S | I | D | N | F | T | CS |
|--------|---|---|---|---|---|---|-----|
| Fix typo in pip character default | 0 | 0 | 0 | 0 | 0 | 0 | **CS-1** (trivial) |
| Add new colour option for blocked state | 1 | 0 | 0 | 0 | 0 | 1 | **CS-1** (trivial) |
| Implement overflow fraction mode | 1 | 0 | 0 | 1 | 0 | 1 | **CS-2** (small) |
| Add session discovery with CWD lookup | 1 | 1 | 1 | 1 | 0 | 1 | **CS-3** (medium) |
| Build tmux pane detail view | 2 | 1 | 0 | 1 | 0 | 1 | **CS-3** (medium) |
| Add process tree walking for multi-pane | 1 | 1 | 0 | 2 | 0 | 2 | **CS-4** (large) |
| Full plugin with TPM, status bar, pane view | 2 | 2 | 1 | 2 | 1 | 2 | **CS-5** (epic) |

## 8. Directory Layout

```
tomux/
├── tomux.tmux              # TPM entry point
├── scripts/
│   ├── status.sh           # Status bar renderer (called by #())
│   ├── pane.sh             # Pane detail renderer
│   ├── session_discovery.sh # Find active Copilot session
│   ├── db_query.sh         # SQLite query helpers
│   └── helpers.sh          # Shared utilities
├── tests/
│   ├── unit/               # bats unit tests
│   ├── integration/        # bats integration tests
│   ├── scratch/            # Temporary probes (.gitignored)
│   └── fixtures/           # Sample DBs, mock data
├── docs/
│   ├── project-rules/      # Constitution, rules, idioms, arch
│   └── adr/                # Architecture decision records
├── TOMUX_AGENT_GUIDANCE.md # Instructions for AI agents
├── README.md               # Installation & configuration
├── Makefile                # test, lint, install targets
└── .gitignore
```

<!-- USER CONTENT START -->
<!-- Add project-specific idioms here. -->
<!-- USER CONTENT END -->
