# Tomux Demo — VHS Tape
# Generates demo.gif showing pip progress in tmux status bar
# Run: vhs demo.tape

Output demo.gif

Set Shell "bash"
Set FontSize 14
Set Width 900
Set Height 500
Set Theme "Dracula"
Set Padding 20
Set TypingSpeed 40ms

# Title
Type "# Tomux — AI Agent Progress in tmux"
Enter
Sleep 1s

# Show what pips look like
Type "echo ''"
Enter
Type "echo '  Status bar examples:'"
Enter
Type "echo ''"
Enter

# Simulate pip rendering with printf colours
Type@50ms "printf '  \033[32m■■■\033[33m■\033[0m□□  \033[34m■■■■\033[33m■\033[0m□□□  Phase 3: Rendering\n'"
Enter
Sleep 1.5s

Type@50ms "printf '  \033[32m■■■■■\033[0m   \033[34m■■\033[33m■\033[0m□□□□  7 subagents running\n'"
Enter
Sleep 1.5s

Type@50ms "printf '  \033[34m■■■■■■■■■■\033[0m            All tasks done!\n'"
Enter
Sleep 2s

Type "echo ''"
Enter

# Show installation
Type "echo '━━━ Installation ━━━'"
Enter
Sleep 500ms
Type "echo ''"
Enter
Type@30ms "echo '# Add to ~/.tmux.conf:'"
Enter
Type@30ms "echo 'set -g @plugin '\\''vaughanknight/tomux'\\'''"
Enter
Type@30ms "echo 'set -g status-right \"#{tomux_status} | %H:%M\"'"
Enter
Sleep 2s

Type "echo ''"
Enter

# Show configuration options
Type "echo '━━━ Configuration ━━━'"
Enter
Sleep 500ms
Type@30ms "echo '@tomux_pip_filled    ■  (configurable)'"
Enter
Type@30ms "echo '@tomux_pip_empty     □  (configurable)'"
Enter
Type@30ms "echo '@tomux_show_activity 1  (show phase text)'"
Enter
Type@30ms "echo '@tomux_toggle_key    T  (prefix+T for details)'"
Enter
Sleep 2s

Type "echo ''"
Enter

# Simulate the detail pane output
Type "echo '━━━ Detail Pane (prefix+T) ━━━'"
Enter
Sleep 500ms
Type "echo ''"
Enter
Type@20ms "printf '  \033[1m═══ Tomux Progress ═══\033[0m\n'"
Enter
Type@20ms "printf '  \033[1mPhase 1: Core\033[0m \033[32m[done]\033[0m\n'"
Enter
Type@20ms "printf '    \033[32m✓\033[0m Create helpers.sh\n'"
Enter
Type@20ms "printf '    \033[32m✓\033[0m Session discovery\n'"
Enter
Type@20ms "printf '    \033[32m✓\033[0m DB query layer\n'"
Enter
Type@20ms "printf '  \033[1mPhase 2: Rendering\033[0m \033[33m[in progress]\033[0m\n'"
Enter
Type@20ms "printf '    \033[32m✓\033[0m Render pips\n'"
Enter
Type@20ms "printf '    \033[32m✓\033[0m Overflow logic\n'"
Enter
Type@20ms "printf '    \033[33m◐\033[0m Colour mapping\n'"
Enter
Type@20ms "printf '    \033[90m○\033[0m Caching\n'"
Enter
Type@20ms "printf '    \033[90m○\033[0m Staleness\n'"
Enter
Type@20ms "printf '  \033[1mPhase 3: Integration\033[0m \033[90m[pending]\033[0m\n'"
Enter
Sleep 3s

Type "echo ''"
Enter
Type@30ms "echo '🔲 github.com/vaughanknight/tomux'"
Enter
Sleep 3s
