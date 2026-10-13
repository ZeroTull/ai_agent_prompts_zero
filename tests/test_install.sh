#!/usr/bin/env bash
# Tests install.sh in a temporary CLAUDE_HOME and project directory. Never touches the real ~/.claude.
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
# shellcheck disable=SC2317,SC2329
out_lacks() { ! grep -q -- "$1" <<<"$out"; }

count_links() { find "$1" -type l | wc -l | tr -d ' '; }
backup_dir() { find "$CLAUDE_HOME/backups" -mindepth 1 -maxdepth 1 -type d | sort | tail -n 1; }

n_agents=$(find "$REPO/agents" -maxdepth 1 -name '*.md' | wc -l | tr -d ' ')
n_skills=$(find "$REPO/skills" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')
n_qa=$(awk -F'\t' 'NR > 1 && $3 == "qa"' "$REPO/catalog.tsv" | wc -l | tr -d ' ')
qa_agent="$(awk -F'\t' 'NR > 1 && $3 == "qa" && $2 == "agent" { print $1; exit }' "$REPO/catalog.tsv").md"
qa_agent2="$(awk -F'\t' 'NR > 1 && $3 == "qa" && $2 == "agent" { n++; if (n == 2) { print $1; exit } }' "$REPO/catalog.tsv").md"
qa_skill="$(awk -F'\t' 'NR > 1 && $3 == "qa" && $2 == "skill" { print $1; exit }' "$REPO/catalog.tsv")"
other_skill="$(awk -F'\t' 'NR > 1 && $3 != "qa" && $2 == "skill" { print $1; exit }' "$REPO/catalog.tsv")"

echo "user install"
run
assert "exits 0" test "$rc" = 0
assert "links every agent" test "$(count_links "$CLAUDE_HOME/agents")" = "$n_agents"
assert "links every skill" test "$(count_links "$CLAUDE_HOME/skills")" = "$n_skills"
for f in CLAUDE.md settings.json statusline-command.sh hooks/tmux-claude.sh commands/review-pr-comments.md; do
  assert "links $f" test "$(readlink "$CLAUDE_HOME/$f")" = "$REPO/$f"
done
assert "skill is readable through link" test -f "$CLAUDE_HOME/skills/$qa_skill/SKILL.md"
assert "no backup on a clean install" test ! -d "$CLAUDE_HOME/backups"

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
if PATH="/usr/bin:/bin" command -v claude >/dev/null 2>&1; then
  echo "  skip  reports a missing tool (claude is installed in /usr/bin or /bin)"
else
  assert "reports a missing tool with its purpose" grep -q "missing .*claude (Claude Code itself)" <<<"$out"
fi
mkdir "$TMP/azext/azure-devops"
out="$(PATH="$stubs:/usr/bin:/bin" AZURE_EXTENSION_DIR="$TMP/azext" "$REPO/install.sh" 2>&1)"
assert "empty extension folder counts as missing" grep -q "missing .*az azure-devops extension" <<<"$out"
touch "$TMP/azext/azure-devops/setup.py"
out="$(PATH="$stubs:/usr/bin:/bin" PY_EXIT=0 AZURE_EXTENSION_DIR="$TMP/azext" "$REPO/install.sh" 2>&1)"; rc=$?
assert "exits 0 with all tools" test "$rc" = 0
assert "no extension warning when installed" out_lacks "azure-devops extension"
assert "no openpyxl warning when importable" out_lacks "openpyxl"

echo "macOS python3 stub"
printf '#!/bin/sh\nexit 1\n' >"$stubs/xcode-none"
printf '#!/bin/sh\nexit 0\n' >"$stubs/xcode-ok"
chmod +x "$stubs/xcode-none" "$stubs/xcode-ok"
out="$(PATH="$stubs:/usr/bin:/bin" QA_PY_STUB="$stubs/python3" QA_OS=Darwin QA_XCODE_SELECT="$stubs/xcode-none" "$REPO/install.sh" 2>&1)"; rc=$?
assert "exits 0" test "$rc" = 0
assert "reports the stub without running it" grep -q "only the macOS stub is installed" <<<"$out"
assert "skips the openpyxl probe" out_lacks "openpyxl"
out="$(PATH="$stubs:/usr/bin:/bin" QA_PY_STUB="$stubs/python3" QA_OS=Darwin QA_XCODE_SELECT="$stubs/xcode-ok" "$REPO/install.sh" 2>&1)"
assert "with tools installed, checks openpyxl" grep -q "missing .*openpyxl" <<<"$out"
assert "no stub message" out_lacks "macOS stub"

echo "re-run is idempotent"
run
assert "exits 0" test "$rc" = 0
assert "reports existing links as ok" grep -q "ok .*agents/$qa_agent" <<<"$out"
assert "no new links" test "$(count_links "$CLAUDE_HOME/agents")" = "$n_agents"

echo "backs up what it replaces"
rm "$CLAUDE_HOME/agents/$qa_agent" "$CLAUDE_HOME/settings.json"
echo "mine" >"$CLAUDE_HOME/agents/$qa_agent"
echo '{"autoMode": {}}' >"$CLAUDE_HOME/settings.json"
rm "$CLAUDE_HOME/skills/$other_skill"
ln -s /tmp/elsewhere "$CLAUDE_HOME/skills/$other_skill"
run
assert "exits 0" test "$rc" = 0
assert "reports backup" grep -q "backed up agents/$qa_agent" <<<"$out"
assert "links the agent" test "$(readlink "$CLAUDE_HOME/agents/$qa_agent")" = "$REPO/agents/$qa_agent"
bk="$(backup_dir)"
assert "keeps the replaced file" test "$(cat "$bk/agents/$qa_agent")" = "mine"
assert "keeps the replaced settings byte for byte" test "$(cat "$bk/settings.json")" = '{"autoMode": {}}'
assert "keeps a replaced foreign link" test "$(readlink "$bk/skills/$other_skill")" = /tmp/elsewhere
assert "hints at settings.local.json" grep -q "settings.local.json" <<<"$out"

echo "replaces links left by a moved clone"
rm "$CLAUDE_HOME/skills/$qa_skill"
ln -s "/old/place/skills/$qa_skill" "$CLAUDE_HOME/skills/$qa_skill"
run
assert "reports relink" grep -q "relinked  skills/$qa_skill" <<<"$out"
assert "link points to this repo" test "$(readlink "$CLAUDE_HOME/skills/$qa_skill")" = "$REPO/skills/$qa_skill"

echo "uninstall"
ln -s /tmp/elsewhere "$CLAUDE_HOME/agents/other.md"
mkdir -p "$CLAUDE_HOME/skills/synced"
rm "$CLAUDE_HOME/skills/$qa_skill"
ln -s "/old/place/skills/$qa_skill" "$CLAUDE_HOME/skills/$qa_skill"
run --uninstall
assert "exits 0" test "$rc" = 0
assert "removes agent links without a backup" test ! -e "$CLAUDE_HOME/agents/$qa_agent2"
assert "removes links without a backup" test ! -e "$CLAUDE_HOME/CLAUDE.md"
assert "restores the backed-up settings.json" test "$(cat "$CLAUDE_HOME/settings.json")" = '{"autoMode": {}}'
assert "restored settings.json is a regular file" test ! -L "$CLAUDE_HOME/settings.json"
assert "restores the backed-up agent" test "$(cat "$CLAUDE_HOME/agents/$qa_agent")" = "mine"
assert "restores a backed-up foreign link" test "$(readlink "$CLAUDE_HOME/skills/$other_skill")" = /tmp/elsewhere
assert "reports the restore" grep -q "restored  settings.json" <<<"$out"
assert "removes stale link with our name" test ! -L "$CLAUDE_HOME/skills/$qa_skill"
assert "keeps foreign link" test -L "$CLAUDE_HOME/agents/other.md"
assert "keeps Claude-managed folders" test -d "$CLAUDE_HOME/skills/synced"
assert "keeps backups" test -d "$(backup_dir)"

echo "restores the newest of several backups"
home2="$TMP/home2"
mkdir -p "$home2"
# Both runs use the same stamp, as if they ran in the same second.
echo '{"v": "A"}' >"$home2/settings.json"
CLAUDE_HOME="$home2" BACKUP_STAMP=fixed "$REPO/install.sh" >/dev/null 2>&1
rm "$home2/settings.json"
echo '{"v": "B"}' >"$home2/settings.json"
CLAUDE_HOME="$home2" BACKUP_STAMP=fixed "$REPO/install.sh" >/dev/null 2>&1
assert "first run backs up to -000" test "$(cat "$home2/backups/setup-fixed-000/settings.json")" = '{"v": "A"}'
assert "second run in the same second backs up to -001" test "$(cat "$home2/backups/setup-fixed-001/settings.json")" = '{"v": "B"}'
out="$(CLAUDE_HOME="$home2" "$REPO/install.sh" --uninstall 2>&1)"
assert "restores the newer one" test "$(cat "$home2/settings.json")" = '{"v": "B"}'
assert "reports the restore from -001" grep -q "restored  settings.json (from backups/setup-fixed-001/settings.json)" <<<"$out"
assert "keeps the older one in backups" test -f "$home2/backups/setup-fixed-000/settings.json"

echo "project install"
proj="$TMP/proj"
mkdir -p "$proj"
echo "# existing" >"$proj/CLAUDE.md"
run --project "$proj"
assert "exits 0" test "$rc" = 0
assert "copies every QA entry" test "$(find "$proj/.claude/agents" "$proj/.claude/skills" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ')" = "$n_qa"
assert "copies, does not link" test ! -L "$proj/.claude/agents/$qa_agent"
assert "skips non-QA entries" test ! -e "$proj/.claude/skills/$other_skill"
assert "creates settings.json from the example" cmp -s "$proj/.claude/settings.json" "$REPO/settings.example.json"
assert "keeps existing CLAUDE.md" test "$(cat "$proj/CLAUDE.md")" = "# existing"
assert "reports CLAUDE.md skip" grep -q "SKIP .*CLAUDE.md" <<<"$out"

echo "project re-run and update"
echo "custom" >"$proj/.claude/settings.json"
run --project "$proj"
assert "reports unchanged copies as ok" grep -q "ok .*agents/$qa_agent" <<<"$out"
assert "keeps existing settings.json" test "$(cat "$proj/.claude/settings.json")" = "custom"
echo "local edit" >>"$proj/.claude/agents/$qa_agent"
echo "extra" >"$proj/.claude/skills/$qa_skill/notes.md"
run --project "$proj"
assert "reports changed agent" grep -q "DIFFERS .*agents/$qa_agent" <<<"$out"
assert "does not overwrite without --update" grep -q "local edit" "$proj/.claude/agents/$qa_agent"
run --project "$proj" --update
assert "exits 0" test "$rc" = 0
assert "reports replacement" grep -q "updated .*skills/$qa_skill (local edits and added files replaced)" <<<"$out"
assert "agent matches repo" cmp -s "$proj/.claude/agents/$qa_agent" "$REPO/agents/$qa_agent"
assert "added file removed" test ! -e "$proj/.claude/skills/$qa_skill/notes.md"
assert "--update keeps settings.json" test "$(cat "$proj/.claude/settings.json")" = "custom"
assert "--update keeps CLAUDE.md" test "$(cat "$proj/CLAUDE.md")" = "# existing"

echo "project entries of another kind"
rm -rf "$proj/.claude/skills/$qa_skill"
ln -s "$TMP" "$proj/.claude/skills/$qa_skill"
run --project "$proj" --update
assert "skips symlinked entry" grep -q "SKIP .*skills/$qa_skill (is a symlink" <<<"$out"
assert "symlink untouched" test "$(readlink "$proj/.claude/skills/$qa_skill")" = "$TMP"
rm "$proj/.claude/skills/$qa_skill"
echo "not a dir" >"$proj/.claude/skills/$qa_skill"
run --project "$proj" --update
assert "skips entry of a different type" grep -q "SKIP .*skills/$qa_skill (exists as a different type" <<<"$out"
assert "file untouched" test "$(cat "$proj/.claude/skills/$qa_skill")" = "not a dir"

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
