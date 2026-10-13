#!/usr/bin/env bash
# Checks that every agent and skill is loadable by Claude Code and listed in the docs.
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fail=0
err() { echo "FAIL: $*"; fail=1; }

# Prints the value of a top-level frontmatter key, or nothing.
fm() {
  awk -v key="$2" '
    NR == 1 { if ($0 != "---") exit; next }
    $0 == "---" { exit }
    index($0, key ": ") == 1 { print substr($0, length(key) + 3); exit }
  ' "$1"
}

check_entry() {
  local file="$1" expected="$2" name desc
  [[ "$(head -n 1 "$file")" == "---" ]] || { err "$file: missing frontmatter"; return; }
  name="$(fm "$file" name)"
  desc="$(fm "$file" description)"
  [[ "$name" == "$expected" ]] || err "$file: name '$name' does not match '$expected'"
  [[ "$name" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]] || err "$file: name '$name' is not kebab-case"
  [[ ${#desc} -ge 40 ]] || err "$file: description missing or too short"
  grep -Eq "\`/?$expected\`" "$REPO/templates/CLAUDE.md" || err "$expected not listed in templates/CLAUDE.md"
  grep -Eq "\`/?$expected\`" "$REPO/README.md" || err "$expected not listed in README.md"
}

shopt -s nullglob
agents=("$REPO"/agents/*.md)
skills=("$REPO"/skills/*/)
[[ ${#agents[@]} -gt 0 ]] || err "no agents found"
[[ ${#skills[@]} -gt 0 ]] || err "no skills found"

for f in "${agents[@]}"; do
  check_entry "$f" "$(basename "$f" .md)"
  model="$(fm "$f" model)"
  [[ -z "$model" || "$model" =~ ^(inherit|opus|sonnet|haiku)$ ]] || err "$f: unknown model '$model'"
done

for d in "${skills[@]}"; do
  d="${d%/}"
  [[ -f "$d/SKILL.md" ]] || { err "$d: missing SKILL.md"; continue; }
  check_entry "$d/SKILL.md" "$(basename "$d")"
done

python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$REPO/settings.example.json" \
  || err "settings.example.json is not valid JSON"

[[ $fail -eq 0 ]] && echo "validate: all checks passed (${#agents[@]} agents, ${#skills[@]} skills)"
exit $fail
