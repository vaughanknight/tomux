#!/usr/bin/env bash
# Recreate tmux sessions after restart

tmux kill-server 2>/dev/null
sleep 1

tmux new-session -d -s player-tower -c ~/GitHub/player-tower
tmux new-session -d -s tower        -c ~/GitHub/player-tower
tmux new-session -d -s trex         -c ~/GitHub/trex
tmux new-session -d -s workiq       -c ~/GitHub/workiq
tmux new-session -d -s tomux        -c ~/GitHub/tomux

# Attach to tomux
tmux attach -t tomux
