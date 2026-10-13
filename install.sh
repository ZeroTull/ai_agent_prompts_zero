#!/usr/bin/env bash
# Installs this Claude Code setup (claude-dev).
#   ./install.sh               link everything into ~/.claude (git pull here updates it)
#   ./install.sh --uninstall   remove the links and restore what they replaced
#   ./install.sh --help        show this help
# Anything the user install replaces is moved to ~/.claude/backups/setup-<timestamp>/ first.
set -euo pipefail

# Resolve the script's real location, so running it through a symlink still finds the repo.
SELF="${BASH_SOURCE[0]}"
while [[ -L "$SELF" ]]; do
  target="$(readlink "$SELF")"
  [[ "$target" == /* ]] || target="$(dirname "$SELF")/$target"
  SELF="$target"
done
REPO="$(cd "$(dirname "$SELF")" && pwd)"
CLAUDE_HOME="${CLAUDE_HOME:-$HOME/.claude}"
BACKUP_DIR=""

# Sets this run's backup folder on first use: setup-<stamp>-NNN, the first free NNN. A second run in the
# same second gets the next number, so backups never overwrite each other and sort oldest to newest.
# BACKUP_STAMP exists so tests can force two runs into the same second.
init_backup_dir() {
  [[ -z "$BACKUP_DIR" ]] || return 0
  local base i=0
  base="$CLAUDE_HOME/backups/setup-${BACKUP_STAMP:-$(date +%Y%m%d-%H%M%S)}"
  while :; do
    BACKUP_DIR="$(printf '%s-%03d' "$base" "$i")"
    [[ -e "$BACKUP_DIR" ]] || return 0
    i=$((i + 1))
    if [[ $i -gt 999 ]]; then
      echo "error: more than 1000 backups for one second in $CLAUDE_HOME/backups" >&2
      exit 1
    fi
  done
}

usage() {
  local code="${1:-0}"
  if [[ "$code" -eq 0 ]]; then
    sed -n '2,6p' "$0" | sed 's/^# \{0,1\}//'
  else
    sed -n '2,6p' "$0" | sed 's/^# \{0,1\}//' >&2
  fi
  exit "$code"
}

die() {
  echo "error: $*" >&2
  usage 1
}

# True for a broken link that points at <something>/<dir>/<name> where <dir>/<name> matches the link's own
# location, i.e. a link left behind by an earlier install from a clone that has since moved.
is_stale_link() {
  local dest="$1" target
  [[ -L "$dest" && ! -e "$dest" ]] || return 1
  target="$(readlink "$dest")"
  [[ "$(basename "$target")" == "$(basename "$dest")" ]] || return 1
  [[ "$(basename "$(dirname "$target")")" == "$(basename "$(dirname "$dest")")" ]]
}

# Links $CLAUDE_HOME/<rel> to $REPO/<rel>. Whatever was there (a file, a folder, a link from another repo or a
# broken link) is moved to the backup folder first, so --uninstall can put it back.
link_one() {
  local rel="$1" src="$REPO/$1" dest="$CLAUDE_HOME/$1" note=""
  if [[ -L "$dest" && "$(readlink "$dest")" == "$src" ]]; then
    echo "  ok        $rel"
    return
  fi
  if [[ -e "$dest" || -L "$dest" ]]; then
    if is_stale_link "$dest"; then
      note=" (was a broken link)"
    elif [[ -L "$dest" ]]; then
      note=" (was a link to $(readlink "$dest"))"
    fi
    init_backup_dir
    mkdir -p "$BACKUP_DIR/$(dirname "$rel")"
    mv "$dest" "$BACKUP_DIR/$rel"
    echo "  backed up $rel$note"
  else
    echo "  linked    $rel"
  fi
  mkdir -p "$(dirname "$dest")"
  ln -s "$src" "$dest"
}

# Refuses to install into an agents or skills folder under <base> that is itself a link, because the entries
# would land inside whatever that folder points to.
check_target_dirs() {
  local base="$1" d
  for d in agents skills commands hooks; do
    if [[ -L "$base/$d" ]]; then
      echo "error: $base/$d is a link to $(readlink "$base/$d"); installing would write into it." >&2
      echo "       Replace it with a real folder first." >&2
      exit 1
    fi
  done
}

# Backs up and removes broken links into this repo whose entry no longer exists here (for example an agent that
# moved to another repo), so ~/.claude keeps no dead links after an upgrade.
prune_removed() {
  local link target rel
  for link in "$CLAUDE_HOME"/agents/* "$CLAUDE_HOME"/skills/* "$CLAUDE_HOME"/commands/* "$CLAUDE_HOME"/hooks/*; do
    [[ -L "$link" && ! -e "$link" ]] || continue
    target="$(readlink "$link")"
    [[ "$target" == "$REPO/"* ]] || continue
    rel="${link#"$CLAUDE_HOME"/}"
    init_backup_dir
    mkdir -p "$BACKUP_DIR/$(dirname "$rel")"
    mv "$link" "$BACKUP_DIR/$rel"
    echo "  removed   $rel (no longer in this repo; link backed up)"
  done
}

# Prints every path the user install links, relative to the repo.
user_entries() {
  local f
  for f in CLAUDE.md settings.json statusline-command.sh; do echo "$f"; done
  for f in "$REPO"/hooks/* "$REPO"/commands/*.md "$REPO"/agents/*.md "$REPO"/skills/*/; do
    [[ -e "$f" ]] || continue
    f="${f%/}"
    echo "${f#"$REPO"/}"
  done
}

# Reports optional tools the setup uses. Never fails the install.
check_dependencies() {
  local cmd purpose
  echo
  echo "Dependency check:"
  while IFS='|' read -r cmd purpose; do
    if command -v "$cmd" >/dev/null 2>&1; then
      echo "  found     $cmd"
    else
      echo "  missing   $cmd ($purpose)"
    fi
  done <<'DEPS'
claude|Claude Code itself
git|diffs, PR reviews
jq|status line
gh|GitHub PRs and Actions runs
glab|GitLab MRs in the PR workflow
python3|tests/validate.sh
DEPS
}

# Prints the newest backup of <rel>, if any. Folder names sort by time under byte order (LC_ALL=C).
latest_backup() {
  local b found
  found="$(for b in "$CLAUDE_HOME"/backups/setup-*/"$1"; do
    if [[ -e "$b" || -L "$b" ]]; then printf '%s\n' "$b"; fi
  done | LC_ALL=C sort | tail -n 1)"
  [[ -n "$found" ]] && echo "$found"
}

# Removes our links and puts back the newest backup of each, so the machine returns to its state before install.
uninstall() {
  local n=0 link target rel backup
  while IFS= read -r rel; do
    link="$CLAUDE_HOME/$rel"
    [[ -L "$link" ]] || continue
    target="$(readlink "$link")"
    if [[ "$target" == "$REPO/"* ]] || is_stale_link "$link"; then
      rm "$link"
      n=$((n + 1))
      if backup="$(latest_backup "$rel")"; then
        mv "$backup" "$link"
        echo "  restored  $rel (from ${backup#"$CLAUDE_HOME"/})"
      else
        echo "  removed   $rel"
      fi
    fi
  done < <(user_entries)
  for link in "$CLAUDE_HOME"/agents/* "$CLAUDE_HOME"/skills/* "$CLAUDE_HOME"/commands/* "$CLAUDE_HOME"/hooks/*; do
    if [[ -L "$link" && ! -e "$link" && "$(readlink "$link")" == "$REPO/"* ]]; then
      rm "$link"
      echo "  removed   ${link#"$CLAUDE_HOME"/} (pointed to an entry no longer in this repo)"
      n=$((n + 1))
    fi
  done
  echo "Removed $n link(s). Older backups stay in $CLAUDE_HOME/backups/."
}

case "${1:-}" in
  "")
    echo "Linking into $CLAUDE_HOME"
    check_target_dirs "$CLAUDE_HOME"
    mkdir -p "$CLAUDE_HOME"
    while IFS= read -r rel; do
      link_one "$rel"
    done < <(user_entries)
    prune_removed
    if [[ -n "$BACKUP_DIR" ]]; then
      echo
      echo "Replaced files were moved to $BACKUP_DIR."
      echo "If settings.json was among them, Claude Code had changed it (for example from /config). Copy any change"
      echo "worth keeping into settings.json in this repo; Claude Code reads user settings only from that file."
    fi
    check_dependencies
    echo
    echo "Done. Restart Claude Code to pick up the new config."
    ;;
  --uninstall)
    [[ $# -eq 1 ]] || die "--uninstall takes no arguments"
    uninstall
    ;;
  -h|--help) usage 0 ;;
  *) die "unknown option $1" ;;
esac
