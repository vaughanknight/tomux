<div align="center">

# 🔲 Tomux

**Real-time AI agent progress in your tmux status bar.**

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![tmux: 3.2+](https://img.shields.io/badge/tmux-3.2%2B-green.svg)](https://github.com/tmux/tmux)
[![TPM Compatible](https://img.shields.io/badge/TPM-compatible-brightgreen.svg)](https://github.com/tmux-plugins/tpm)
[![Bash: 3.2+](https://img.shields.io/badge/bash-3.2%2B-orange.svg)](#)
[![Tests: 32 passing](https://img.shields.io/badge/tests-32%20passing-success.svg)](#testing)

<br>

<img src="demo.gif" alt="Tomux demo showing pip progress in tmux status bar" width="700">

<br>

*Phase pips (green) and task pips (blue) updating live as the AI agent works through a plan.*

</div>

---

Tomux is a tmux plugin that visualises [GitHub Copilot CLI](https://githubnext.com/projects/copilot-cli/) agent progress directly in your status bar. When Copilot executes multi-phase plans — clarification questions, parallel research, phased implementation — Tomux renders coloured pips (■□) so you see progress at a glance without leaving the terminal.

```
■■■□□ ■■■□□□□  Implementing Phase 3
 ↑       ↑              ↑
phases  tasks       activity text
```

---

## Features

- **Phase pips** — each plan phase rendered as a coloured block (■ done, ● in-progress, □ pending)
- **Task pips** — per-phase task progress alongside phase pips
- **Activity text** — optional current-work description in the status bar
- **Overflow mode** — switches to compact fractions (`7/15`) when counts exceed thresholds
- **Detail pane** — press `prefix+T` for a full task breakdown in a split pane
- **Dedicated status line** — opt-in second status line for distraction-free display
- **Zero-config** — works immediately with sensible defaults
- **Read-only** — never writes to Copilot databases
- **Graceful degradation** — silent empty output when Copilot isn't running
- **Bash 3.2 compatible** — works on stock macOS without upgrades
- **Colour customisation** — override every colour via tmux options

---

## Quick Start

### 1. Install via TPM

Add to your `~/.tmux.conf`:

```tmux
set -g @plugin 'vaughanknight/tomux'
```

Press `prefix + I` to install.

### 2. Add to your status bar

```tmux
set -g status-right "#{tomux_status} | %H:%M"
```

### 3. Reload tmux

```bash
tmux source-file ~/.tmux.conf
```

That's it. Tomux will automatically detect Copilot CLI sessions in your current pane's working directory and render progress pips.

---

## Agent Setup

For Tomux to display meaningful progress data, the AI agent needs to write structured phase/task data. There are three ways to set this up:

### Option A: Copy the guidance file

```bash
cp /path/to/tomux/templates/TOMUX_AGENT_GUIDANCE.md ./TOMUX_AGENT_GUIDANCE.md
```

The agent will read this file and follow the contract for creating phases, todos, and session state.

### Option B: Add a pointer to copilot-instructions

Add this line to `.github/copilot-instructions.md` in your project:

```markdown
Read and follow the rules in TOMUX_AGENT_GUIDANCE.md in the project root.
It defines how to structure todos and phases so the Tomux tmux plugin can
display your progress.
```

### Option C: Use the /tomux-init skill

If the project includes a `/tomux-init` skill, invoke it to automatically set up the guidance file and instructions pointer.

---

## Configuration Reference

All options use the `@tomux_` prefix with sensible defaults. Set them in `~/.tmux.conf`.

### Display & Rendering

| Option | Default | Description |
|--------|---------|-------------|
| `@tomux_pip_filled` | `■` | Character for completed/in-progress items |
| `@tomux_pip_empty` | `□` | Character for pending items |
| `@tomux_refresh_interval` | `5` | Status bar refresh cycle in seconds |
| `@tomux_show_activity` | `0` | Show activity text after pips (`1` to enable) |
| `@tomux_activity_max_length` | `30` | Truncate activity text to N characters |

### Colours

| Option | Default | Description |
|--------|---------|-------------|
| `@tomux_colour_done` | `green` | Completed phase/task colour |
| `@tomux_colour_progress` | `colour214` | In-progress colour (amber) |
| `@tomux_colour_blocked` | `red` | Blocked status colour |
| `@tomux_colour_task_done` | `blue` | Completed task pip colour |
| `@tomux_colour_pending` | `default` | Pending/empty pip colour |
| `@tomux_colour_warning` | `colour226` | Stale session warning colour (yellow) |

### Overflow Thresholds

| Option | Default | Description |
|--------|---------|-------------|
| `@tomux_phase_threshold` | `10` | Switch phases to fraction mode above N |
| `@tomux_task_threshold` | `10` | Switch tasks to fraction mode above N |

### Status Bar Placement

| Option | Default | Description |
|--------|---------|-------------|
| `@tomux_align` | `right` | Status bar alignment (`left` or `right`) |
| `@tomux_use_status_line` | `0` | Use dedicated status line 2 (`1` to enable) |

### Detail Pane

| Option | Default | Description |
|--------|---------|-------------|
| `@tomux_pane_position` | `bottom` | Detail pane location (`bottom` or `right`) |
| `@tomux_pane_size` | `20` | Detail pane height/width in lines/columns |
| `@tomux_hotkey` | `T` | Toggle key for detail pane (bound as `prefix+T`) |

---

## How It Works

Tomux is a **read-only observer** that polls Copilot CLI's SQLite databases on a timer:

```
tmux status bar
  │  #{tomux_status} — shell expansion every N seconds
  ▼
scripts/status.sh
  │  1. Get current pane's working directory
  │  2. Look up session UUID in ~/.copilot/session-store.db
  │  3. Query ~/.copilot/session-state/{uuid}/session.db
  │  4. Read phases, todos, session_state tables
  │  5. Render coloured pip string
  ▼
Output: "#[fg=green]■■#[fg=colour214]■#[fg=default]□□"
```

**Key databases:**

| Database | Location | Contents |
|----------|----------|----------|
| Session store | `~/.copilot/session-store.db` | Maps CWD → session UUID |
| Session DB | `~/.copilot/session-state/{uuid}/session.db` | Todos, phases, state |

Tomux **never writes** to these databases. All data is created by the AI agent following the guidance contract.

---

## Display Modes

### Inline (Default)

Embed `#{tomux_status}` anywhere in your status bar:

```tmux
set -g status-right "#{tomux_status} | %H:%M"
```

Output: `■■●□□ ■■■□ | 14:30`

### Dedicated Status Line

Use a second tmux status line for a cleaner look:

```tmux
set -g @tomux_use_status_line 1
```

This renders Tomux on `status 2`, keeping your main status bar untouched. Tomux saves and restores your original status line configuration on unload.

### Detail Pane

Press `prefix+T` (configurable via `@tomux_hotkey`) to toggle a split pane showing the full task breakdown with ANSI-coloured output:

```
┌──────────────────────────────────────┐
│  your terminal session               │
│                                      │
├──────────────────────────────────────┤
│  Phase 1: Scaffold         ■ done   │
│    ✓ Create project structure        │
│    ✓ Install dependencies            │
│    ✓ Configure toolchain             │
│  Phase 2: Core Logic        ● wip   │
│    ✓ Data models                     │
│    → Business logic                  │
│    ○ Event handlers                  │
│    ○ Error handling                  │
│  Phase 3: API Routes        □ todo  │
│  Phase 4: Tests             □ todo  │
│  Phase 5: Documentation     □ todo  │
└──────────────────────────────────────┘
```

Configure pane placement and size:

```tmux
set -g @tomux_pane_position right   # bottom (default) or right
set -g @tomux_pane_size 25          # height/width in lines/columns
```

---

## Colour Customisation

Override any colour using standard tmux colour names or 256-colour codes:

```tmux
# Use a different green for completed items
set -g @tomux_colour_done colour34

# Bright cyan for in-progress
set -g @tomux_colour_progress colour51

# Muted grey for pending
set -g @tomux_colour_pending colour240

# Use named colours
set -g @tomux_colour_blocked magenta
```

Supported colour formats:
- Named: `red`, `green`, `blue`, `yellow`, `cyan`, `magenta`, `white`, `black`, `default`
- 256-colour: `colour0` through `colour255`

---

## Troubleshooting

### No pips showing

1. **Check tmux version**: Tomux requires tmux 3.2+. Run `tmux -V`.
2. **Check sqlite3**: Run `command -v sqlite3` — it must be in your PATH.
3. **Check format string**: Ensure `#{tomux_status}` is in your `status-right` or `status-left`.
4. **Check Copilot is running**: Tomux only shows data when a Copilot CLI session exists for the current pane's CWD.
5. **Check session store**: Run `sqlite3 ~/.copilot/session-store.db "SELECT id, cwd FROM sessions ORDER BY updated_at DESC LIMIT 5"` to verify sessions exist.

### Wrong session / stale data

- Tomux matches sessions by **exact CWD**, then falls back to parent directory matching.
- If you see stale data, the session may have moved. Check `updated_at` in the session store.
- Stale sessions (>10 minutes with no Copilot process) display in the warning colour.

### Pips show but no phases (flat display)

- The AI agent hasn't created the `phases` table yet. Tomux falls back to flat todo display.
- Ensure `TOMUX_AGENT_GUIDANCE.md` is in your project root so the agent creates structured data.

### Activity text not showing

- Set `@tomux_show_activity 1` in your tmux config.
- The agent must write to `session_state` with key `activity`.

### Performance feels slow

- Default refresh is 5 seconds (`@tomux_refresh_interval`). Increase for slower machines.
- Tomux caches query results between refreshes via tmux environment variables.
- Target performance budget: <500ms per refresh cycle.

### Detail pane won't toggle

- Check the hotkey: default is `prefix+T`. Verify with `tmux list-keys | grep tomux`.
- If the pane was manually closed, Tomux detects the stale pane ID and recreates it.

---

## Contributing

### Development Setup

```bash
git clone https://github.com/vaughanknight/tomux.git
cd tomux

# Generate test fixture databases
make fixtures

# Run linter (shellcheck)
make lint

# Run tests (bats)
make test

# Clean up
make clean
```

### Project Structure

```
tomux/
├── tomux.tmux              # TPM entry point
├── scripts/
│   ├── helpers.sh          # Shared utilities, pip rendering
│   ├── session_discovery.sh # CWD → session UUID lookup
│   ├── db_query.sh         # SQLite read-only access layer
│   ├── status.sh           # Status bar renderer
│   ├── pane.sh             # Detail pane renderer
│   └── toggle.sh           # Pane toggle handler
├── templates/
│   └── TOMUX_AGENT_GUIDANCE.md  # Agent guidance contract
├── tests/
│   ├── unit/               # bats unit tests
│   ├── integration/        # bats integration tests
│   └── fixtures/           # Test databases & mocks
├── docs/                   # Architecture & project rules
├── Makefile                # test, lint, fixtures, clean
└── README.md
```

### Coding Standards

- **Bash 3.2 compatible** — no associative arrays, `mapfile`, namerefs, `${var,,}`, or `|&`
- **shellcheck clean** — zero warnings
- **Quote all expansions** — `"${var}"` not `$var`
- **`local` for function variables** — prevent scope leaks
- **`[[ ]]` for conditionals** — not `[ ]`
- **Read-only database access** — never write to Copilot databases

### Testing

Tests use [bats-core](https://github.com/bats-core/bats-core) with fixture databases generated by `make fixtures`. Every promoted test includes a doc comment explaining *why* it exists, the contract it verifies, and a worked example.

```bash
make test        # Run all tests
make lint        # shellcheck all scripts
make fixtures    # Regenerate fixture databases
```

---

## License

MIT License. See [LICENSE](LICENSE) for details.
