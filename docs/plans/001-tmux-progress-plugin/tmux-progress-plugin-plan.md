# Tomux — tmux Progress Visualisation Plugin Implementation Plan

**Plan Version**: 1.0.0
**Created**: 2026-03-19
**Spec**: [tmux-progress-plugin-spec.md](./tmux-progress-plugin-spec.md)
**Status**: DRAFT
**Workshops**:
- [agent-guidance-contract.md](./workshops/agent-guidance-contract.md) — Agent Guidance Contract

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Technical Context](#technical-context)
3. [Critical Research Findings](#critical-research-findings)
4. [Testing Philosophy](#testing-philosophy)
5. [Project Structure](#project-structure)
6. [Implementation Phases](#implementation-phases)
   - [Phase 1: Core Infrastructure](#phase-1-core-infrastructure)
   - [Phase 2: Status Bar Rendering](#phase-2-status-bar-rendering)
   - [Phase 3: TPM Integration](#phase-3-tpm-integration)
   - [Phase 4: Detail Pane](#phase-4-detail-pane)
   - [Phase 5: Agent Guidance & Skill](#phase-5-agent-guidance--skill)
   - [Phase 6: Polish & Documentation](#phase-6-polish--documentation)
7. [Cross-Cutting Concerns](#cross-cutting-concerns)
8. [Complexity Tracking](#complexity-tracking)
9. [Progress Tracking](#progress-tracking)
10. [Change Footnotes Ledger](#change-footnotes-ledger)

---

## Executive Summary

**Problem**: When an AI coding agent executes complex plans — asking 20 questions, launching 7 parallel subagents, or implementing a 5-phase plan — developers have no at-a-glance way to see progress. They must scroll conversation output or check markdown files.

**Solution**: Tomux is a native tmux plugin (pure bash + sqlite3) that reads the Copilot CLI session database and renders phase/task progress as coloured pip indicators (■□) in the tmux status bar. An optional detail pane shows the full task breakdown. An agent guidance file instructs AI agents to create well-structured data.

**Approach**:
- 6-phase implementation following dependency chain: foundation → rendering → integration → features → guidance → polish
- TAD (Test-Assisted Development) with targeted mocks: mock tmux commands, use real sqlite3 against fixture DBs
- Read-only observer (P-1): never writes to Copilot databases
- Bash 3.2 compatible (macOS constraint)

**Expected Outcomes**:
- TPM-installable plugin that works zero-config with `#{tomux_status}` in status-right
- Coloured pip display showing phase + task progress side-by-side
- Toggleable detail pane (prefix+T) showing full task breakdown
- Agent guidance template for structured todo/phase creation
- Cross-platform: macOS, Linux, WSL

---

## Technical Context

### Current System State
- **Project**: Empty — no existing code (greenfield)
- **Reference**: trex project (sibling at `../trex` relative to project root) provides proven session discovery and data model patterns
- **Environment**: macOS ARM64, tmux 3.6a, sqlite3 3.50.4, bash 3.2.57

### Integration Requirements
- **Copilot CLI session-store.db**: Global index at `~/.copilot/session-store.db` (read-only)
- **Copilot CLI session.db**: Per-session at `~/.copilot/session-state/{uuid}/session.db` (read-only)
- **TPM**: Plugin installed to `~/.tmux/plugins/tomux/`
- **tmux**: Format string `#()` shell expansion for status bar, `bind-key` for hotkeys

### Constraints
- **Bash 3.2**: macOS ships bash 3.2.57 (2007). NO bash 4+ features: no associative arrays, no `mapfile`, no `${var,,}`, no `|&`, no namerefs
- **POSIX tools only**: ps, awk, sed, grep, sqlite3. No jq, python, node
- **Read-only**: Never write to any Copilot database (P-1)
- **Non-invasive**: Never modify user's status-left/status-right directly (P-6)
- **Performance**: <500ms per refresh cycle

### Assumptions
- sqlite3 is pre-installed on target platforms
- tmux 3.2+ (released 2021)
- Copilot CLI session DB schema is stable (mitigated by table existence checks; see Critical Finding 02)
- Users have TPM installed for plugin management

### Copilot CLI Database Schemas (Read-Only)

> These are runtime paths detected via `$HOME` expansion — not part of the plugin codebase.

**Global session index**: `$HOME/.copilot/session-store.db`

```sql
CREATE TABLE sessions (
  id TEXT PRIMARY KEY,        -- Session UUID
  cwd TEXT,                   -- Working directory
  repository TEXT,            -- Git repository
  branch TEXT,                -- Git branch
  summary TEXT,               -- Session summary
  created_at TEXT DEFAULT (datetime('now')),
  updated_at TEXT DEFAULT (datetime('now')),
  host_type TEXT
);
CREATE INDEX idx_sessions_cwd ON sessions(cwd);
```

**Per-session DB**: `$HOME/.copilot/session-state/{uuid}/session.db`

```sql
CREATE TABLE todos (
  id TEXT PRIMARY KEY,        -- e.g., 'ph1-t01'
  title TEXT NOT NULL,
  description TEXT,
  status TEXT DEFAULT 'pending'
    CHECK(status IN ('pending','in_progress','done','blocked')),
  created_at TEXT DEFAULT (datetime('now')),
  updated_at TEXT DEFAULT (datetime('now'))
);

CREATE TABLE todo_deps (
  todo_id TEXT NOT NULL,
  depends_on TEXT NOT NULL,
  PRIMARY KEY (todo_id, depends_on)
);

-- Optional (created by agent guidance):
CREATE TABLE phases (
  id TEXT PRIMARY KEY,        -- e.g., 'ph1'
  name TEXT,                  -- e.g., 'Phase 1: Core Infrastructure'
  ordinal INTEGER,            -- Sort order: 1, 2, 3
  status TEXT DEFAULT 'pending'
    CHECK(status IN ('pending','in_progress','done','blocked'))
);

CREATE TABLE session_state (
  key TEXT PRIMARY KEY,
  value TEXT
);
```

### Exact Commands Reference

```bash
# Linting (all phases)
shellcheck scripts/*.sh tomux.tmux

# Unit tests (Phase 1+)
bats tests/unit/*.bats

# Generate fixtures (Phase 1)
bash tests/fixtures/gen-fixtures.sh

# Integration tests (Phase 3+)
bats tests/integration/*.bats

# Full test suite (Phase 6)
make test    # runs: shellcheck + bats unit + bats integration
make lint    # runs: shellcheck scripts/*.sh tomux.tmux
make fixtures # runs: bash tests/fixtures/gen-fixtures.sh
```

---

## Critical Research Findings

### 🚨 Critical

| # | Finding | Action | Affects |
|---|---------|--------|---------|
| 01 | **Bash 3.2 on macOS** — No associative arrays, mapfile, namerefs | Use indexed arrays and `read` loops only. Test all code on bash 3.2 | All phases |
| 02 | **Session discovery: CWD → UUID** — Global session-store.db maps CWD to session UUID with parent dir fallback | Implement exact CWD match + LIKE fallback query | Phase 1 |
| 03 | **Process tree walk required** — Must detect copilot in pane's process tree to prevent stale display | `ps -eo pid=,ppid=,comm=` + awk BFS from pane PID | Phase 1 |
| 04 | **sqlite3 -readonly not available** — macOS sqlite3 lacks `-readonly` flag | Use `PRAGMA query_only = ON;` or rely on file permissions | Phase 1 |

### ⚠️ High

| # | Finding | Action | Affects |
|---|---------|--------|---------|
| 05 | **Phase grouping dual strategy** — Phases table for grouping when present; ID-prefix fallback when missing | Query phases first, fall back to prefix strip algorithm | Phase 2 |
| 06 | **Multi-line status replaces status-left/right** — Setting `status 2` changes semantics entirely | Default to inline interpolation; multi-line opt-in only, save/restore original | Phase 3 |
| 07 | **tmux #() colour rendering** — `#[fg=colour]` directives in script output ARE treated as format strings | Confirmed working; embed colour codes directly in output | Phase 2 |
| 08 | **Pane toggle: stale ID detection** — User may kill detail pane manually | Check pane existence via `tmux list-panes` before kill, create fresh if stale | Phase 4 |

### ℹ️ Medium

| # | Finding | Action | Affects |
|---|---------|--------|---------|
| 09 | **Tilde expansion fails in double quotes** — `"~/.copilot"` → broken path | Always use `"$HOME/.copilot"` | All phases |
| 10 | **Pipes create subshells** — Variables lost after `|` pipe | Use `while read ... done < <(query)` process substitution | All phases |
| 11 | **Cache via tmux environment** — `tmux set-environment -g` persists across refreshes | Use for caching query results between refresh cycles | Phase 2 |
| 12 | **Staleness detection** — Timestamp + process check for stale data | Dim display if session_state stale >10min AND copilot not in process tree | Phase 2, 6 |
| 13 | **Per-phase task cleanup** — DELETE old phase tasks when moving to next phase | Agent guidance instructs this; Tomux benefits from focused display | Phase 5 |

---

## Testing Philosophy

### Selected Approach: TAD (Test-Assisted Development)

**From constitution**: Tests are executable documentation that prove contracts and catch regressions. Tests must "pay rent" through comprehension value.

**Mock Policy**: Targeted — mock tmux commands and filesystem; use real sqlite3 against fixture databases.

### TAD Workflow Per Phase

1. **Scratch phase**: Write probe tests in `tests/scratch/` for fast exploration
2. **RUN-Implement-Fix loop**: Execute scratch tests repeatedly (RED→GREEN cycles)
3. **Promote**: Move 1-2 valuable tests per feature (~5-10% promotion rate) to `tests/unit/`
4. **Document**: Add Test Doc comment blocks to promoted tests (Why/Contract/Usage/Quality/Example)
5. **Delete**: Remove non-valuable scratch tests (90-95%)

### Test Infrastructure

- **Framework**: bats-core
- **Fixtures**: SQLite databases generated by `tests/fixtures/gen-fixtures.sh` (reproducible)
- **Mocks**: `tests/fixtures/mocks.sh` — mock tmux commands for isolated unit testing
- **CI**: `tests/scratch/` excluded from CI; promoted tests must be deterministic

---

## Project Structure

```
tomux/
├── tomux.tmux                         # TPM entry point (Phase 3)
├── scripts/
│   ├── helpers.sh                     # Shared utilities (Phase 1)
│   ├── session_discovery.sh           # CWD → session UUID (Phase 1)
│   ├── db_query.sh                    # SQLite query layer (Phase 1)
│   ├── status.sh                      # Status bar renderer (Phase 2)
│   ├── pane.sh                        # Detail pane renderer (Phase 4)
│   └── toggle.sh                      # Pane toggle handler (Phase 4)
├── templates/
│   └── TOMUX_AGENT_GUIDANCE.md        # Agent guidance template (Phase 5)
├── tests/
│   ├── scratch/                       # Fast probes (.gitignored)
│   ├── unit/                          # Promoted tests with Test Doc
│   ├── integration/                   # Full lifecycle tests
│   └── fixtures/
│       ├── gen-fixtures.sh            # Reproducible DB generation
│       ├── mocks.sh                   # tmux command mocks
│       ├── basic.db                   # 1 phase, 3 tasks
│       ├── multiphase.db              # 3 phases, mixed statuses
│       ├── overflow.db                # 15 tasks (overflow test)
│       ├── flat-nophases.db           # No phases table
│       └── empty.db                   # Empty session
├── docs/
│   ├── project-rules/                 # Constitution, rules, idioms, arch
│   └── plans/001-tmux-progress-plugin/
│       ├── tmux-progress-plugin-spec.md
│       ├── tmux-progress-plugin-plan.md  # THIS FILE
│       ├── research-dossier.md
│       ├── deep-research-multiline-status.md
│       ├── deep-research-pane-toggle.md
│       ├── workshops/
│       │   └── agent-guidance-contract.md
│       └── tasks/                     # Phase dossiers (created by plan-5)
├── TOMUX_AGENT_GUIDANCE.md            # Project-level guidance (Phase 5)
├── README.md                          # Comprehensive docs (Phase 6)
├── Makefile                           # test, lint, install targets (Phase 6)
└── .gitignore                         # Exclude tests/scratch/, *.db caches
```

---

## Implementation Phases

### Phase 1: Core Infrastructure

**Objective**: Build the three foundation scripts that all other phases depend on — helpers, session discovery, and database query layer.

**Deliverables**:
- `scripts/helpers.sh` — 6 core functions: get_tmux_option, colour_code, render_pips, overflow_pips, format_activity, detect_platform
- `scripts/session_discovery.sh` — 3 core functions: find_session_id, get_session_db_path, has_copilot_process
- `scripts/db_query.sh` — 4 core functions: query_session_db, get_todos, get_phases, get_session_state
- Test fixtures: 3 SQLite databases (basic, flat, empty)
- Test mocks: tmux command mocks

**Dependencies**: None (foundational phase)

**Risks**:
| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Process tree walk differs macOS vs Linux | High | Medium | Platform detection in detect_platform(), conditional ps flags |
| Bash 3.2 compatibility issues | High | High | No bash 4+ features; test on /bin/bash explicitly |
| sqlite3 query timeout on locked DB | Medium | Medium | `.timeout 2000` pragma; return empty on failure |

### Tasks (TAD Approach)

| # | Status | Task | CS | Success Criteria | Log | Notes |
|---|--------|------|----|------------------|-----|-------|
| 1.1 | [ ] | Create project scaffold (dirs, .gitignore, Makefile skeleton) | 1 | All dirs exist, .gitignore excludes scratch/ and *.db caches | - | |
| 1.2 | [ ] | Create tests/fixtures/gen-fixtures.sh with 3 fixture DBs | 2 | basic.db, flat-nophases.db, empty.db generated reproducibly | - | |
| 1.3 | [ ] | Create tests/fixtures/mocks.sh with tmux command mocks | 1 | mock_tmux_option, mock_tmux_display functions available | - | |
| 1.4 | [ ] | Write scratch probes for helpers.sh functions | 2 | 10-15 probes covering get_tmux_option, render_pips, overflow, colour_code | - | |
| 1.5 | [ ] | Implement scripts/helpers.sh (6 functions, bash 3.2 compatible) | 3 | All scratch tests pass; shellcheck clean | - | |
| 1.6 | [ ] | Write scratch probes for session_discovery.sh | 2 | 8-10 probes covering CWD match, parent fallback, process tree | - | |
| 1.7 | [ ] | Implement scripts/session_discovery.sh (3 functions) | 3 | find_session_id returns UUID from fixture; has_copilot_process works on macOS | - | |
| 1.8 | [ ] | Write scratch probes for db_query.sh | 2 | 8-10 probes covering three-gate guard, all query functions | - | |
| 1.9 | [ ] | Implement scripts/db_query.sh (4 functions) | 2 | All queries return expected data from fixture DBs; graceful on missing tables | - | |
| 1.10 | [ ] | Promote 3-5 valuable tests to tests/unit/ with Test Doc blocks | 2 | render_pips contract, session discovery contract, three-gate guard | - | |
| 1.11 | [ ] | Run shellcheck on all 3 scripts | 1 | Zero warnings | - | |

### Acceptance Criteria
- [ ] All 3 foundation scripts pass shellcheck
- [ ] render_pips(3, 5, "blue", "■", "□") returns exactly 5 pip characters with correct colours
- [ ] find_session_id returns correct UUID from fixture session-store.db
- [ ] has_copilot_process returns 0/1 correctly on macOS
- [ ] Three-gate guard silently returns empty when sqlite3 missing, DB missing, or table missing
- [ ] All code is bash 3.2 compatible (no arrays, mapfile, namerefs)
- [ ] 3-5 promoted tests with full Test Doc blocks

---

### Phase 2: Status Bar Rendering

**Objective**: Build the status bar renderer that queries the session database and outputs coloured pip format strings for tmux.

**Deliverables**:
- `scripts/status.sh` — Main renderer: session discovery → DB query → pip rendering → format string output
- 4 additional test fixtures (multiphase, overflow, mixed-status, staleness)
- Caching layer using tmux environment variables

**Dependencies**: Phase 1 complete (helpers, discovery, db_query)

**Risks**:
| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Colour codes don't render in #() output | Low | High | Confirmed working in research; test early in real tmux |
| Overflow threshold edge cases | Medium | Low | Extensive fixture testing at threshold boundary |
| Caching invalidation races | Low | Medium | Cache by session UUID + mtime; stale cache is acceptable |

### Tasks (TAD Approach)

| # | Status | Task | CS | Success Criteria | Log | Notes |
|---|--------|------|----|------------------|-----|-------|
| 2.1 | [ ] | Create 4 additional fixture DBs (multiphase, overflow, mixed-status, staleness) | 2 | All fixtures generated reproducibly by gen-fixtures.sh | - | |
| 2.2 | [ ] | Write scratch probes for status.sh rendering logic | 2 | 10-15 probes: empty session, flat todos, phased todos, overflow, activity text | - | |
| 2.3 | [ ] | Implement scripts/status.sh — main render pipeline | 3 | Correct pip output for all fixture scenarios; completes in <200ms | - | |
| 2.4 | [ ] | Implement caching layer (tmux environment variables) | 2 | Cache hit returns in <10ms; cache invalidated on DB mtime change | - | |
| 2.5 | [ ] | Implement staleness detection (timestamp + process check) | 2 | Stale sessions show dimmed indicator; live sessions show normal pips | - | |
| 2.6 | [ ] | Test colour rendering in real tmux #() expansion | 2 | Colours display correctly in iTerm2 and Terminal.app | - | Live test |
| 2.7 | [ ] | Promote 2-3 tests to tests/unit/ (rendering contract, overflow boundary) | 2 | Tests with full Test Doc blocks | - | |

### Acceptance Criteria
- [ ] Empty session → no output (hidden)
- [ ] Flat todos (no phases) → `■■■□□` with correct colours
- [ ] Phased todos → `■■ ■■■□□` (phase pips + task pips)
- [ ] 15 tasks with threshold 10 → fraction mode `7/15`
- [ ] Activity text appended when @tomux_show_activity=1
- [ ] Staleness detected and displayed (dimmed)
- [ ] Full refresh cycle <200ms (budget 500ms)
- [ ] Caching reduces repeated queries

---

### Phase 3: TPM Integration

**Objective**: Create the TPM entry point that registers options, sets up format string interpolation, and binds keybindings.

**Deliverables**:
- `tomux.tmux` — TPM entry point (executable)
- All `@tomux_*` options registered with defaults
- Format string interpolation: `#{tomux_status}` → `#(status.sh)`
- Keybinding: prefix+T → toggle detail pane

**Dependencies**: Phase 2 complete (status.sh must work end-to-end)

**Risks**:
| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Format string interpolation conflicts with other plugins | Medium | Medium | Use unique `#{tomux_status}` marker; document in README |
| Option defaults not applied on first load | Low | Low | Set all defaults in tomux.tmux before interpolation |

### Tasks (TAD Approach)

| # | Status | Task | CS | Success Criteria | Log | Notes |
|---|--------|------|----|------------------|-----|-------|
| 3.1 | [ ] | Write scratch probes for option registration and interpolation | 2 | Test get_tmux_option reads registered options correctly | - | |
| 3.2 | [ ] | Implement tomux.tmux — option registration (20+ @tomux_* options) | 2 | All options have documented defaults; shellcheck clean | - | |
| 3.3 | [ ] | Implement format string interpolation (#{tomux_status} → #(status.sh)) | 3 | User's status-right shows pips when #{tomux_status} embedded | - | |
| 3.4 | [ ] | Implement multi-line status support (opt-in via @tomux_use_status_line) | 2 | When enabled: saves original status, sets status 2, uses status-format[1] | - | |
| 3.5 | [ ] | Register keybinding (prefix+T → scripts/toggle.sh) | 1 | Hotkey appears in tmux list-keys | - | |
| 3.6 | [ ] | Integration test: install via TPM, verify status bar renders | 3 | End-to-end: TPM install → pips appear in status bar with real Copilot session | - | Live test |

### Acceptance Criteria
- [ ] `tomux.tmux` is executable and shellcheck clean
- [ ] All @tomux_* options registered with documented defaults
- [ ] #{tomux_status} in status-right renders pips
- [ ] @tomux_use_status_line=1 adds second status line without breaking existing bar
- [ ] prefix+T binding registered
- [ ] Plugin loads without errors in clean tmux session

---

### Phase 4: Detail Pane

**Objective**: Build the toggleable detail pane that shows full task breakdown with status icons and auto-refresh.

**Deliverables**:
- `scripts/toggle.sh` — Pane toggle handler (create/kill with stale ID detection)
- `scripts/pane.sh` — Detail pane renderer (ANSI-coloured task table with auto-refresh)

**Dependencies**: Phase 3 complete (keybinding registered, options available)

**Risks**:
| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Layout restoration in complex multi-pane windows | Medium | Medium | tmux auto-restores for simple splits; store window_layout for complex |
| Pane script crash leaves orphan | Low | Medium | remain-on-exit on; restart loop with error display |

### Tasks (TAD Approach)

| # | Status | Task | CS | Success Criteria | Log | Notes |
|---|--------|------|----|------------------|-----|-------|
| 4.1 | [ ] | Write scratch probes for pane toggle logic | 2 | Test create/kill cycle, stale ID detection, position options | - | |
| 4.2 | [ ] | Implement scripts/toggle.sh — pane toggle handler | 3 | Create pane if absent; kill if present; handle stale IDs; return focus | - | |
| 4.3 | [ ] | Implement scripts/pane.sh — detail renderer (ANSI table) | 3 | Renders phases + tasks with ✓/◐/✕/○ status icons; auto-refreshes | - | |
| 4.4 | [ ] | Test pane toggle in real tmux (single pane and multi-pane windows) | 2 | Toggle works in 1-pane, 2-pane, 4-pane layouts; layout preserved | - | Live test |
| 4.5 | [ ] | Promote 1-2 tests (toggle contract, renderer output format) | 1 | Tests with Test Doc blocks | - | |

### Acceptance Criteria
- [ ] prefix+T creates detail pane at bottom (default) or right (configurable)
- [ ] prefix+T again kills detail pane, restores layout
- [ ] Detail pane shows: phase names, task titles, status icons (✓ ◐ ✕ ○)
- [ ] Auto-refresh at @tomux_refresh_interval
- [ ] Focus returns to original pane after toggle
- [ ] Stale pane ID detected and cleaned up

---

### Phase 5: Agent Guidance & Skill

**Objective**: Create the TOMUX_AGENT_GUIDANCE.md template and /tomux-init skill that instructs AI agents to write well-structured todo/phase data.

**Deliverables**:
- `templates/TOMUX_AGENT_GUIDANCE.md` — Layered template (essential contract + worked examples)
- `/tomux-init` skill — Creates guidance file, updates instructions file, sets up tables
- Global default at `~/.config/tomux/agent-guidance.md`
- Project-level `TOMUX_AGENT_GUIDANCE.md` (generated by skill)

**Dependencies**: Phase 3 complete (plugin functional so guidance can be tested end-to-end)

**Risks**:
| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Agent doesn't follow guidance | Medium | Low | Flat display still works; guidance is advisory |
| Version mismatch confusion | Low | Low | Warning in status bar; backward compatible |

### Tasks (Lightweight Approach — documentation, not code)

| # | Status | Task | CS | Success Criteria | Log | Notes |
|---|--------|------|----|------------------|-----|-------|
| 5.1 | [ ] | Write templates/TOMUX_AGENT_GUIDANCE.md from workshop decisions | 3 | Version header, essential contract, 3 worked examples, SQL cheat sheet | - | Per workshop §11 |
| 5.2 | [ ] | Create /tomux-init skill (~/.claude/commands/tomux.md) | 2 | Asks user for instructions file, creates guidance, updates pointer | - | |
| 5.3 | [ ] | Create global default location (~/.config/tomux/agent-guidance.md) | 1 | Install script copies template; project-level overrides global | - | |
| 5.4 | [ ] | Test guidance end-to-end: agent reads guidance → creates structured todos → Tomux displays | 3 | Full round-trip: guidance → agent writes DB → pips appear | - | Live test |
| 5.5 | [ ] | Add semantic version detection to status.sh | 2 | Version mismatch → ⚠ warning in status bar | - | |

### Acceptance Criteria
- [ ] TOMUX_AGENT_GUIDANCE.md includes: table schemas, ID naming rules, status values, cleanup rules, 3 worked examples
- [ ] /tomux-init skill creates guidance file and updates instructions file
- [ ] Agent following guidance produces structured data that Tomux renders with phase grouping
- [ ] Version mismatch shows ⚠ warning
- [ ] Without guidance file, Tomux shows flat pips with hint

---

### Phase 6: Polish & Documentation

**Objective**: Comprehensive README, cross-platform testing, edge case handling, and release preparation.

**Deliverables**:
- `README.md` — Installation, configuration reference, screenshots, architecture, contributing, agent guidance tutorial
- `Makefile` — test, lint, install targets
- `.gitignore` — Exclude scratch tests, DB caches
- Cross-platform verification: macOS, Linux, WSL
- Performance profiling and tuning

**Dependencies**: All prior phases complete

**Risks**:
| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Cross-platform differences in edge cases | Medium | Medium | Test matrix: macOS + Linux + WSL × 2 terminal emulators |
| README scope creep | Low | Low | Follow spec: comprehensive but structured |

### Tasks (Lightweight Approach)

| # | Status | Task | CS | Success Criteria | Log | Notes |
|---|--------|------|----|------------------|-----|-------|
| 6.1 | [ ] | Write README.md (installation, quick-start, config reference) | 3 | All @tomux_* options documented with defaults and examples | - | |
| 6.2 | [ ] | Add architecture section + contributing guide to README | 2 | Component diagram, data flow, how to contribute | - | |
| 6.3 | [ ] | Add agent guidance tutorial section to README | 2 | Step-by-step: install → /tomux-init → see pips | - | |
| 6.4 | [ ] | Create Makefile (test, lint, install, fixtures) | 2 | `make test`, `make lint`, `make fixtures` all work | - | |
| 6.5 | [ ] | Cross-platform test: macOS (iTerm2, Terminal.app) | 2 | All features work, colours render, pane toggle works | - | Live test |
| 6.6 | [ ] | Cross-platform test: Linux (Alacritty or kitty) | 2 | All features work, process tree walk uses correct ps flags | - | Live test |
| 6.7 | [ ] | Performance profiling with 5/50/500 tasks | 2 | <200ms for 5 tasks, <500ms for 500 tasks; caching helps | - | |
| 6.8 | [ ] | Edge case sweep: tmux 3.2, Unicode fallback, empty DB, locked DB | 2 | All edge cases handled gracefully | - | |

### Acceptance Criteria
- [ ] README covers: installation, config, screenshots, architecture, contributing, agent guidance
- [ ] `make test` runs all promoted tests; `make lint` runs shellcheck
- [ ] Works on macOS + Linux (WSL counts as Linux)
- [ ] Performance <500ms for all scenarios
- [ ] All edge cases handled with graceful degradation

---

## Cross-Cutting Concerns

### Security
- **No secrets**: Plugin reads public session data; no credentials involved
- **Read-only**: P-1 enforced — never writes to any Copilot database
- **No network**: Pure local filesystem access; no HTTP calls

### Observability
- **Logging**: None in status bar mode (stdout is the output). Detail pane shows errors inline
- **Staleness indicator**: Dimmed pips or ◌ (dotted circle) when copilot process exits
- **Version warning**: `⚠ TOMUX: guidance v1 → update to v2` for version mismatches

### Documentation
- **Location**: README.md (comprehensive) + docs/project-rules/ (constitution, rules, idioms, architecture)
- **Agent guidance**: TOMUX_AGENT_GUIDANCE.md template in templates/; /tomux-init skill
- **Target audience**: tmux users who use Copilot CLI for AI-assisted development

---

## Complexity Tracking

| Component | CS | Label | Breakdown (S,I,D,N,F,T) | Justification | Mitigation |
|-----------|-----|-------|------------------------|---------------|------------|
| Session Discovery | 3 | Medium | S=1,I=1,D=1,N=1,F=1,T=1 | Cross-platform process tree walking + CWD matching | Platform detection, extensive fixture testing |
| Status Bar Renderer | 3 | Medium | S=1,I=1,D=0,N=1,F=1,T=1 | Dual display mode (pips/fractions), colour management, caching | Threshold-based mode switching, tmux env caching |
| TPM Integration | 3 | Medium | S=1,I=2,D=0,N=1,F=1,T=1 | Multi-line status interaction, format string interpolation | Default to inline; multi-line opt-in; save/restore |
| Agent Guidance | 2 | Small | S=1,I=0,D=1,N=1,F=0,T=0 | Novel data contract, version management | Layered template, backward compatible versioning |

---

## Progress Tracking

### Phase Completion Checklist
- [ ] Phase 1: Core Infrastructure — NOT STARTED
- [ ] Phase 2: Status Bar Rendering — NOT STARTED
- [ ] Phase 3: TPM Integration — NOT STARTED
- [ ] Phase 4: Detail Pane — NOT STARTED
- [ ] Phase 5: Agent Guidance & Skill — NOT STARTED
- [ ] Phase 6: Polish & Documentation — NOT STARTED

### STOP Rule

**IMPORTANT**: This plan must be validated before creating phase dossiers.
1. Run `/plan-4-complete-the-plan` to validate readiness
2. Only proceed to `/plan-5-phase-tasks-and-brief` after validation passes

### Deviation Ledger

| Principle Violated | Why Needed | Simpler Alternative Rejected | Risk Mitigation |
|-------------------|------------|------------------------------|-----------------|
| (none) | — | — | — |

### ADR Ledger

| ADR | Status | Affects Phases | Notes |
|-----|--------|----------------|-------|
| ADR-001 (seed) | Not yet created | Phase 1 | Session Discovery Strategy |
| ADR-002 (seed) | Not yet created | Phase 3 | Status Bar Integration Pattern |
| ADR-003 (seed) | Not yet created | Phase 2 | Pip Rendering Architecture |

---

## Change Footnotes Ledger

[^1]: [To be added during implementation via plan-6a]
[^2]: [To be added during implementation via plan-6a]
[^3]: [To be added during implementation via plan-6a]
