#!/usr/bin/env bash
# pane.sh — Detail pane renderer for tomux
# Runs inside a tmux pane, auto-refreshes

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=helpers.sh
source "$CURRENT_DIR/helpers.sh"
# shellcheck source=session_discovery.sh
source "$CURRENT_DIR/session_discovery.sh"
# shellcheck source=db_query.sh
source "$CURRENT_DIR/db_query.sh"

# ANSI colour helpers
C_GREEN='\033[32m'
C_BLUE='\033[34m'
C_YELLOW='\033[33m'
C_RED='\033[31m'
C_GRAY='\033[90m'
C_BOLD='\033[1m'
C_RESET='\033[0m'

# Status icons with colour
icon_for_status() {
  case "$1" in
    done)        printf '%b' "${C_GREEN}✓${C_RESET}" ;;
    in_progress) printf '%b' "${C_YELLOW}◐${C_RESET}" ;;
    blocked)     printf '%b' "${C_RED}✕${C_RESET}" ;;
    *)           printf '%b' "${C_GRAY}○${C_RESET}" ;;
  esac
}

# Phase status icon
phase_icon_for_status() {
  case "$1" in
    done)        printf '%b' "${C_GREEN}✓${C_RESET}" ;;
    in_progress) printf '%b' "${C_YELLOW}▶${C_RESET}" ;;
    *)           printf '%b' "${C_GRAY}○${C_RESET}" ;;
  esac
}

# Build a mini progress bar: ■■■□□ 3/5
render_progress_bar() {
  local done_count="$1"
  local total="$2"
  local pip_filled pip_empty
  pip_filled=$(get_tmux_option "@tomux_pip_filled" "■")
  pip_empty=$(get_tmux_option "@tomux_pip_empty" "□")

  local bar=""
  local i=0
  while [ "$i" -lt "$total" ]; do
    if [ "$i" -lt "$done_count" ]; then
      bar="${bar}${pip_filled}"
    else
      bar="${bar}${pip_empty}"
    fi
    i=$((i + 1))
  done
  printf '  %b %d/%d' "${C_BLUE}${bar}${C_RESET}" "$done_count" "$total"
}

# ---------------------------------------------------------------------------
# Main loop
# ---------------------------------------------------------------------------
refresh_interval=$(get_tmux_option "@tomux_refresh_interval" "5")

while true; do
  clear

  # Get CWD from the user's pane (! = last active pane)
  pane_cwd=$(tmux display-message -p -t '!' '#{pane_current_path}' 2>/dev/null)
  if [ -z "$pane_cwd" ]; then
    printf '%b\n' "${C_GRAY}tomux: cannot determine working directory${C_RESET}"
    sleep "$refresh_interval"
    continue
  fi

  # Discover session and database
  db_path=$(find_session_db "$pane_cwd" 2>/dev/null)
  if [ -z "$db_path" ] || [ ! -f "$db_path" ]; then
    printf '%b\n' "${C_GRAY}tomux: no active session${C_RESET}"
    sleep "$refresh_interval"
    continue
  fi

  # Header
  printf '%b\n' "${C_BOLD}═══ Tomux Progress ═══${C_RESET}"
  echo ""

  # Check for phases table
  has_phases=$(sqlite3 "$db_path" \
    "SELECT count(*) FROM sqlite_master WHERE type='table' AND name='phases';" 2>/dev/null)

  if [ "$has_phases" = "1" ]; then
    phase_count=$(sqlite3 "$db_path" "SELECT count(*) FROM phases;" 2>/dev/null)
  else
    phase_count=0
  fi

  if [ "$phase_count" -gt 0 ]; then
    # ---- Phased layout ----
    sqlite3 -separator '|' "$db_path" \
      "SELECT id, name, status FROM phases ORDER BY ordinal;" 2>/dev/null | \
    while IFS='|' read -r phase_id phase_name phase_status; do
      p_icon=$(phase_icon_for_status "$phase_status")
      printf ' %b %b\n' "$p_icon" "${C_BOLD}${phase_name}${C_RESET}"

      # Count done tasks in this phase (by id prefix convention: phN-*)
      phase_total=$(sqlite3 "$db_path" \
        "SELECT count(*) FROM todos WHERE id LIKE '${phase_id}-%';" 2>/dev/null)
      phase_done=$(sqlite3 "$db_path" \
        "SELECT count(*) FROM todos WHERE id LIKE '${phase_id}-%' AND status='done';" 2>/dev/null)

      phase_total="${phase_total:-0}"
      phase_done="${phase_done:-0}"

      if [ "$phase_total" -gt 0 ]; then
        render_progress_bar "$phase_done" "$phase_total"
        echo ""

        # List individual tasks
        sqlite3 -separator '|' "$db_path" \
          "SELECT title, status FROM todos WHERE id LIKE '${phase_id}-%' ORDER BY id;" 2>/dev/null | \
        while IFS='|' read -r todo_title todo_status; do
          t_icon=$(icon_for_status "$todo_status")
          printf '    %b %s\n' "$t_icon" "$todo_title"
        done
      fi
      echo ""
    done
  else
    # ---- Flat layout (no phases) ----
    total=$(sqlite3 "$db_path" "SELECT count(*) FROM todos;" 2>/dev/null)
    done_count=$(sqlite3 "$db_path" "SELECT count(*) FROM todos WHERE status='done';" 2>/dev/null)
    total="${total:-0}"
    done_count="${done_count:-0}"

    if [ "$total" -gt 0 ]; then
      render_progress_bar "$done_count" "$total"
      echo ""
      echo ""
      sqlite3 -separator '|' "$db_path" \
        "SELECT title, status FROM todos ORDER BY id;" 2>/dev/null | \
      while IFS='|' read -r todo_title todo_status; do
        t_icon=$(icon_for_status "$todo_status")
        printf '    %b %s\n' "$t_icon" "$todo_title"
      done
    else
      printf '%b\n' "${C_GRAY}  No tasks found${C_RESET}"
    fi
    echo ""
  fi

  # Activity line
  show_activity=$(get_tmux_option "@tomux_show_activity" "0")
  if [ "$show_activity" = "1" ]; then
    activity=$(sqlite3 "$db_path" \
      "SELECT value FROM session_state WHERE key='activity';" 2>/dev/null)
    if [ -n "$activity" ]; then
      max_len=$(get_tmux_option "@tomux_activity_max_length" "30")
      if [ "${#activity}" -gt "$max_len" ]; then
        activity="${activity:0:$max_len}…"
      fi
      printf '%b\n' "${C_GRAY}⚡ ${activity}${C_RESET}"
    fi
  fi

  sleep "$refresh_interval"
done
