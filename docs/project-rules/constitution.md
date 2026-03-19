<!-- Sync Impact Report
  Mode: CREATE (fresh project)
  Version: 1.0.0
  Created: 2026-03-18
  Sections: 6 (all new)
  Outstanding TODOs: 2 (mock policy, CI pipeline)
  Template dependencies: none yet
-->

# Tomux — Project Constitution

**Version**: 1.0.0
**Ratified**: 2026-03-18
**Last amended**: 2026-03-18

---

## 1. Purpose

Tomux is a **native tmux plugin** (bash + sqlite3) that visualises
Copilot CLI agent progress directly inside the tmux UI — status bar
pips and an optional detail pane. It reads the Copilot session SQLite
database in real-time and renders phase/task progress as coloured
pip indicators.

The plugin is designed to be **zero-config** for basic use: install via
TPM, and if a Copilot session is active for the current working
directory, progress pips appear automatically.

---

## 2. Guiding Principles

| ID | Principle | Rationale |
|----|-----------|-----------|
| P-1 | **Read-only observer** | Tomux MUST NOT write to the Copilot session database. It is a pure visualisation layer. |
| P-2 | **Minimal dependencies** | Only `sqlite3` CLI and standard POSIX tools (`ps`, `awk`, `sed`). No Python, Node, jq, or compiled binaries required. |
| P-3 | **Bash-native** | All plugin logic in POSIX-compatible bash. No polyglot complexity. |
| P-4 | **Graceful degradation** | If the session DB is missing, copilot isn't running, or sqlite3 is unavailable, the plugin shows nothing (or a configurable idle indicator) — never errors. |
| P-5 | **Configurable everything** | Colours, characters, thresholds, refresh rate, display location, and label visibility MUST be configurable via tmux `@options`. Sensible defaults for all. |
| P-6 | **Respect the user's tmux** | Never overwrite existing status bar content. Provide format-string variables (e.g., `#{tomux_status}`) that users embed where they choose. |
| P-7 | **Cross-platform** | macOS, Linux, and WSL. Handle platform differences (e.g., `lsof` vs `/proc`) in session discovery. |
| P-8 | **Performance-conscious** | Queries run on a configurable interval (default 5s). Cache results. Never block tmux rendering. |

<!-- USER CONTENT START -->
<!-- Add project-specific principles here. They will survive constitution updates. -->
<!-- USER CONTENT END -->

---

## 3. Quality & Verification Strategy

### Testing Philosophy

Tomux follows **Test-Assisted Development (TAD)**: tests are executable
documentation that prove contracts and catch regressions. Tests must
"pay rent" through comprehension value — no test exists purely for
coverage numbers.

### Testing Approach

| Layer | Tool | What it proves |
|-------|------|---------------|
| Unit (bash functions) | [bats-core](https://github.com/bats-core/bats-core) | Individual function contracts: query building, pip rendering, colour formatting, overflow logic |
| Integration | bats + tmux server | Full plugin lifecycle: TPM install → status bar render → DB polling → display update |
| Manual smoke | Checklist in CONTRIBUTING.md | Visual correctness on macOS, Linux, WSL with various tmux versions |

### Quality Gates

- All bats tests pass before merge
- `shellcheck` clean on all `.sh` and `.tmux` files
- Manual verification on at least one platform per PR
- No regressions in existing tmux status bar content (P-6)

<!-- USER CONTENT START -->
<!-- Add project-specific quality gates here. -->
<!-- USER CONTENT END -->

---

## 4. Delivery Practices

### Planning

- Features are planned using the `/plan-*` command suite
- Each feature gets a spec → clarification → architecture → phased
  implementation cycle
- Complexity scored using CS 1–5 (no time estimates ever)

### Documentation Expectations

- README.md: installation, quick-start, configuration reference
- TOMUX_AGENT_GUIDANCE.md: instructions for AI agents to create the
  DB structure Tomux expects
- Code comments only where behaviour is non-obvious
- ADRs for significant design decisions

### Definition of Done

1. Feature works on macOS + Linux (WSL counts as Linux)
2. bats tests cover the new behaviour
3. shellcheck passes
4. README updated if user-facing
5. Configuration options documented with defaults

<!-- USER CONTENT START -->
<!-- Add project-specific delivery practices here. -->
<!-- USER CONTENT END -->

---

## 5. Governance

### Amendment Procedure

1. Propose change via PR modifying this file
2. Mark custom content with `<!-- USER CONTENT START/END -->` markers
3. Run `/plan-0-constitution` to validate consistency across all
   doctrine files
4. Single approver required for PATCH changes; all contributors
   for MINOR/MAJOR

### Review Cadence

- Constitution reviewed when a new major feature is planned
- Rules and idioms updated alongside each feature implementation

### Compliance Tracking

- PR reviews reference principle IDs (P-1 through P-8) when relevant
- Architecture guardrails enforced via code review checklist

<!-- USER CONTENT START -->
<!-- Add project-specific governance rules here. -->
<!-- USER CONTENT END -->

---

## 6. Complexity Scoring (CS 1–5)

All effort estimation uses Complexity Score. **No time estimates.**

| Factor | 0 | 1 | 2 |
|--------|---|---|---|
| Surface Area (S) | One file | Multiple files | Cross-cutting |
| Integration (I) | Internal only | One external | Multiple externals |
| Data & State (D) | None | Minor tweaks | Migration/concurrency |
| Novelty (N) | Well-specified | Some ambiguity | Significant discovery |
| Non-Functional (F) | Standard | Moderate constraints | Critical constraints |
| Testing (T) | Unit only | Integration/e2e | Staged rollout |

**Mapping**: P(0–12) → CS-1(0–2), CS-2(3–4), CS-3(5–7), CS-4(8–9), CS-5(10–12)

For CS ≥ 4: MUST include staged rollout plan and rollback strategy.
