#!/usr/bin/env bash
# Tests install.sh in a temporary CLAUDE_HOME and project directory.
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export CLAUDE_HOME="$TMP/home"
fail=0

assert() {
  local msg="$1"; shift
  if "$@"; then echo "  pass  $msg"; else echo "  FAIL  $msg"; fail=1; fi
}

n_agents=$(find "$REPO/agents" -maxdepth 1 -name '*.md' | wc -l | tr -d ' ')
n_skills=$(find "$REPO/skills" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')

echo "user install"
"$REPO/install.sh" >/dev/null
assert "links every agent" test "$(find "$CLAUDE_HOME/agents" -type l | wc -l | tr -d ' ')" = "$n_agents"
assert "links every skill" test "$(find "$CLAUDE_HOME/skills" -type l | wc -l | tr -d ' ')" = "$n_skills"
assert "agent link resolves to repo file" test "$(readlink "$CLAUDE_HOME/agents/pr-reviewer.md")" = "$REPO/agents/pr-reviewer.md"
assert "skill is readable through link" test -f "$CLAUDE_HOME/skills/bug-ticket/SKILL.md"

echo "re-run is idempotent"
out="$("$REPO/install.sh")"
assert "reports existing links as ok" grep -q "ok .*pr-reviewer.md" <<<"$out"
assert "no new links" test "$(find "$CLAUDE_HOME/agents" -type l | wc -l | tr -d ' ')" = "$n_agents"

echo "does not overwrite foreign files"
rm "$CLAUDE_HOME/agents/test-developer.md"
echo "mine" >"$CLAUDE_HOME/agents/test-developer.md"
out="$("$REPO/install.sh")"
assert "skips foreign file" grep -q "SKIP .*test-developer.md" <<<"$out"
assert "foreign file kept" test "$(cat "$CLAUDE_HOME/agents/test-developer.md")" = "mine"

echo "uninstall"
ln -s /tmp/elsewhere "$CLAUDE_HOME/agents/other.md"
"$REPO/install.sh" --uninstall >/dev/null
assert "removes repo links" test ! -e "$CLAUDE_HOME/agents/pr-reviewer.md"
assert "keeps foreign file" test -f "$CLAUDE_HOME/agents/test-developer.md"
assert "keeps foreign link" test -L "$CLAUDE_HOME/agents/other.md"

echo "project install"
proj="$TMP/proj"
mkdir -p "$proj"
echo "# existing" >"$proj/CLAUDE.md"
"$REPO/install.sh" --project "$proj" >/dev/null
assert "copies agents" test -f "$proj/.claude/agents/pr-reviewer.md"
assert "copies, does not link" test ! -L "$proj/.claude/agents/pr-reviewer.md"
assert "copies skills" test -f "$proj/.claude/skills/test-cases/SKILL.md"
assert "creates settings.json" test -f "$proj/.claude/settings.json"
assert "keeps existing CLAUDE.md" test "$(cat "$proj/CLAUDE.md")" = "# existing"

echo "bad arguments"
assert "rejects missing project dir" bash -c "! '$REPO/install.sh' --project '$TMP/nope' 2>/dev/null"
assert "rejects unknown option" bash -c "! '$REPO/install.sh' --bogus 2>/dev/null"

[[ $fail -eq 0 ]] && echo "test_install: all passed"
exit $fail
