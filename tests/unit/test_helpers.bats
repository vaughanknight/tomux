#!/usr/bin/env bats
# test_helpers.bats — Unit tests for scripts/helpers.sh
# TAD: Promoted from scratch probes — core rendering contracts

TOMUX_HOME="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"

setup() {
  source "$TOMUX_HOME/tests/fixtures/mocks.sh"
  source "$TOMUX_HOME/scripts/helpers.sh"
}

# --- render_pips ---

@test "render_pips: 3 done, 1 progress, 0 blocked out of 5 → correct pip count" {
  # Why: Core rendering contract — pip count must equal total
  # Contract: render_pips produces exactly total pips (done + progress + blocked + pending)
  result=$(render_pips 3 1 0 5 "colour28" "colour214" "colour196")
  # Count actual pip characters (■ and □)
  pip_count=$(echo "$result" | grep -o '[■□]' | wc -l | tr -d ' ')
  [ "$pip_count" -eq 5 ]
}

@test "render_pips: done pips use done colour" {
  result=$(render_pips 2 0 0 3 "colour28" "colour214" "colour196")
  [[ "$result" == *"#[fg=colour28]■"* ]]
}

@test "render_pips: in-progress pips use progress colour" {
  result=$(render_pips 0 2 0 3 "colour28" "colour214" "colour196")
  [[ "$result" == *"#[fg=colour214]■"* ]]
}

@test "render_pips: blocked pips use blocked colour" {
  result=$(render_pips 0 0 1 3 "colour28" "colour214" "colour196")
  [[ "$result" == *"#[fg=colour196]■"* ]]
}

@test "render_pips: pending pips use empty character" {
  result=$(render_pips 0 0 0 3 "colour28" "colour214" "colour196")
  [[ "$result" == *"□"* ]]
}

@test "render_pips: 0 total → empty string" {
  result=$(render_pips 0 0 0 0 "colour28" "colour214" "colour196")
  [ -z "$result" ] || [ "$result" = "#[fg=default]" ]
}

# --- render_with_overflow ---

@test "render_with_overflow: under threshold → pips" {
  # Contract: when total <= threshold, render individual pips
  result=$(render_with_overflow 3 1 0 5 10 "colour28" "colour214" "colour196")
  [[ "$result" == *"■"* ]]
  [[ "$result" == *"□"* ]]
}

@test "render_with_overflow: over threshold → fraction" {
  # Contract: when total > threshold, render done/total fraction
  result=$(render_with_overflow 7 1 0 15 10 "colour28" "colour214" "colour196")
  [[ "$result" == *"7"* ]]
  [[ "$result" == *"/15"* ]]
}

@test "render_with_overflow: exactly at threshold → pips (not fraction)" {
  # Contract: threshold is inclusive — at threshold use pips
  result=$(render_with_overflow 5 0 0 10 10 "colour28" "colour214" "colour196")
  pip_count=$(echo "$result" | grep -o '[■□]' | wc -l | tr -d ' ')
  [ "$pip_count" -eq 10 ]
}

# --- format_activity ---

@test "format_activity: truncates long text with ellipsis" {
  result=$(format_activity "Implementing Phase 3: Rendering Surfaces and More" 30)
  [ "${#result}" -le 31 ]  # 30 + potential ellipsis char
  [[ "$result" == *"…" ]] || [[ "$result" == *"..." ]]
}

@test "format_activity: short text unchanged" {
  result=$(format_activity "Hello" 30)
  [ "$result" = "Hello" ]
}

@test "format_activity: empty text → empty" {
  result=$(format_activity "" 30)
  [ -z "$result" ]
}

# --- detect_platform ---

@test "detect_platform: returns macos, linux, or unknown" {
  result=$(detect_platform)
  [[ "$result" == "macos" ]] || [[ "$result" == "linux" ]] || [[ "$result" == "unknown" ]]
}

# --- get_tmux_option ---

@test "get_tmux_option: returns default when option not set" {
  result=$(get_tmux_option "@tomux_nonexistent" "fallback")
  [ "$result" = "fallback" ]
}

@test "get_tmux_option: returns set value when option exists" {
  mock_set_option "@tomux_test" "custom_value"
  result=$(get_tmux_option "@tomux_test" "fallback")
  [ "$result" = "custom_value" ]
}
