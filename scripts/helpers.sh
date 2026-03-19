#!/usr/bin/env bash
# helpers.sh — Shared utilities for tomux
# Sourced by: status.sh, pane.sh, toggle.sh, session_discovery.sh, db_query.sh

# Guard against multiple sourcing
[[ -n "${_TOMUX_HELPERS_LOADED:-}" ]] && return 0
readonly _TOMUX_HELPERS_LOADED=1

# --- Option reading ---

get_tmux_option() {
  local option_name="$1"
  local default_value="${2:-}"
  local value
  value=$(tmux show-option -gqv "$option_name" 2>/dev/null) || true
  if [[ -n "$value" ]]; then
    echo "$value"
  else
    echo "$default_value"
  fi
}

# --- Platform detection ---

detect_platform() {
  local uname_out
  uname_out=$(uname -s 2>/dev/null) || true
  case "$uname_out" in
    Darwin) echo "macos" ;;
    Linux)  echo "linux" ;;
    *)      echo "unknown" ;;
  esac
}

# --- Colour mapping ---

colour_code() {
  local name="$1"
  local override
  override=$(get_tmux_option "@tomux_colour_${name}" "")
  if [[ -n "$override" ]]; then
    echo "$override"
    return 0
  fi

  case "$name" in
    phase_done) echo "colour28"  ;;
    task_done)  echo "colour33"  ;;
    progress)   echo "colour214" ;;
    blocked)    echo "colour196" ;;
    warning)    echo "colour226" ;;
    pending)    echo "colour245" ;;
    *)          echo "colour245" ;;
  esac
}

# --- Pip rendering ---

render_pips() {
  local done_count="$1"
  local in_progress_count="$2"
  local blocked_count="$3"
  local total="$4"
  local done_colour="$5"
  local progress_colour="$6"
  local blocked_colour="$7"

  local pip_filled
  local pip_empty
  pip_filled=$(get_tmux_option "@tomux_pip_filled" "■")
  pip_empty=$(get_tmux_option "@tomux_pip_empty" "□")

  local pending_colour
  pending_colour=$(colour_code "pending")

  local result=""

  # Done pips
  local count=0
  while [[ "$count" -lt "$done_count" ]]; do
    result="${result}#[fg=${done_colour}]${pip_filled}"
    count=$((count + 1))
  done

  # In-progress pips
  count=0
  while [[ "$count" -lt "$in_progress_count" ]]; do
    result="${result}#[fg=${progress_colour}]${pip_filled}"
    count=$((count + 1))
  done

  # Blocked pips
  count=0
  while [[ "$count" -lt "$blocked_count" ]]; do
    result="${result}#[fg=${blocked_colour}]${pip_filled}"
    count=$((count + 1))
  done

  # Pending pips (remaining)
  local rendered=$((done_count + in_progress_count + blocked_count))
  local pending=$((total - rendered))
  if [[ "$pending" -lt 0 ]]; then
    pending=0
  fi
  count=0
  while [[ "$count" -lt "$pending" ]]; do
    result="${result}#[fg=${pending_colour}]${pip_empty}"
    count=$((count + 1))
  done

  result="${result}#[fg=default]"
  echo "$result"
}

# --- Overflow-aware rendering ---

render_with_overflow() {
  local done="$1"
  local in_progress="$2"
  local blocked="$3"
  local total="$4"
  local threshold="$5"
  local done_colour="$6"
  local progress_colour="$7"
  local blocked_colour="$8"

  if [[ "$total" -le "$threshold" ]]; then
    render_pips "$done" "$in_progress" "$blocked" "$total" \
      "$done_colour" "$progress_colour" "$blocked_colour"
  else
    echo "#[fg=${done_colour}]${done}#[fg=default]/${total}"
  fi
}

# --- Text formatting ---

format_activity() {
  local text="$1"
  local max_length="${2:-30}"

  if [[ -z "$text" ]]; then
    echo ""
    return 0
  fi

  if [[ "${#text}" -le "$max_length" ]]; then
    echo "$text"
  else
    local truncated="${text:0:$((max_length - 1))}"
    echo "${truncated}…"
  fi
}
