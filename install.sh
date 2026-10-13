#!/usr/bin/env bash
# Installs the QA agents and skills for Claude Code.
#   ./install.sh                    symlink into ~/.claude (all your repos, updates with git pull)
#   ./install.sh --project <path>   copy into <path>/.claude (commit it to share with the team)
#   ./install.sh --uninstall        remove symlinks created by the user-level install
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

# Link (user mode) or copy (project mode) one agent file or skill directory.
place() {
  local mode="$1" src="$2" dest="$3"
  if [[ -L "$dest" && "$(readlink "$dest")" == "$src" ]]; then
    echo "  ok       $dest"
    return
  fi
  if [[ -e "$dest" || -L "$dest" ]]; then
    echo "  SKIP     $dest (already exists, not ours - remove it to install)"
    return
  fi
  if [[ "$mode" == link ]]; then
    ln -s "$src" "$dest"
    echo "  linked   $dest"
  else
    cp -R "$src" "$dest"
    echo "  copied   $dest"
  fi
}

install_into() {
  local mode="$1" target="$2"
  mkdir -p "$target/agents" "$target/skills"
  echo "Agents -> $target/agents"
  for f in "$REPO"/agents/*.md; do
    place "$mode" "$f" "$target/agents/$(basename "$f")"
  done
  echo "Skills -> $target/skills"
  for d in "$REPO"/skills/*/; do
    d="${d%/}"
    place "$mode" "$d" "$target/skills/$(basename "$d")"
  done
}

uninstall() {
  local n=0 link
  for link in "$CLAUDE_HOME"/agents/* "$CLAUDE_HOME"/skills/*; do
    if [[ -L "$link" && "$(readlink "$link")" == "$REPO"/* ]]; then
      rm "$link"
      echo "  removed  $link"
      n=$((n + 1))
    fi
  done
  echo "Removed $n link(s)."
}

case "${1:-}" in
  "")
    install_into link "$CLAUDE_HOME"
    echo
    echo "Next: merge settings.example.json into $CLAUDE_HOME/settings.json (deny rules for secrets)."
    ;;
  --project)
    [[ -n "${2:-}" && -d "$2" ]] || { echo "error: --project needs an existing directory" >&2; usage 1; }
    project="$(cd "$2" && pwd)"
    install_into copy "$project/.claude"
    if [[ ! -e "$project/.claude/settings.json" ]]; then
      cp "$REPO/settings.example.json" "$project/.claude/settings.json"
      echo "  copied   $project/.claude/settings.json"
    else
      echo "  SKIP     $project/.claude/settings.json (exists - merge settings.example.json by hand)"
    fi
    if [[ ! -e "$project/CLAUDE.md" ]]; then
      cp "$REPO/templates/CLAUDE.md" "$project/CLAUDE.md"
      echo "  copied   $project/CLAUDE.md"
    else
      echo "  SKIP     $project/CLAUDE.md (exists - see templates/CLAUDE.md for the section to add)"
    fi
    echo
    echo "Next: open Claude Code in $project and run /qa-conventions."
    ;;
  --uninstall) uninstall ;;
  -h|--help) usage 0 ;;
  *) echo "error: unknown option $1" >&2; usage 1 ;;
esac
