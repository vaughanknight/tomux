#!/usr/bin/env bats
# test_db_query.bats — Unit tests for scripts/db_query.sh
# TAD: Promoted from scratch probes — database access contracts

TOMUX_HOME="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
FIXTURE_DIR="$TOMUX_HOME/tests/fixtures"

setup() {
  source "$TOMUX_HOME/tests/fixtures/mocks.sh"
  source "$TOMUX_HOME/scripts/helpers.sh"
  source "$TOMUX_HOME/scripts/db_query.sh"
}

# --- Three-gate guard ---

@test "get_todos: returns empty when DB file missing" {
  # Why: Graceful degradation (P-4) — never error on missing data
  # Contract: missing DB → empty string, exit 0
  result=$(get_todos "/nonexistent/path.db")
  [ -z "$result" ]
}

@test "get_todos: returns empty when DB has no todos table" {
  # Create a temp DB without todos table
  local tmpdb="/tmp/tomux_test_notable.db"
  sqlite3 "$tmpdb" "CREATE TABLE other (id TEXT);" 2>/dev/null
  result=$(get_todos "$tmpdb")
  [ -z "$result" ]
  rm -f "$tmpdb"
}

# --- get_todos ---

@test "get_todos: basic.db returns 3 pipe-delimited rows" {
  # Contract: returns id|title|status per row, ordered by created_at
  result=$(get_todos "$FIXTURE_DIR/basic.db")
  line_count=$(echo "$result" | grep -c '|')
  [ "$line_count" -eq 3 ]
}

@test "get_todos: basic.db first todo is ph1-t01" {
  result=$(get_todos "$FIXTURE_DIR/basic.db")
  first_line=$(echo "$result" | head -1)
  [[ "$first_line" == "ph1-t01|"* ]]
}

@test "get_todos: flat-nophases.db returns 5 todos" {
  result=$(get_todos "$FIXTURE_DIR/flat-nophases.db")
  line_count=$(echo "$result" | grep -c '|')
  [ "$line_count" -eq 5 ]
}

@test "get_todos: empty.db returns empty" {
  result=$(get_todos "$FIXTURE_DIR/empty.db")
  [ -z "$result" ]
}

# --- get_phases ---

@test "get_phases: basic.db returns 1 phase" {
  result=$(get_phases "$FIXTURE_DIR/basic.db")
  line_count=$(echo "$result" | grep -c '|')
  [ "$line_count" -eq 1 ]
}

@test "get_phases: multiphase.db returns 3 phases ordered by ordinal" {
  result=$(get_phases "$FIXTURE_DIR/multiphase.db")
  line_count=$(echo "$result" | grep -c '|')
  [ "$line_count" -eq 3 ]
  first_line=$(echo "$result" | head -1)
  [[ "$first_line" == "ph1|"* ]]
}

@test "get_phases: flat-nophases.db returns empty (no phases table)" {
  # Contract: missing phases table → empty, not error
  result=$(get_phases "$FIXTURE_DIR/flat-nophases.db")
  [ -z "$result" ]
}

# --- get_session_state ---

@test "get_session_state: basic.db activity returns expected value" {
  result=$(get_session_state "$FIXTURE_DIR/basic.db" "activity")
  [ "$result" = "Implementing DB query layer" ]
}

@test "get_session_state: missing key returns empty" {
  result=$(get_session_state "$FIXTURE_DIR/basic.db" "nonexistent_key")
  [ -z "$result" ]
}

# --- get_active_phase_id ---

@test "get_active_phase_id: multiphase.db returns first non-done phase" {
  result=$(get_active_phase_id "$FIXTURE_DIR/multiphase.db")
  [ "$result" = "ph2" ]
}

@test "get_active_phase_id: basic.db returns ph1 (in_progress)" {
  result=$(get_active_phase_id "$FIXTURE_DIR/basic.db")
  [ "$result" = "ph1" ]
}

# --- table_exists ---

@test "table_exists: basic.db has todos table" {
  table_exists "$FIXTURE_DIR/basic.db" "todos"
}

@test "table_exists: basic.db has phases table" {
  table_exists "$FIXTURE_DIR/basic.db" "phases"
}

@test "table_exists: flat-nophases.db does NOT have phases table" {
  ! table_exists "$FIXTURE_DIR/flat-nophases.db" "phases"
}

# --- overflow fixture ---

@test "get_todos: overflow.db returns 15 tasks" {
  result=$(get_todos "$FIXTURE_DIR/overflow.db")
  line_count=$(echo "$result" | grep -c '|')
  [ "$line_count" -eq 15 ]
}
