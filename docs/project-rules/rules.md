# Tomux — Rules

**Version**: 1.0.0
**Last updated**: 2026-03-18
**Derives from**: [constitution.md](./constitution.md)

---

## 1. Source Control

- MUST use conventional commits: `feat:`, `fix:`, `docs:`, `chore:`,
  `test:`, `refactor:`
- MUST include `Co-authored-by: Copilot <...>` trailer when AI-assisted
- SHOULD keep commits atomic — one logical change per commit
- MUST NOT commit the Copilot session database or any user data

## 2. Coding Standards

### Bash

- MUST pass `shellcheck` with zero warnings (SC-level errors are
  blockers)
- MUST use `#!/usr/bin/env bash` shebang
- MUST quote all variable expansions: `"${var}"` not `$var`
- MUST use `local` for function-scoped variables
- SHOULD use `readonly` for constants
- MUST use `[[ ]]` over `[ ]` for conditionals
- MUST use lowercase with underscores for variable names:
  `pip_char_filled`, not `PipCharFilled`
- MUST use UPPERCASE for exported/tmux option variables:
  `TOMUX_REFRESH_INTERVAL`
- SHOULD keep functions under 50 lines; extract helpers when longer
- MUST handle the case where `sqlite3` is not installed (P-4)
- MUST handle the case where the DB file doesn't exist (P-4)
- MUST handle the case where tables don't exist in the DB (P-4)

### tmux Integration

- MUST NOT call `set-option -g status-left` or `status-right` directly
  (P-6). Instead, define interpolation variables that users embed.
- MUST use `@tomux_` prefix for all tmux user options
- MUST provide defaults for every `@tomux_` option via
  `tmux show-option -gqv` with fallback
- SHOULD use `tmux display-message` for transient user feedback only
- MUST support tmux 3.2+ (may use `display-popup` features)

### SQLite Queries

- MUST open databases as read-only: `sqlite3 -readonly`
  (or equivalent flag)
- MUST set a query timeout to avoid blocking on locked DBs
- MUST check table existence before querying
  (`SELECT name FROM sqlite_master WHERE type='table'`)
- SHOULD cache query results for the configured refresh interval
- MUST NOT write to any Copilot database (P-1)

## 3. Testing

### Philosophy (TAD)

Tests are **executable documentation**. Every test must justify its
existence through comprehension value, not coverage metrics. Tests
that don't "pay rent" get deleted.

### Test Quality Standards

Every test MUST include a doc comment with:
- **Why**: Business/bug/regression reason for this test
- **Contract**: Plain-English invariant being asserted
- **Usage Notes**: How to call the function, gotchas
- **Quality Contribution**: What failures this catches
- **Worked Example**: Representative input → output

```bash
@test "renders 3/5 done tasks as 3 green + 2 empty pips" {
  # Test Doc:
  # - Why: Core rendering contract — pip count must match task count
  # - Contract: render_pips(done, total, color) returns exactly
  #   `total` characters, first `done` in color, rest empty
  # - Usage Notes: Requires TERM supporting 256 colours
  # - Quality Contribution: Catches off-by-one in pip rendering
  # - Worked Example: render_pips 3 5 "green" → "■■■□□"
  
  run render_pips 3 5 "green"
  [[ "$output" == *"■■■□□"* ]]
}
```

### Scratch → Promote Workflow

- Probe tests MAY live in `tests/scratch/` for fast exploration
- `tests/scratch/` MUST be excluded from CI (`.gitignore`)
- Promote to `tests/unit/` or `tests/integration/` only if the test
  adds durable value (critical path, opaque behaviour, regression-prone,
  or edge case)
- Promoted tests MUST include full Test Doc comment blocks
- Non-valuable scratch tests MUST be deleted

### TDD Guidance

- TDD (test-first) SHOULD be used for: pip rendering logic, overflow
  calculations, colour formatting, query builders
- TDD MAY be skipped for: simple config reads, tmux option wiring
- When using TDD, follow RED → GREEN → REFACTOR cycles

### Test Reliability

- Tests MUST NOT depend on a running tmux server (mock tmux commands)
- Tests MUST NOT read real Copilot session databases (use fixtures)
- Tests MUST be deterministic — no flaky tests in CI
- Tests SHOULD complete in under 5 seconds total

### Test Organization

```
tests/
├── scratch/        # Fast probes, excluded from CI
├── unit/           # Isolated function tests with Test Doc
├── integration/    # Full plugin lifecycle tests
└── fixtures/       # Sample .db files, mock tmux output
```

### Mock Policy

TODO(mock-policy): Define mock policy during plan-2-clarify.
Default: **Targeted** — mock tmux commands and file system; use
real sqlite3 against fixture databases.

## 4. Tooling & Automation

- `shellcheck` MUST run on all `.sh` and `.tmux` files
- bats-core for all automated tests
- TODO(ci-pipeline): Define CI pipeline (GitHub Actions)
- Local development: `make test` and `make lint` targets

## 5. Naming Conventions

| Entity | Convention | Example |
|--------|-----------|---------|
| Plugin entry point | `*.tmux` | `tomux.tmux` |
| Helper scripts | `snake_case.sh` | `render_pips.sh` |
| tmux user options | `@tomux_*` | `@tomux_refresh_interval` |
| tmux format vars | `#{tomux_*}` | `#{tomux_status}` |
| Bash functions | `snake_case` | `get_session_id` |
| Bash constants | `UPPER_SNAKE` | `TOMUX_DEFAULT_REFRESH` |
| Test files | `*.bats` | `render_pips.bats` |

<!-- USER CONTENT START -->
<!-- Add project-specific rules here. -->
<!-- USER CONTENT END -->
