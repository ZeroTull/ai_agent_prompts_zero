#!/usr/bin/env bash
# Installs this Claude Code setup.
#   ./install.sh                             link everything into ~/.claude (git pull here updates it)
#   ./install.sh --project <path> [--update] copy the QA agents and skills into <path>/.claude for a team
#   ./install.sh --uninstall                 remove the links created by the user install
# Anything the user install replaces is moved to ~/.claude/backups/setup-<timestamp>/ first.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_HOME="${CLAUDE_HOME:-$HOME/.claude}"
BACKUP_DIR="$CLAUDE_HOME/backups/setup-$(date +%Y%m%d-%H%M%S)"

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

# Links $CLAUDE_HOME/<rel> to $REPO/<rel>, backing up whatever was there.
link_one() {
  local rel="$1" src="$REPO/$1" dest="$CLAUDE_HOME/$1"
  if [[ -L "$dest" && "$(readlink "$dest")" == "$src" ]]; then
    echo "  ok        $rel"
    return
  fi
  if is_stale_link "$dest"; then
    rm "$dest"
    echo "  relinked  $rel (old target was missing)"
  elif [[ -e "$dest" || -L "$dest" ]]; then
    mkdir -p "$BACKUP_DIR/$(dirname "$rel")"
    mv "$dest" "$BACKUP_DIR/$rel"
    echo "  backed up $rel"
  else
    echo "  linked    $rel"
  fi
  mkdir -p "$(dirname "$dest")"
  ln -s "$src" "$dest"
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

kind() { if [[ -d "$1" ]]; then echo dir; else echo file; fi; }

copy_one() {
  local src="$1" dest="$2" update="$3"
  if [[ -L "$dest" ]]; then
    echo "  SKIP      $dest (is a symlink - remove it to install a copy)"
  elif [[ -e "$dest" && "$(kind "$src")" != "$(kind "$dest")" ]]; then
    echo "  SKIP      $dest (exists as a different type - remove it to install)"
  elif [[ ! -e "$dest" ]]; then
    cp -R "$src" "$dest"
    echo "  copied    $dest"
  elif diff -rq "$src" "$dest" >/dev/null 2>&1; then
    echo "  ok        $dest"
  elif [[ "$update" == yes ]]; then
    rm -rf "$dest"
    cp -R "$src" "$dest"
    echo "  updated   $dest (local edits and added files replaced)"
  else
    echo "  DIFFERS   $dest (--update replaces it, including local edits)"
  fi
}

# Prints "kind name" for every QA entry in the catalog.
qa_entries() {
  awk -F'\t' 'NR > 1 && $3 == "qa" { print $2, $1 }' "$REPO/catalog.tsv"
}

copy_if_absent() {
  local src="$1" dest="$2" hint="$3"
  if [[ -e "$dest" ]]; then
    echo "  SKIP      $dest (exists - $hint)"
  else
    cp "$src" "$dest"
    echo "  copied    $dest"
  fi
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
az|Azure DevOps work items, PRs and pipelines - or use the Azure DevOps MCP server
python3|Excel requirements in /test-developer
DEPS
  local py
  py="$(command -v python3 || true)"
  # On macOS without Command Line Tools, /usr/bin/python3 is a stub that opens an install dialog.
  # The QA_* variables exist so tests can simulate that machine.
  if [[ "$py" == "${QA_PY_STUB:-/usr/bin/python3}" && "${QA_OS:-$(uname -s)}" == Darwin ]] &&
    ! "${QA_XCODE_SELECT:-xcode-select}" -p >/dev/null 2>&1; then
    echo "  missing   python3 (only the macOS stub is installed: xcode-select --install or brew install python)"
  elif [[ -n "$py" ]] && ! "$py" -c "import openpyxl" >/dev/null 2>&1; then
    echo "  missing   openpyxl (Excel requirements in /test-developer: pip3 install --user openpyxl)"
  fi
  # Checks the extension folder instead of running az, which can be slow to start.
  local azext="${AZURE_EXTENSION_DIR:-$HOME/.azure/cliextensions}/azure-devops"
  if command -v az >/dev/null 2>&1 && [[ -z "$(ls -A "$azext" 2>/dev/null)" ]]; then
    echo "  missing   az azure-devops extension (az extension add --name azure-devops)"
  fi
}

uninstall() {
  local n=0 link target rel
  while IFS= read -r rel; do
    link="$CLAUDE_HOME/$rel"
    [[ -L "$link" ]] || continue
    target="$(readlink "$link")"
    if [[ "$target" == "$REPO/"* ]] || is_stale_link "$link"; then
      rm "$link"
      echo "  removed   $rel"
      n=$((n + 1))
    fi
  done < <(user_entries)
  echo "Removed $n link(s). Backups from earlier installs stay in $CLAUDE_HOME/backups/."
}

case "${1:-}" in
  "")
    echo "Linking into $CLAUDE_HOME"
    mkdir -p "$CLAUDE_HOME"
    while IFS= read -r rel; do
      link_one "$rel"
    done < <(user_entries)
    if [[ -d "$BACKUP_DIR" ]]; then
      echo
      echo "Replaced files were moved to $BACKUP_DIR."
      echo "If settings.json was among them, check it for changes Claude Code made (e.g. autoMode) and move"
      echo "machine-specific ones to $CLAUDE_HOME/settings.local.json."
    fi
    check_dependencies
    echo
    echo "Done. Restart Claude Code to pick up the new config."
    ;;
  --project)
    [[ -n "${2:-}" ]] || die "--project needs a directory"
    [[ -d "$2" ]] || die "not a directory: $2"
    update=no
    if [[ $# -eq 3 && "$3" == --update ]]; then
      update=yes
    elif [[ $# -gt 2 ]]; then
      die "unexpected arguments after --project $2"
    fi
    project="$(cd "$2" && pwd)"
    mkdir -p "$project/.claude/agents" "$project/.claude/skills"
    echo "QA agents and skills -> $project/.claude"
    while read -r k name; do
      case "$k" in
        agent) copy_one "$REPO/agents/$name.md" "$project/.claude/agents/$name.md" "$update" ;;
        skill) copy_one "$REPO/skills/$name" "$project/.claude/skills/$name" "$update" ;;
      esac
    done < <(qa_entries)
    copy_if_absent "$REPO/settings.example.json" "$project/.claude/settings.json" "merge settings.example.json by hand"
    copy_if_absent "$REPO/templates/CLAUDE.md" "$project/CLAUDE.md" "add the sections from templates/CLAUDE.md by hand"
    check_dependencies
    echo
    echo "Note: agents or skills removed from this repo are not deleted from $project/.claude - remove them by hand."
    echo "Next: open Claude Code in $project and run /qa-conventions."
    ;;
  --uninstall)
    [[ $# -eq 1 ]] || die "--uninstall takes no arguments"
    uninstall
    ;;
  -h|--help) usage 0 ;;
  *) die "unknown option $1" ;;
esac
