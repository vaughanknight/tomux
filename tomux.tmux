#!/usr/bin/env bash
# tomux.tmux — TPM entry point for Tomux progress visualisation plugin
# Installed to: ~/.tmux/plugins/tomux/tomux.tmux

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=scripts/helpers.sh
source "$CURRENT_DIR/scripts/helpers.sh"

# ---------------------------------------------------------------------------
# Register defaults — only sets the option if the user hasn't already
# ---------------------------------------------------------------------------
register_default() {
  local option="$1"
  local default_val="$2"
  local current
  current=$(tmux show-option -gqv "$option" 2>/dev/null)
  if [ -z "$current" ]; then
    tmux set-option -g "$option" "$default_val"
  fi
}

register_default "@tomux_refresh_interval"    "5"
register_default "@tomux_pip_filled"          "■"
register_default "@tomux_pip_empty"           "□"
register_default "@tomux_colour_phase_done"   "colour28"
register_default "@tomux_colour_task_done"    "colour33"
register_default "@tomux_colour_progress"     "colour214"
register_default "@tomux_colour_blocked"      "colour196"
register_default "@tomux_colour_warning"      "colour226"
register_default "@tomux_colour_pending"      "colour245"
register_default "@tomux_phase_threshold"     "10"
register_default "@tomux_task_threshold"      "10"
register_default "@tomux_show_activity"       "0"
register_default "@tomux_activity_max_length" "30"
register_default "@tomux_pane_position"       "bottom"
register_default "@tomux_pane_size"           "12"
register_default "@tomux_toggle_key"          "T"
register_default "@tomux_use_status_line"     "0"
register_default "@tomux_align"               "right"
register_default "@tomux_idle_indicator"      ""
register_default "@tomux_stale_timeout"       "600"

# ---------------------------------------------------------------------------
# Status-line interpolation — replace #{tomux_status} with #() runner
# ---------------------------------------------------------------------------
tomux_status_cmd="#($CURRENT_DIR/scripts/status.sh)"
interpolation="#{tomux_status}"

align=$(get_tmux_option "@tomux_align" "right")
if [ "$align" = "left" ]; then
  status_option="status-left"
else
  status_option="status-right"
fi

current_status=$(tmux show-option -gqv "$status_option" 2>/dev/null)
# Only interpolate if the placeholder is present
case "$current_status" in
  *"$interpolation"*)
    new_status="${current_status//$interpolation/$tomux_status_cmd}"
    tmux set-option -g "$status_option" "$new_status"
    ;;
esac

# ---------------------------------------------------------------------------
# Optional: dedicated status line (status 2)
# ---------------------------------------------------------------------------
use_status_line=$(get_tmux_option "@tomux_use_status_line" "0")
if [ "$use_status_line" = "1" ]; then
  current_count=$(tmux show-option -gqv "status" 2>/dev/null)
  current_count="${current_count:-1}"
  if [ "$current_count" -lt 2 ] 2>/dev/null; then
    tmux set-option -g "@tomux_original_status" "$current_count"
    tmux set-option -g "status" 2
  fi
  tmux set-option -g "status-format[1]" "$tomux_status_cmd"
fi

# ---------------------------------------------------------------------------
# Key binding — prefix + toggle_key
# ---------------------------------------------------------------------------
toggle_key=$(get_tmux_option "@tomux_toggle_key" "T")
tmux bind-key "$toggle_key" run-shell "$CURRENT_DIR/scripts/toggle.sh"
