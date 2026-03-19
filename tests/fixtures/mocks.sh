#!/usr/bin/env bash
# mocks.sh — Mock tmux commands for isolated unit testing
# Source this in bats tests: source "$FIXTURE_DIR/mocks.sh"

# Override tmux with a mock that returns predictable values
MOCK_TMUX_OPTIONS=""

mock_set_option() {
  MOCK_TMUX_OPTIONS="${MOCK_TMUX_OPTIONS}${1}=${2}\n"
}

mock_get_option() {
  local key="$1"
  local val
  val=$(printf '%b' "$MOCK_TMUX_OPTIONS" | grep "^${key}=" | tail -1 | cut -d= -f2-)
  echo "$val"
}

# Replace tmux command for testing
tmux() {
  case "$1" in
    show-option|show-options)
      shift
      # Parse -gqv flags
      local option=""
      while [[ $# -gt 0 ]]; do
        case "$1" in
          -gqv|-gvq|-qgv|-qvg|-vgq|-vqg) shift; option="$1" ;;
          -g|-q|-v) ;;
          *) option="$1" ;;
        esac
        shift
      done
      mock_get_option "$option"
      ;;
    show-window-option|show-window-options)
      shift
      local option=""
      while [[ $# -gt 0 ]]; do
        case "$1" in
          -t) shift ;; # skip target
          -qv|-vq) shift; option="$1" ;;
          *) option="$1" ;;
        esac
        shift
      done
      mock_get_option "$option"
      ;;
    display-message)
      shift
      while [[ $# -gt 0 ]]; do
        case "$1" in
          -p) shift; echo "${MOCK_TMUX_DISPLAY:-}" ;;
          *) shift ;;
        esac
      done
      ;;
    set-option|set-window-option)
      # Silently accept
      ;;
    set-environment)
      # Silently accept
      ;;
    show-environment)
      shift
      local key=""
      while [[ $# -gt 0 ]]; do
        case "$1" in
          -g) ;;
          *) key="$1" ;;
        esac
        shift
      done
      mock_get_option "env_${key}"
      ;;
    list-panes)
      echo "${MOCK_TMUX_PANES:-}"
      ;;
    split-window|kill-pane|select-pane|bind-key|select-layout)
      # Silently accept
      ;;
    *)
      echo "MOCK_TMUX: unhandled command: $*" >&2
      return 1
      ;;
  esac
}

export -f tmux
