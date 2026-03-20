
## Tomux Progress Tracking

This project uses [Tomux](https://github.com/vaughanknight/tomux) for
tmux-based progress visualisation. Read `TOMUX_AGENT_GUIDANCE.md` in the
project root for the data contract — it defines how to create structured
todos and phases that Tomux can display as coloured pips in the tmux status bar.

When working on tasks, follow the guidance to:
- Create phases with short IDs (ph1, ph2, etc.)
- Create todos with phase-prefixed IDs (ph1-t01, ph2-scaffold)
- Update session_state with activity context
- Clean up old todos when starting new work
