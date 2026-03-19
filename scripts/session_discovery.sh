#!/usr/bin/env bash
# session_discovery.sh — Find active Copilot session for current pane
# Sourced by: status.sh, pane.sh

# Guard against multiple sourcing
[[ -n "${_TOMUX_SESSION_DISCOVERY_LOADED:-}" ]] && return 0
readonly _TOMUX_SESSION_DISCOVERY_LOADED=1

# Source helpers if not already loaded
TOMUX_SCRIPT_DIR="${TOMUX_SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
# shellcheck source=helpers.sh
source "${TOMUX_SCRIPT_DIR}/helpers.sh"

# --- Session discovery ---

find_session_id() {
  local cwd="$1"

  # Gate 1: sqlite3 available
  if ! command -v sqlite3 >/dev/null 2>&1; then
    return 0
  fi

  local store_db="${HOME}/.copilot/session-store.db"

  # Gate 2: DB file readable
  if [[ ! -r "$store_db" ]]; then
    return 0
  fi

  # Gate 3: sessions table exists
  local has_table
  has_table=$(sqlite3 -readonly "$store_db" \
    "SELECT count(*) FROM sqlite_master WHERE type='table' AND name='sessions';" 2>/dev/null) || true
  if [[ "$has_table" != "1" ]]; then
    return 0
  fi

  # Exact CWD match (most recent)
  local session_id
  session_id=$(sqlite3 -readonly "$store_db" \
    ".timeout 2000" \
    "SELECT id FROM sessions WHERE cwd = '${cwd}' ORDER BY updated_at DESC LIMIT 1;" 2>/dev/null) || true

  if [[ -n "$session_id" ]]; then
    echo "$session_id"
    return 0
  fi

  # Parent directory fallback: match sessions whose cwd is a parent of given cwd
  session_id=$(sqlite3 -readonly "$store_db" \
    ".timeout 2000" \
    "SELECT id FROM sessions WHERE '${cwd}' LIKE cwd || '%' ORDER BY length(cwd) DESC, updated_at DESC LIMIT 1;" 2>/dev/null) || true

  if [[ -n "$session_id" ]]; then
    echo "$session_id"
  fi
}

get_session_db_path() {
  local session_id="$1"

  if [[ -z "$session_id" ]]; then
    return 0
  fi

  local db_path="${HOME}/.copilot/session-state/${session_id}/session.db"

  if [[ -r "$db_path" ]]; then
    echo "$db_path"
  fi
}

has_copilot_process() {
  local pane_pid="$1"

  if [[ -z "$pane_pid" ]]; then
    return 1
  fi

  # Get full process listing: pid, ppid, command name
  local ps_output
  ps_output=$(ps -eo pid=,ppid=,comm= 2>/dev/null) || return 1

  # Walk the process tree from pane_pid using awk
  # Collect all descendant PIDs, then check if any comm contains "copilot"
  local found
  found=$(echo "$ps_output" | awk -v root="$pane_pid" '
    BEGIN { pids[root] = 1; found = 0 }
    {
      pid = $1 + 0
      ppid = $2 + 0
      comm = $3
      all_pid[NR] = pid
      all_ppid[NR] = ppid
      all_comm[NR] = comm
    }
    END {
      # Iteratively find all descendants
      changed = 1
      while (changed) {
        changed = 0
        for (i = 1; i <= NR; i++) {
          if ((all_ppid[i] in pids) && !(all_pid[i] in pids)) {
            pids[all_pid[i]] = 1
            changed = 1
          }
        }
      }
      # Check if any descendant command contains "copilot"
      for (i = 1; i <= NR; i++) {
        if (all_pid[i] in pids) {
          if (index(tolower(all_comm[i]), "copilot") > 0) {
            found = 1
            exit
          }
        }
      }
      print found
    }
  ') || true

  if [[ "$found" = "1" ]]; then
    return 0
  else
    return 1
  fi
}
