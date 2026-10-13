#!/usr/bin/env bash
# Installs the QA agents and skills for Claude Code.
#   ./install.sh                             symlink into ~/.claude (all your repos, updates with git pull)
#   ./install.sh --project <path> [--update] copy into <path>/.claude; --update replaces changed copies (local edits included)
#   ./install.sh --uninstall                 remove symlinks created by the user-level install
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_HOME="${CLAUDE_HOME:-$HOME/.claude}"

usage() {
  local code="${1:-0}"
  if [[ "$code" -eq 0 ]]; then
    sed -n '2,5p' "$0" | sed 's/^# \{0,1\}//'
  else
    sed -n '2,5p' "$0" | sed 's/^# \{0,1\}//' >&2
  fi
  exit "$code"
}

die() {
  echo "error: $*" >&2
  usage 1
}

# True for a broken link that points at <something>/agents/<name> or <something>/skills/<name>,
# i.e. a link left behind by an earlier install from a repo that has since moved.
is_stale_link() {
  local dest="$1" target
  [[ -L "$dest" && ! -e "$dest" ]] || return 1
  target="$(readlink "$dest")"
  [[ "$(basename "$target")" == "$(basename "$dest")" ]] || return 1
  [[ "$(basename "$(dirname "$target")")" == "$(basename "$(dirname "$dest")")" ]]
}

link_one() {
  local src="$1" dest="$2"
  if [[ -L "$dest" && "$(readlink "$dest")" == "$src" ]]; then
    echo "  ok        $dest"
  elif is_stale_link "$dest"; then
    rm "$dest"
    ln -s "$src" "$dest"
    echo "  relinked  $dest (old target was missing)"
  elif [[ -e "$dest" || -L "$dest" ]]; then
    echo "  SKIP      $dest (exists and is not ours - remove it to install)"
  else
    ln -s "$src" "$dest"
    echo "  linked    $dest"
  fi
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

# Calls "$1" for every agent file and skill directory with (src, dest, extra args...).
each_entry() {
  local fn="$1" target="$2" src
  shift 2
  mkdir -p "$target/agents" "$target/skills"
  echo "Agents -> $target/agents"
  for src in "$REPO"/agents/*.md; do
    "$fn" "$src" "$target/agents/$(basename "$src")" "$@"
  done
  echo "Skills -> $target/skills"
  for src in "$REPO"/skills/*/; do
    src="${src%/}"
    "$fn" "$src" "$target/skills/$(basename "$src")" "$@"
  done
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

# Reports optional tools the agents use. Never fails the install.
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
az|Azure DevOps work items, PRs and pipelines - or use the Azure DevOps MCP server
gh|GitHub PRs and Actions runs
python3|Excel requirements in /test-developer
DEPS
  local py
  py="$(command -v python3 || true)"
  # On macOS without Command Line Tools, /usr/bin/python3 is a stub that opens an install dialog.
  if [[ "$py" == /usr/bin/python3 && "$(uname -s)" == Darwin ]] && ! xcode-select -p >/dev/null 2>&1; then
    echo "  missing   python3 (only the macOS stub is installed: xcode-select --install or brew install python)"
  elif [[ -n "$py" ]] && ! "$py" -c "import openpyxl" >/dev/null 2>&1; then
    echo "  missing   openpyxl (Excel requirements in /test-developer: pip3 install --user openpyxl)"
  fi
  # Checks the extension folder instead of running az, which can be slow to start.
  if command -v az >/dev/null 2>&1 && [[ ! -d "${AZURE_EXTENSION_DIR:-$HOME/.azure/cliextensions}/azure-devops" ]]; then
    echo "  missing   az azure-devops extension (az extension add --name azure-devops)"
  fi
}

uninstall() {
  local n=0 link target
  for link in "$CLAUDE_HOME"/agents/* "$CLAUDE_HOME"/skills/*; do
    [[ -L "$link" ]] || continue
    target="$(readlink "$link")"
    # A stale link counts as ours only if this repo ships an entry with the same name.
    if [[ "$target" == "$REPO/"* ]] ||
      { is_stale_link "$link" && [[ -e "$REPO/$(basename "$(dirname "$link")")/$(basename "$link")" ]]; }; then
      rm "$link"
      echo "  removed   $link"
      n=$((n + 1))
    fi
  done
  echo "Removed $n link(s)."
}

case "${1:-}" in
  "")
    install_target="$CLAUDE_HOME"
    each_entry link_one "$install_target"
    check_dependencies
    echo
    echo "Next: merge settings.example.json into $CLAUDE_HOME/settings.json (deny rules for secrets)."
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
    each_entry copy_one "$project/.claude" "$update"
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
