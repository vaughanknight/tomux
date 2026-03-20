#!/usr/bin/env bash
# status.sh — Status bar renderer for tomux
# Called by tmux: #(path/to/status.sh)
# Outputs: tmux format string with coloured pips

set -f  # Disable globbing for safety

# Resolve script directory and source dependencies
TOMUX_SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
export TOMUX_SCRIPT_DIR

# shellcheck source=helpers.sh
source "${TOMUX_SCRIPT_DIR}/helpers.sh"
# shellcheck source=session_discovery.sh
source "${TOMUX_SCRIPT_DIR}/session_discovery.sh"
# shellcheck source=db_query.sh
source "${TOMUX_SCRIPT_DIR}/db_query.sh"

# --- CWD and pane PID ---

pane_cwd="${1:-$(pwd)}"
pane_pid=$(tmux display-message -p '#{pane_pid}' 2>/dev/null) || true

# --- Copilot process check (for staleness, not gating) ---

copilot_running=0
if [[ -n "$pane_pid" ]] && has_copilot_process "$pane_pid"; then
  copilot_running=1
fi

# --- Session discovery ---

session_id=$(find_session_id "$pane_cwd")
if [[ -z "$session_id" ]]; then
  exit 0
fi

session_db=$(get_session_db_path "$session_id")
if [[ -z "$session_db" ]]; then
  exit 0
fi

# --- Cache check ---
# Use DB mtime to avoid redundant queries

get_file_mtime() {
  local filepath="$1"
  local platform
  platform=$(detect_platform)
  case "$platform" in
    macos) stat -f "%m" "$filepath" 2>/dev/null || echo "0" ;;
    *)     stat -c "%Y" "$filepath" 2>/dev/null || echo "0" ;;
  esac
}

current_mtime=$(get_file_mtime "$session_db")
cached_mtime=$(tmux show-environment -g TOMUX_CACHE_MTIME 2>/dev/null | sed 's/^[^=]*=//' || true)
cached_output=$(tmux show-environment -g TOMUX_CACHE_OUTPUT 2>/dev/null | sed 's/^[^=]*=//' || true)

if [[ -n "$cached_mtime" && "$cached_mtime" = "$current_mtime" && -n "$cached_output" ]]; then
  echo "$cached_output"
  exit 0
fi

# --- Configuration ---

phase_threshold=$(get_tmux_option "@tomux_phase_threshold" "10")
task_threshold=$(get_tmux_option "@tomux_task_threshold" "10")
show_activity=$(get_tmux_option "@tomux_show_activity" "0")
activity_max_length=$(get_tmux_option "@tomux_activity_max_length" "30")

# --- Colour setup ---

phase_done_colour=$(colour_code "phase_done")
task_done_colour=$(colour_code "task_done")
progress_colour=$(colour_code "progress")
blocked_colour=$(colour_code "blocked")
_pending_colour=$(colour_code "pending")  # available for future use

# --- Query data ---

phases_raw=$(get_phases "$session_db")
todos_raw=$(get_todos "$session_db")

# --- Determine active phase ---

has_phases=0
phase_count=0
phase_done=0
phase_in_progress=0
phase_blocked=0
active_phase_id=""

if [[ -n "$phases_raw" ]]; then
  has_phases=1

  # Count phase statuses
  while IFS='|' read -r _p_id _p_name _p_ordinal p_status; do
    phase_count=$((phase_count + 1))
    case "$p_status" in
      done)        phase_done=$((phase_done + 1)) ;;
      in_progress) phase_in_progress=$((phase_in_progress + 1)) ;;
      blocked)     phase_blocked=$((phase_blocked + 1)) ;;
    esac
  done <<EOF
$phases_raw
EOF

  active_phase_id=$(get_active_phase_id "$session_db")
fi

# --- Count task statuses for active phase ---

task_done=0
task_in_progress=0
task_blocked=0
task_total=0

if [[ -n "$todos_raw" ]]; then
  while IFS='|' read -r t_id _t_title t_status; do
    # If we have phases and an active phase, filter tasks by phase prefix
    if [[ "$has_phases" -eq 1 && -n "$active_phase_id" ]]; then
      case "$t_id" in
        "${active_phase_id}"-*) ;;  # Matches active phase
        *) continue ;;              # Skip other phases
      esac
    fi

    task_total=$((task_total + 1))
    case "$t_status" in
      done)        task_done=$((task_done + 1)) ;;
      in_progress) task_in_progress=$((task_in_progress + 1)) ;;
      blocked)     task_blocked=$((task_blocked + 1)) ;;
    esac
  done <<EOF
$todos_raw
EOF
fi

# --- Render output ---

output=""

if [[ "$has_phases" -eq 1 && "$phase_count" -gt 1 ]]; then
  # Phase pips
  phase_pips=$(render_with_overflow \
    "$phase_done" "$phase_in_progress" "$phase_blocked" "$phase_count" \
    "$phase_threshold" "$phase_done_colour" "$progress_colour" "$blocked_colour")
  output="${phase_pips} "
fi

# Task pips
if [[ "$task_total" -gt 0 ]]; then
  task_pips=$(render_with_overflow \
    "$task_done" "$task_in_progress" "$task_blocked" "$task_total" \
    "$task_threshold" "$task_done_colour" "$progress_colour" "$blocked_colour")
  output="${output}${task_pips}"
fi

# Activity text
if [[ "$show_activity" = "1" ]]; then
  activity_text=$(get_session_state "$session_db" "activity")
  if [[ -n "$activity_text" ]]; then
    formatted=$(format_activity "$activity_text" "$activity_max_length")
    output="${output} ${formatted}"
  fi
fi

# --- Cache result ---

if [[ -n "$current_mtime" ]]; then
  tmux set-environment -g TOMUX_CACHE_MTIME "$current_mtime" 2>/dev/null || true
  tmux set-environment -g TOMUX_CACHE_OUTPUT "$output" 2>/dev/null || true
fi

echo "$output"
