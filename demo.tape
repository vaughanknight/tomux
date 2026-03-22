# Tomux Demo — VHS Tape
# Shows Tomux pips updating live inside a tmux session
# Run: vhs demo.tape

Output demo.gif

Set Shell "bash"
Set FontSize 13
Set Width 1100
Set Height 600
Set Theme "Dracula"
Set Padding 10
Set TypingSpeed 30ms

# Start a fresh tmux on a separate socket
Type "tmux -L demo new-session -d -s demo -c ~/GitHub/tomux"
Enter
Sleep 1s
Type "tmux -L demo set -g status-style 'bg=colour236,fg=colour248'"
Enter
Sleep 200ms
Type "tmux -L demo set -g status-right '#(~/GitHub/tomux/scripts/status.sh ~/GitHub/tomux) | %H:%M'"
Enter
Sleep 200ms
Type "tmux -L demo set -g @tomux_show_activity 1"
Enter
Sleep 200ms
Type "tmux -L demo set -g status-interval 2"
Enter
Sleep 500ms
Type "tmux -L demo attach -t demo"
Enter
Sleep 2s

# Inside tmux now
Type "echo '🔲 Tomux Demo — watch the pips in the status bar'"
Enter
Sleep 2s

# Init plan
Type "bash ~/GitHub/tomux/scripts/demo-steps.sh init"
Enter
Sleep 4s

# Phase 1 progress
Type "bash ~/GitHub/tomux/scripts/demo-steps.sh ph1-progress"
Enter
Sleep 4s

Type "bash ~/GitHub/tomux/scripts/demo-steps.sh ph1-more"
Enter
Sleep 4s

# Complete phase 1
Type "bash ~/GitHub/tomux/scripts/demo-steps.sh ph1-done"
Enter
Sleep 4s

# Phase 2 progress
Type "bash ~/GitHub/tomux/scripts/demo-steps.sh ph2-progress"
Enter
Sleep 4s

# Show the detail pane
Ctrl+b
Sleep 300ms
Shift+t
Sleep 5s

# Complete phase 2
Type "bash ~/GitHub/tomux/scripts/demo-steps.sh ph2-done"
Enter
Sleep 4s

# Complete phase 3
Type "bash ~/GitHub/tomux/scripts/demo-steps.sh ph3-done"
Enter
Sleep 4s

Type "echo '🔲 github.com/vaughanknight/tomux'"
Enter
Sleep 3s

# Clean exit
Type "exit"
Enter
Sleep 500ms
Type "tmux -L demo kill-server 2>/dev/null; true"
Enter
Sleep 1s


