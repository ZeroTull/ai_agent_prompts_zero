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

# Runs install.sh, stores stdout+stderr in $out and the exit code in $rc.
run() {
  out="$("$REPO/install.sh" "$@" 2>&1)"
  rc=$?
}

# True if the last install output does not contain $1. Called through assert.
# shellcheck disable=SC2329
out_lacks() { ! grep -q -- "$1" <<<"$out"; }

count_links() { find "$1" -type l | wc -l | tr -d ' '; }

n_agents=$(find "$REPO/agents" -maxdepth 1 -name '*.md' | wc -l | tr -d ' ')
n_skills=$(find "$REPO/skills" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')
an_agent="$(basename "$(find "$REPO/agents" -maxdepth 1 -name '*.md' | sort | head -n 1)")"
a_skill="$(basename "$(find "$REPO/skills" -mindepth 1 -maxdepth 1 -type d | sort | head -n 1)")"

echo "user install"
run
assert "exits 0" test "$rc" = 0
assert "links every agent" test "$(count_links "$CLAUDE_HOME/agents")" = "$n_agents"
assert "links every skill" test "$(count_links "$CLAUDE_HOME/skills")" = "$n_skills"
assert "agent link resolves to repo file" test "$(readlink "$CLAUDE_HOME/agents/$an_agent")" = "$REPO/agents/$an_agent"
assert "skill is readable through link" test -f "$CLAUDE_HOME/skills/$a_skill/SKILL.md"

echo "dependency check"
assert "prints dependency check" grep -q "^Dependency check:" <<<"$out"
assert "reports git as found" grep -Eq "^  found +git$" <<<"$out"

# Stub tools: az records any call, python3 fails or succeeds on demand.
stubs="$TMP/stubs"
mkdir -p "$stubs" "$TMP/azext"
printf '#!/bin/sh\ntouch "%s/az-called"\n' "$TMP" >"$stubs/az"
# PY_EXIT is expanded by the stub at run time.
# shellcheck disable=SC2016
printf '#!/bin/sh\nexit "${PY_EXIT:-1}"\n' >"$stubs/python3"
chmod +x "$stubs/az" "$stubs/python3"
out="$(PATH="$stubs:/usr/bin:/bin" AZURE_EXTENSION_DIR="$TMP/azext" "$REPO/install.sh" 2>&1)"; rc=$?
assert "exits 0 with missing tools" test "$rc" = 0
assert "reports missing azure-devops extension" grep -q "missing .*az azure-devops extension" <<<"$out"
assert "does not run az" test ! -e "$TMP/az-called"
assert "reports missing openpyxl" grep -q "missing .*openpyxl" <<<"$out"
if ! PATH="/usr/bin:/bin" command -v claude >/dev/null 2>&1; then
  assert "reports a missing tool with its purpose" grep -q "missing .*claude (Claude Code itself)" <<<"$out"
fi
mkdir "$TMP/azext/azure-devops"
out="$(PATH="$stubs:/usr/bin:/bin" PY_EXIT=0 AZURE_EXTENSION_DIR="$TMP/azext" "$REPO/install.sh" 2>&1)"; rc=$?
assert "exits 0 with all tools" test "$rc" = 0
assert "no extension warning when installed" out_lacks "azure-devops extension"
assert "no openpyxl warning when importable" out_lacks "openpyxl"

echo "re-run is idempotent"
run
assert "exits 0" test "$rc" = 0
assert "reports existing links as ok" grep -q "ok .*$an_agent" <<<"$out"
assert "no new links" test "$(count_links "$CLAUDE_HOME/agents")" = "$n_agents"

echo "does not overwrite foreign files"
rm "$CLAUDE_HOME/agents/$an_agent"
echo "mine" >"$CLAUDE_HOME/agents/$an_agent"
run
assert "exits 0" test "$rc" = 0
assert "skips foreign file" grep -q "SKIP .*$an_agent" <<<"$out"
assert "foreign file kept" test "$(cat "$CLAUDE_HOME/agents/$an_agent")" = "mine"

echo "replaces links left by a moved repo"
rm "$CLAUDE_HOME/skills/$a_skill"
ln -s "/old/place/skills/$a_skill" "$CLAUDE_HOME/skills/$a_skill"
run
assert "reports relink" grep -q "relinked .*$a_skill" <<<"$out"
assert "link points to this repo" test "$(readlink "$CLAUDE_HOME/skills/$a_skill")" = "$REPO/skills/$a_skill"

echo "uninstall"
ln -s /tmp/elsewhere "$CLAUDE_HOME/agents/other.md"
ln -s "/old/place/skills/not-ours" "$CLAUDE_HOME/skills/not-ours"
ln -s "/old/place/agents/$an_agent" "$CLAUDE_HOME/agents/stale-$an_agent"
rm "$CLAUDE_HOME/skills/$a_skill"
ln -s "/old/place/skills/$a_skill" "$CLAUDE_HOME/skills/$a_skill"
run --uninstall
assert "exits 0" test "$rc" = 0
assert "removes repo links" test "$(count_links "$CLAUDE_HOME/skills")" = 1
assert "removes stale link with our name" test ! -L "$CLAUDE_HOME/skills/$a_skill"
assert "keeps foreign file" test -f "$CLAUDE_HOME/agents/$an_agent"
assert "keeps foreign link" test -L "$CLAUDE_HOME/agents/other.md"
assert "keeps stale link with a foreign name" test -L "$CLAUDE_HOME/skills/not-ours"
assert "keeps stale link whose name does not match its target" test -L "$CLAUDE_HOME/agents/stale-$an_agent"

echo "project install"
proj="$TMP/proj"
mkdir -p "$proj"
echo "# existing" >"$proj/CLAUDE.md"
run --project "$proj"
assert "exits 0" test "$rc" = 0
assert "copies agents" test -f "$proj/.claude/agents/$an_agent"
assert "copies, does not link" test ! -L "$proj/.claude/agents/$an_agent"
assert "copies skills" test -f "$proj/.claude/skills/$a_skill/SKILL.md"
assert "creates settings.json" cmp -s "$proj/.claude/settings.json" "$REPO/settings.example.json"
assert "keeps existing CLAUDE.md" test "$(cat "$proj/CLAUDE.md")" = "# existing"
assert "reports CLAUDE.md skip" grep -q "SKIP .*CLAUDE.md" <<<"$out"

echo "project re-run"
echo "custom" >"$proj/.claude/settings.json"
run --project "$proj"
assert "exits 0" test "$rc" = 0
assert "reports unchanged copies as ok" grep -q "ok .*agents/$an_agent" <<<"$out"
assert "keeps existing settings.json" test "$(cat "$proj/.claude/settings.json")" = "custom"
assert "reports settings.json skip" grep -q "SKIP .*settings.json" <<<"$out"

echo "project update"
echo "local edit" >>"$proj/.claude/agents/$an_agent"
echo "local edit" >>"$proj/.claude/skills/$a_skill/SKILL.md"
run --project "$proj"
assert "reports changed agent" grep -q "DIFFERS .*agents/$an_agent" <<<"$out"
assert "reports changed skill" grep -q "DIFFERS .*skills/$a_skill" <<<"$out"
assert "does not overwrite without --update" grep -q "local edit" "$proj/.claude/agents/$an_agent"
run --project "$proj" --update
assert "exits 0" test "$rc" = 0
assert "reports update" grep -q "updated .*agents/$an_agent" <<<"$out"
assert "agent matches repo" cmp -s "$proj/.claude/agents/$an_agent" "$REPO/agents/$an_agent"
assert "skill matches repo" diff -rq "$proj/.claude/skills/$a_skill" "$REPO/skills/$a_skill"
assert "--update keeps settings.json" test "$(cat "$proj/.claude/settings.json")" = "custom"
assert "--update keeps CLAUDE.md" test "$(cat "$proj/CLAUDE.md")" = "# existing"

echo "project update replaces added files"
echo "extra" >"$proj/.claude/skills/$a_skill/notes.md"
run --project "$proj" --update
assert "reports replacement" grep -q "updated .*skills/$a_skill (local edits and added files replaced)" <<<"$out"
assert "added file removed" test ! -e "$proj/.claude/skills/$a_skill/notes.md"

echo "project copy that is a symlink"
rm -rf "$proj/.claude/skills/$a_skill"
ln -s "$TMP" "$proj/.claude/skills/$a_skill"
run --project "$proj" --update
assert "skips symlinked entry" grep -q "SKIP .*skills/$a_skill (is a symlink" <<<"$out"
assert "symlink untouched" test "$(readlink "$proj/.claude/skills/$a_skill")" = "$TMP"

echo "project entry of a different type"
rm "$proj/.claude/skills/$a_skill"
echo "not a dir" >"$proj/.claude/skills/$a_skill"
run --project "$proj" --update
assert "skips entry of a different type" grep -q "SKIP .*skills/$a_skill (exists as a different type" <<<"$out"
assert "file untouched" test "$(cat "$proj/.claude/skills/$a_skill")" = "not a dir"

echo "arguments"
run --help
assert "--help exits 0" test "$rc" = 0
assert "--help prints usage" grep -q -- "--project" <<<"$out"
run --project "$TMP/nope"
assert "missing project dir exits 1" test "$rc" = 1
run --project
assert "--project without dir exits 1" test "$rc" = 1
run --project "$proj" extra
assert "extra project argument exits 1" test "$rc" = 1
run --uninstall extra
assert "extra uninstall argument exits 1" test "$rc" = 1
run --bogus
assert "unknown option exits 1" test "$rc" = 1

[[ $fail -eq 0 ]] && echo "test_install: all passed"
exit $fail
