# Tomux — tmux Progress Visualisation Plugin

📚 This specification incorporates findings from `research-dossier.md`, `deep-research-multiline-status.md`, and `deep-research-pane-toggle.md`.

---

## Research Context

- **Components affected**: tmux status bar (status-right or status-format[N]), optional detail pane, Copilot CLI session databases (read-only)
- **Critical dependencies**: sqlite3 CLI (pre-installed on macOS/Linux), tmux 3.2+, TPM (Tmux Plugin Manager)
- **Modification risks**: Process tree walking has platform differences (macOS vs Linux). Multi-line status bar replaces `status-left`/`status-right` semantics with `status-format[N]` — must preserve user's existing config.
- **Link**: See `research-dossier.md` for full analysis (641 lines, 70 findings across 7 subagents)

---

## Summary

Tomux is a native tmux plugin that gives developers **real-time visibility** into what their AI coding agent is doing. When a Copilot CLI session is active for the current terminal pane, Tomux automatically discovers it and renders phase/task progress as coloured pip indicators (■□) in the tmux status bar. An optional toggleable detail pane shows the full task breakdown.

**Why**: When an AI agent is working on a complex plan — asking 20 clarification questions, running 4 parallel research subagents, or implementing a 5-phase plan — developers have no at-a-glance way to see progress. They must scroll through the conversation or check markdown files. Tomux solves this by surfacing the agent's todo/phase state directly in the terminal UI where developers already live.

**How it works**: The Copilot CLI already writes todo items and session state to a per-session SQLite database. Tomux reads this database (never writes to it) and renders a compact visual summary. An agent guidance file (`TOMUX_AGENT_GUIDANCE.md`) instructs AI agents to create well-structured todos that Tomux can display effectively.

---

## Goals

1. **At-a-glance progress visibility** — Developers see phase and task progress as coloured pips in their tmux status bar without switching context
2. **Automatic session discovery** — Plugin detects the active Copilot session for the current terminal pane via CWD-to-session matching (no manual config needed)
3. **Two-level hierarchy** — Show phases (green pips) and tasks within the active phase (blue pips) side-by-side; collapse to flat task pips when only one phase exists
4. **Rich status colours** — Green (phase complete), blue (task complete), amber (in-progress), red (blocked), yellow (warning/question), empty (pending)
5. **Configurable overflow** — Switch from individual pips to compact fractions (e.g., `3/20`) when item count exceeds a configurable threshold (default 10 for phases, 10 for tasks)
6. **Toggleable detail pane** — Hotkey (default `prefix + T`) opens/closes a detail pane showing phase names, task names, and status icons
7. **Flexible status bar placement** — Render in the user's existing status-right (default) OR on a dedicated second status line (configurable) for users with crowded status bars
8. **Current phase indicator** — Optionally show the text description of the current phase/activity alongside the pips (configurable)
9. **Zero-config basic experience** — Install via TPM, add `#{tomux_status}` to status-right, and it works. All advanced features are opt-in.
10. **Agent guidance file** — A `TOMUX_AGENT_GUIDANCE.md` template that developers drop into their project to instruct AI agents to create well-structured phase/task data
11. **Cross-platform** — Works on macOS, Linux, and WSL with no additional dependencies beyond sqlite3 and standard POSIX tools
12. **TPM-compatible** — Standard TPM plugin lifecycle: install, update, and keybinding registration

---

## Non-Goals

1. **Writing to the Copilot session database** — Tomux is a read-only observer. Users cannot mark tasks done from tmux (may be added in future)
2. **Custom tmux theme integration** — Tomux uses configurable tmux colour names, not theme-aware colour resolution. Users configure colours via `@tomux_colour_*` options
3. **Multi-session aggregation** — Each pane shows its own session's progress. No cross-session dashboards or combined views
4. **Sub-second real-time updates** — Default refresh is 5 seconds (configurable). This is a status display, not a live stream
5. **Process tree walking on every refresh** — Process detection may be cached or run on a slower cadence than DB reads to minimise overhead
6. **Notification/alerting** — No desktop notifications, bells, or sounds when tasks complete
7. **Historical progress tracking** — Shows current state only, not progress over time
8. **Popup-based UI** — The primary detail view is a split pane, not a floating popup (popups are less suitable for persistent reference views)

---

## Complexity

- **Score**: CS-3 (medium)
- **Breakdown**: S=2, I=1, D=1, N=1, F=1, T=1 (Total P=7)
- **Confidence**: 0.85
- **Assumptions**:
  - sqlite3 is available on all target platforms
  - Copilot CLI session DB schema is stable (todos, session_state, todo_deps tables)
  - tmux 3.2+ is the minimum version (multi-line status support confirmed in 2.9+)
  - Phase grouping via todo ID prefix stripping is the stable contract
  - `#()` shell expansion in tmux format strings supports `#[fg=colour]` directives in output
- **Dependencies**:
  - Copilot CLI (writes the session DB that Tomux reads)
  - TPM (Tmux Plugin Manager) for installation
  - sqlite3 CLI tool
  - tmux 3.2+
- **Risks**:
  - **Platform divergence in process tree walking** — `ps` flags and CWD detection differ between macOS/Linux (mitigated by platform detection in helpers.sh)
  - **DB schema changes** — If Copilot CLI changes the session DB schema, Tomux breaks (mitigated by table existence checks and graceful degradation)
  - **tmux colour rendering** — `#[fg=colour]` behaviour in `#()` output needs careful testing across terminal emulators
  - **Multi-line status interaction** — Changing `status` from `on` to `2` replaces `status-left`/`status-right` semantics with `status-format[N]` — could break user's existing status bar if not handled carefully
- **Phases** (suggested):
  1. Core infrastructure — helpers, session discovery, DB query layer
  2. Status bar rendering — pip rendering, overflow, colour formatting
  3. TPM integration — entry point, option registration, format string interpolation
  4. Detail pane — toggle script, auto-refresh renderer, keybinding
  5. Agent guidance — TOMUX_AGENT_GUIDANCE.md template, documentation
  6. Polish — multi-line status support, cross-platform testing, README

---

## Acceptance Criteria

### Session Discovery

1. When a tmux pane's working directory matches a Copilot session's CWD in `session-store.db`, Tomux displays that session's progress in the status bar
2. When no Copilot session matches the current pane's CWD, Tomux displays nothing (or a configurable idle indicator, default: hidden)
3. When a Copilot session's CWD is a parent directory of the pane's CWD, Tomux falls back to that session (parent directory matching)
4. When sqlite3 is not installed or the session DB is missing, Tomux silently shows nothing — no error messages in the status bar

### Status Bar Rendering

5. When a session has 3 done, 1 in-progress, and 2 pending tasks (no phases), the status bar shows: `■■■■□□` with the first 3 green (done), 1 amber (in-progress), and 2 empty (pending)
6. When a session has 2 phases (phase 1: done, phase 2: in-progress with 3/5 tasks done), the status bar shows phase pips followed by task pips: `■■ ■■■□□` (green/amber phases, then blue/empty tasks)
7. When task count exceeds the configurable threshold (default 10), the display switches to fraction mode: e.g., `■■ 7/15` instead of 15 individual task pips
8. Colours are configurable via `@tomux_colour_done`, `@tomux_colour_progress`, `@tomux_colour_blocked`, `@tomux_colour_task_done`, `@tomux_colour_pending`, `@tomux_colour_warning` — all with sensible defaults
9. Pip characters are configurable via `@tomux_pip_filled` and `@tomux_pip_empty` — default: `■` and `□`
10. When `@tomux_show_activity` is enabled, the current phase/activity description text appears alongside the pips

### Status Bar Placement

11. By default, Tomux provides a `#{tomux_status}` format variable that users embed in their `status-right` — the plugin does NOT overwrite the user's status bar content
12. When `@tomux_use_status_line` is set to `1`, Tomux adds a dedicated second status line (`status 2`, `status-format[1]`) instead of embedding in the existing status bar
13. When switching to dedicated status line mode, Tomux saves the original `status` value and restores it on disable/uninstall
14. The status bar side (left vs right alignment) is configurable via `@tomux_align` (default: `right`)

### Detail Pane

15. Pressing the configurable hotkey (default `prefix + T`) toggles a detail pane that shows phase names, task titles, and status icons (✓ done, ◐ in-progress, ✕ blocked, ○ pending)
16. Pressing the same hotkey again closes the detail pane and restores the original layout
17. The detail pane auto-refreshes at the configured interval (default 5 seconds)
18. The detail pane position (bottom or right) and size are configurable via `@tomux_pane_position` and `@tomux_pane_size`
19. If the user manually closes the detail pane (e.g., `kill-pane`), the next hotkey press creates a fresh one (stale pane ID detection)
20. Focus returns to the original pane after the detail pane is created — the user's cursor position is not disrupted

### Agent Guidance

21. The project includes a `TOMUX_AGENT_GUIDANCE.md` template file that, when placed in a project directory, instructs AI agents to: (a) create todos with phase-prefixed IDs for grouping, (b) update session_state with activity context, (c) use standard status values
22. Without the agent guidance file, Tomux still works — it displays whatever todos exist in the session DB, just without structured phase grouping

### Configuration

23. All configurable options use the `@tomux_` prefix and have documented defaults
24. The plugin works out of the box with zero configuration beyond adding `#{tomux_status}` to the user's status bar format string
25. The refresh interval is configurable via `@tomux_refresh_interval` (default: `5` seconds)

### Cross-Platform

26. The plugin works on macOS (Darwin) using `lsof` for CWD fallback detection
27. The plugin works on Linux using `/proc/{pid}/cwd` for CWD detection
28. The plugin works on WSL (treated as Linux)
29. Platform detection is automatic — no user configuration required

### Performance

30. A full refresh cycle (session discovery + DB query + rendering) completes in under 500ms on commodity hardware
31. Cached results are reused when the underlying data hasn't changed, avoiding unnecessary re-rendering

### Graceful Degradation

32. When the Copilot session DB has no `todos` table, Tomux shows nothing
33. When the session DB is locked (concurrent access), Tomux retries or shows cached data — never hangs
34. When tmux version is below 3.2, the plugin still works for status bar mode but disables multi-line status and popup features

---

## Risks & Assumptions

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Copilot CLI changes session DB schema | Low | High | Table existence checks; column presence detection; graceful null returns |
| sqlite3 not installed on target system | Low | High | `command -v sqlite3` check; show nothing if absent |
| Process tree walking fails on exotic shell setups | Medium | Low | CWD-based matching works independently; process tree is optional optimisation |
| tmux `#()` colour rendering differs across terminals | Medium | Medium | Test on iTerm2, Terminal.app, Alacritty, kitty; provide fallback to no-colour mode |
| Multi-line status bar breaks user's existing config | Medium | High | Default to inline mode (status-right); multi-line is opt-in; save/restore original state |
| Agent doesn't follow guidance (bad todo IDs) | Medium | Low | Flat display still works without phase grouping; guidance is advisory |
| Pane toggle layout restoration fails in complex layouts | Low | Medium | tmux auto-restores for simple splits; save `#{window_layout}` for complex cases |

**Assumptions**:
- Users are running tmux 3.2+ (released 2021; widely available)
- sqlite3 is pre-installed (true for macOS; almost always true for Linux)
- The Copilot CLI session-store.db lives at `~/.copilot/session-store.db` (standard path)
- Per-session DBs live at `~/.copilot/session-state/{uuid}/session.db` (standard path)
- The `todos` table uses the schema: `id TEXT PRIMARY KEY, title TEXT, status TEXT`
- Phase grouping works by stripping the last `-segment` from todo IDs

---

## Resolved Questions

> All open questions resolved via `/plan-2-clarify` on 2026-03-19.

1. **[RESOLVED: Phase table vs ID-prefix grouping]** — Use phases table for grouping when available; fall back to ID-prefix grouping (strip last `-segment`) when phases table is missing. This handles both structured projects (with guidance) and unstructured ones (flat display with prefix-based best-effort grouping).

2. **[RESOLVED: Amber vs Yellow distinction]** — Default to 256-colour codes (`colour214` for amber, `colour226` for yellow). Accept that they look the same on 16-colour terminals — users can override via `@tomux_colour_*` options. No auto-detection or dual palette.

3. **[RESOLVED: Per-pane vs per-window display]** — Show the **active (focused) pane's** session. Switches on pane focus change. The status bar always reflects the pane the user is currently working in.

4. **[RESOLVED: Detail pane in multi-pane windows]** — Configurable: default is **bottom of window** (predictable). Option `@tomux_pane_position` supports `bottom` (of window) and `right`. Future: `below-active` for context-aware positioning.

### Additional Clarifications

5. **[RESOLVED: Workflow mode]** — **Full (B)**: multi-phase plan with all quality gates. This is CS-3 with a novel data contract — structure is warranted.

6. **[RESOLVED: Testing strategy / mock policy]** — **Targeted mocks**: mock tmux commands and filesystem; use real sqlite3 against fixture databases. No headless tmux server for unit tests.

7. **[RESOLVED: Process tree walking]** — **Always walk process tree** on every refresh. The ~92ms cost is within budget and prevents showing stale data when copilot isn't running. No caching — fresh walk each cycle.

8. **[RESOLVED: README scope]** — **Comprehensive**: installation, configuration reference, screenshots/examples, troubleshooting, architecture overview, contributing guide, agent guidance tutorial.

---

## ADR Seeds (Optional)

### ADR-001: Session Discovery Strategy
- **Decision Drivers**: Cross-platform compatibility, per-pane isolation, minimal dependencies
- **Candidate Alternatives**:
  - A: CWD-only matching (simple but can't distinguish multiple sessions with same CWD)
  - B: Process tree + CWD matching (trex approach — more robust, slightly more complex)
  - C: File-lock-based detection (copilot creates a lock file — would require copilot changes)
- **Stakeholders**: Plugin users, Copilot CLI team

### ADR-002: Status Bar Integration Pattern
- **Decision Drivers**: Must not break existing user config (P-6), support crowded status bars
- **Candidate Alternatives**:
  - A: Format string interpolation (`#{tomux_status}` → `#(script.sh)`) — user embeds marker
  - B: Dedicated status line (`status 2` + `status-format[1]`) — completely separate line
  - C: Both, user-configurable — default to interpolation, opt-in to dedicated line
- **Stakeholders**: Plugin users, other tmux plugin authors

### ADR-003: Pip Rendering Architecture
- **Decision Drivers**: Performance (must complete in <500ms), configurability, terminal compatibility
- **Candidate Alternatives**:
  - A: Build format string with `#[fg=colour]` directives inline — single script output
  - B: Pre-render to tmux environment variable, read from format string — decoupled caching
  - C: Write to temp file, `cat` from format string — filesystem-based caching
- **Stakeholders**: Plugin users, performance-sensitive users

---

## External Research

- **Incorporated**:
  - `deep-research-multiline-status.md` (378 lines) — tmux multi-line status bar mechanics
  - `deep-research-pane-toggle.md` (248 lines) — pane toggle pattern with hotkey
- **Key Findings**:
  - Multi-line status introduced in tmux 2.9; line 0 = topmost, counterintuitive numbering
  - `status-format[N]` fully replaces `status-left`/`status-right` when multi-line is active
  - Pane identification best done via window user option + pane title
  - tmux auto-restores layout for simple splits (no explicit save/restore needed)
- **Applied To**: Goals §7 (status bar placement), AC §11-14 (status bar placement), AC §15-20 (detail pane), Risks (multi-line config interaction)

---

## Unresolved Research

*None — both external research opportunities identified in `research-dossier.md` have been addressed.*

---

## Workshop Opportunities

| Topic | Type | Why Workshop | Key Questions |
|-------|------|--------------|---------------|
| Agent Guidance Contract | Data Model | The `TOMUX_AGENT_GUIDANCE.md` needs to define a precise contract for how AI agents should create todos/phases. Getting this wrong means the visual display is useless. | 1. What exact SQL should agents execute? 2. How should batch operations (20 questions) be structured? 3. How should parallel subagent work be tracked? 4. Should the guidance file be a skill/command or just documentation? |
| Configuration Schema | API Contract | 20+ `@tomux_*` options need consistent naming, sensible defaults, and clear documentation. The option namespace IS the plugin's public API. | 1. What's the full option list with defaults? 2. How should colour options work (named vs 256-colour index)? 3. Should we support a "preset" option for bundled configurations? 4. How to document options in README? |
| Pip Rendering Engine | State Machine | The rendering logic has multiple modes (pips vs fractions), two levels (phases + tasks), configurable thresholds, and 6 status colours. It's the visual core of the plugin. | 1. Exact format string output for each state combination? 2. How to handle the transition from pips to fractions? 3. What does "1 phase, 5 tasks" look like vs "3 phases, 12 tasks"? 4. What separates phases from tasks visually? |

**Complexity guidance**: At CS-3, workshops are recommended for the Agent Guidance Contract (it defines the data quality Tomux depends on) and optionally for the Configuration Schema and Pip Rendering Engine.

---

*Spec ready for clarification via `/plan-2-clarify`.*
