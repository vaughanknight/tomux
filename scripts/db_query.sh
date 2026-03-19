#!/usr/bin/env bash
# db_query.sh — SQLite query layer for tomux (read-only)
# Sourced by: status.sh, pane.sh

# Guard against multiple sourcing
[[ -n "${_TOMUX_DB_QUERY_LOADED:-}" ]] && return 0
readonly _TOMUX_DB_QUERY_LOADED=1

# Source helpers if not already loaded
TOMUX_SCRIPT_DIR="${TOMUX_SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
# shellcheck source=helpers.sh
source "${TOMUX_SCRIPT_DIR}/helpers.sh"

# --- Core query function ---

query_db() {
  local db_path="$1"
  local sql="$2"

  # Gate 1: sqlite3 available
  if ! command -v sqlite3 >/dev/null 2>&1; then
    return 0
  fi

  # Gate 2: DB file readable
  if [[ ! -r "$db_path" ]]; then
    return 0
  fi

  sqlite3 -readonly "$db_path" \
    ".timeout 2000" \
    ".separator |" \
    "$sql" 2>/dev/null || true
}

# --- Table existence check ---

table_exists() {
  local db_path="$1"
  local table_name="$2"

  # Gate 1: sqlite3 available
  if ! command -v sqlite3 >/dev/null 2>&1; then
    return 1
  fi

  # Gate 2: DB file readable
  if [[ ! -r "$db_path" ]]; then
    return 1
  fi

  local count
  count=$(sqlite3 -readonly "$db_path" \
    ".timeout 2000" \
    "SELECT count(*) FROM sqlite_master WHERE type='table' AND name='${table_name}';" 2>/dev/null) || true

  if [[ "$count" = "1" ]]; then
    return 0
  else
    return 1
  fi
}

# --- Data retrieval functions ---

get_todos() {
  local db_path="$1"

  if ! table_exists "$db_path" "todos"; then
    return 0
  fi

  query_db "$db_path" "SELECT id, title, status FROM todos ORDER BY created_at;"
}

get_phases() {
  local db_path="$1"

  if ! table_exists "$db_path" "phases"; then
    return 0
  fi

  query_db "$db_path" "SELECT id, name, ordinal, status FROM phases ORDER BY ordinal;"
}

get_session_state() {
  local db_path="$1"
  local key="$2"

  if ! table_exists "$db_path" "session_state"; then
    return 0
  fi

  query_db "$db_path" "SELECT value FROM session_state WHERE key = '${key}' LIMIT 1;"
}

get_active_phase_id() {
  local db_path="$1"

  if ! table_exists "$db_path" "phases"; then
    return 0
  fi

  # First non-done phase (by ordinal order)
  local phase_id
  phase_id=$(query_db "$db_path" \
    "SELECT id FROM phases WHERE status != 'done' ORDER BY ordinal LIMIT 1;")

  if [[ -n "$phase_id" ]]; then
    echo "$phase_id"
    return 0
  fi

  # Fallback: last phase by ordinal
  phase_id=$(query_db "$db_path" \
    "SELECT id FROM phases ORDER BY ordinal DESC LIMIT 1;")
  echo "$phase_id"
}
