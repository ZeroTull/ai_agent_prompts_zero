#!/usr/bin/env bash
# Tests install.sh in a temporary CLAUDE_HOME. Never touches the real ~/.claude.
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
own_agent="$(awk -F'\t' 'NR > 1 && $3 == "personal" && $2 == "agent" { print $1; exit }' "$REPO/catalog.tsv").md"
own_agent2="$(awk -F'\t' 'NR > 1 && $3 == "personal" && $2 == "agent" { n++; if (n == 2) { print $1; exit } }' "$REPO/catalog.tsv").md"
own_skill="$(awk -F'\t' 'NR > 1 && $3 == "personal" && $2 == "skill" { print $1; exit }' "$REPO/catalog.tsv")"
other_skill="$(awk -F'\t' 'NR > 1 && $3 == "third-party" && $2 == "skill" { print $1; exit }' "$REPO/catalog.tsv")"

echo "user install"
run
assert "exits 0" test "$rc" = 0
assert "links every agent" test "$(count_links "$CLAUDE_HOME/agents")" = "$n_agents"
assert "links every skill" test "$(count_links "$CLAUDE_HOME/skills")" = "$n_skills"
for f in CLAUDE.md settings.json statusline-command.sh hooks/tmux-claude.sh commands/review-pr-comments.md; do
  assert "links $f" test "$(readlink "$CLAUDE_HOME/$f")" = "$REPO/$f"
done
assert "skill is readable through link" test -f "$CLAUDE_HOME/skills/$own_skill/SKILL.md"
assert "no backup on a clean install" test ! -d "$CLAUDE_HOME/backups"

echo "dependency check"
assert "prints dependency check" grep -q "^Dependency check:" <<<"$out"
assert "reports git as found" grep -Eq "^  found +git$" <<<"$out"

# Stub tools: az records any call, python3 fails or succeeds on demand.
echo "re-run is idempotent"
run
assert "exits 0" test "$rc" = 0
assert "reports existing links as ok" grep -q "ok .*agents/$own_agent" <<<"$out"
assert "no new links" test "$(count_links "$CLAUDE_HOME/agents")" = "$n_agents"

echo "backs up what it replaces"
rm "$CLAUDE_HOME/agents/$own_agent" "$CLAUDE_HOME/settings.json"
echo "mine" >"$CLAUDE_HOME/agents/$own_agent"
echo '{"autoMode": {}}' >"$CLAUDE_HOME/settings.json"
rm "$CLAUDE_HOME/skills/$other_skill"
ln -s /tmp/elsewhere "$CLAUDE_HOME/skills/$other_skill"
run
assert "exits 0" test "$rc" = 0
assert "reports backup" grep -q "backed up agents/$own_agent" <<<"$out"
assert "links the agent" test "$(readlink "$CLAUDE_HOME/agents/$own_agent")" = "$REPO/agents/$own_agent"
bk="$(backup_dir)"
assert "keeps the replaced file" test "$(cat "$bk/agents/$own_agent")" = "mine"
assert "keeps the replaced settings byte for byte" test "$(cat "$bk/settings.json")" = '{"autoMode": {}}'
assert "keeps a replaced foreign link" test "$(readlink "$bk/skills/$other_skill")" = /tmp/elsewhere
assert "says where settings changes belong" grep -q "Claude Code reads user settings only from that file" <<<"$out"

echo "replaces links left by a moved clone"
rm "$CLAUDE_HOME/skills/$own_skill"
ln -s "/old/place/skills/$own_skill" "$CLAUDE_HOME/skills/$own_skill"
run
assert "backs up the broken link" grep -q "backed up skills/$own_skill (was a broken link)" <<<"$out"
assert "link points to this repo" test "$(readlink "$CLAUDE_HOME/skills/$own_skill")" = "$REPO/skills/$own_skill"

echo "uninstall"
ln -s /tmp/elsewhere "$CLAUDE_HOME/agents/other.md"
mkdir -p "$CLAUDE_HOME/skills/synced"
rm "$CLAUDE_HOME/skills/$own_skill"
ln -s "/old/place/skills/$own_skill" "$CLAUDE_HOME/skills/$own_skill"
run --uninstall
assert "exits 0" test "$rc" = 0
assert "removes agent links without a backup" test ! -e "$CLAUDE_HOME/agents/$own_agent2"
assert "removes links without a backup" test ! -e "$CLAUDE_HOME/CLAUDE.md"
assert "restores the backed-up settings.json" test "$(cat "$CLAUDE_HOME/settings.json")" = '{"autoMode": {}}'
assert "restored settings.json is a regular file" test ! -L "$CLAUDE_HOME/settings.json"
assert "restores the backed-up agent" test "$(cat "$CLAUDE_HOME/agents/$own_agent")" = "mine"
assert "restores a backed-up foreign link" test "$(readlink "$CLAUDE_HOME/skills/$other_skill")" = /tmp/elsewhere
assert "reports the restore" grep -q "restored  settings.json" <<<"$out"
assert "restores the broken link it had backed up" test "$(readlink "$CLAUDE_HOME/skills/$own_skill")" = "/old/place/skills/$own_skill"
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

echo "refuses a linked agents folder"
linked="$TMP/linked"
mkdir -p "$linked" "$TMP/elsewhere-agents"
ln -s "$TMP/elsewhere-agents" "$linked/agents"
out="$(CLAUDE_HOME="$linked" "$REPO/install.sh" 2>&1)"; rc=$?
assert "exits 1" test "$rc" = 1
assert "writes nothing into the linked folder" test -z "$(ls -A "$TMP/elsewhere-agents")"

echo "refuses linked commands and hooks folders"
for d in commands hooks; do
  lh="$TMP/linked-$d"
  mkdir -p "$lh" "$TMP/elsewhere-$d"
  ln -s "$TMP/elsewhere-$d" "$lh/$d"
  out="$(CLAUDE_HOME="$lh" "$REPO/install.sh" 2>&1)"; rc=$?
  assert "exits 1 for a linked $d folder" test "$rc" = 1
  assert "writes nothing into the linked $d folder" test -z "$(ls -A "$TMP/elsewhere-$d")"
done

echo "removes links to entries that left this repo"
home3="$TMP/home3"
CLAUDE_HOME="$home3" "$REPO/install.sh" >/dev/null 2>&1
ln -s "$REPO/agents/moved-away.md" "$home3/agents/moved-away.md"
ln -s "$REPO/skills/moved-skill" "$home3/skills/moved-skill"
ln -s /elsewhere/agents/foreign.md "$home3/agents/foreign.md"
out="$(CLAUDE_HOME="$home3" "$REPO/install.sh" 2>&1)"
assert "removes the dead agent link" test ! -L "$home3/agents/moved-away.md"
assert "removes the dead skill link" test ! -L "$home3/skills/moved-skill"
assert "reports the removal" grep -q "removed   agents/moved-away.md (no longer in this repo" <<<"$out"
assert "backs up the removed link" test -L "$(find "$home3/backups" -name moved-away.md | head -n 1)"
assert "keeps dead links into other places" test -L "$home3/agents/foreign.md"
ln -s "$REPO/agents/moved-away.md" "$home3/agents/moved-away.md"
out="$(CLAUDE_HOME="$home3" "$REPO/install.sh" --uninstall 2>&1)"
assert "uninstall also removes dead links into this repo" test ! -L "$home3/agents/moved-away.md"

echo "runs through a symlink to the script"
mkdir -p "$TMP/bin"
ln -s "$REPO/install.sh" "$TMP/bin/dev-install"
out="$(CLAUDE_HOME="$TMP/via-link" "$TMP/bin/dev-install" 2>&1)"; rc=$?
assert "exits 0" test "$rc" = 0
assert "links into the real repo" test "$(readlink "$TMP/via-link/CLAUDE.md")" = "$REPO/CLAUDE.md"

echo "arguments"
run --help
assert "--help exits 0" test "$rc" = 0
assert "--help prints usage" grep -q -- "--uninstall" <<<"$out"
run --uninstall extra
assert "extra uninstall argument exits 1" test "$rc" = 1
run --bogus
assert "unknown option exits 1" test "$rc" = 1

[[ $fail -eq 0 ]] && echo "test_install: all passed"
exit $fail
