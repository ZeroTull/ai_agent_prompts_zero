#!/usr/bin/env bash
# Tests settings.json, the hook wrapper and the status line script.
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail=0

assert() {
  local msg="$1"; shift
  if "$@" >/dev/null 2>&1; then echo "  pass  $msg"; else echo "  FAIL  $msg"; fail=1; fi
}

echo "settings.json"
assert "is valid JSON" jq -e . "$REPO/settings.json"
assert "enables push-to-talk voice mode" jq -e '.voice.enabled == true and .voice.mode == "hold"' "$REPO/settings.json"
assert "uses the status line script" jq -e '.statusLine.command | contains("statusline-command.sh")' "$REPO/settings.json"
# Literal $HOME is the expected value.
# shellcheck disable=SC2016
assert "every hook command points at the wrapper" \
  jq -e '[.hooks[][].hooks[].command] | all(. == "bash \"$HOME/.claude/hooks/tmux-claude.sh\"")' "$REPO/settings.json"
# Auto mode reads autoMode only from ~/.claude/settings.json, so it lives here, without machine-specific paths.
assert "has an autoMode environment" jq -e '.autoMode.environment | length > 0' "$REPO/settings.json"
assert "autoMode names no machine paths" jq -e '[.autoMode.environment[] | select(test("/Users/|/home/"))] | length == 0' "$REPO/settings.json"

echo "hook wrapper"
assert "exits 0 without the plugin" bash -c "echo '{}' | TMUX_CLAUDE_HOOK=/nonexistent bash '$REPO/hooks/tmux-claude.sh'"
fake="$TMP/fake-hook.sh"
printf '#!/bin/bash\ncat > "%s"\n' "$TMP/hook-input" >"$fake"
chmod +x "$fake"
echo '{"hook_event_name":"Stop"}' | TMUX_CLAUDE_HOOK="$fake" bash "$REPO/hooks/tmux-claude.sh"
assert "forwards the payload to the plugin" grep -q Stop "$TMP/hook-input"

echo "status line"
out=$(echo '{"model":{"display_name":"Opus"},"context_window":{"used_percentage":42,"context_window_size":200000},"cost":{"total_cost_usd":0.5,"total_duration_ms":65000,"total_lines_added":3,"total_lines_removed":1}}' |
  bash "$REPO/statusline-command.sh")
assert "shows the model" grep -q Opus <<<"$out"
assert "shows context percent" grep -q "42%" <<<"$out"
assert "shows line changes" grep -q "+3/-1" <<<"$out"
out_uk=$(echo '{"cost":{"total_cost_usd":0.5}}' | LC_ALL=uk_UA.UTF-8 bash "$REPO/statusline-command.sh" 2>&1)
# Literal dollar sign.
# shellcheck disable=SC2016
assert "formats cost regardless of locale" grep -q '\$0.500' <<<"$out_uk"
assert "prints no errors" bash -c "! grep -q invalid <<<'$out_uk'"

[[ $fail -eq 0 ]] && echo "test_config: all passed"
exit $fail
