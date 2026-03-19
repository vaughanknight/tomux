#!/usr/bin/env bash
# toggle.sh — Toggle the tomux detail pane

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=helpers.sh
source "$CURRENT_DIR/helpers.sh"

# Capture the original pane before any splits
original_pane=$(tmux display-message -p '#{pane_id}')

# Check for an existing detail pane (window-level option)
stored_pane=$(tmux show-window-option -qv "@tomux_detail_pane_id" 2>/dev/null)

if [ -n "$stored_pane" ]; then
  # Verify pane still exists in the current window
  pane_exists=""
  while IFS= read -r line; do
    if [ "$line" = "$stored_pane" ]; then
      pane_exists="1"
      break
    fi
  done <<EOF
$(tmux list-panes -F '#{pane_id}' 2>/dev/null)
EOF

  if [ -n "$pane_exists" ]; then
    # Kill the detail pane and clear the marker
    tmux kill-pane -t "$stored_pane"
    tmux set-window-option "@tomux_detail_pane_id" ""
    exit 0
  fi
fi

# No existing pane (or stale reference) — create one
position=$(get_tmux_option "@tomux_pane_position" "bottom")
size=$(get_tmux_option "@tomux_pane_size" "12")

split_flag="-v"
if [ "$position" = "right" ]; then
  split_flag="-h"
fi

# Split and launch the detail renderer
new_pane=$(tmux split-window "$split_flag" -l "$size" -P -F '#{pane_id}' \
  "$CURRENT_DIR/pane.sh")

# Tag and store
tmux select-pane -t "$new_pane" -T "tomux-detail"
tmux set-window-option "@tomux_detail_pane_id" "$new_pane"

# Return focus to the user's working pane
tmux select-pane -t "$original_pane"
