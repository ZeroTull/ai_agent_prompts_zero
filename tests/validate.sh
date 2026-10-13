#!/usr/bin/env bash
# Checks that every agent and skill is loadable by Claude Code, carries the safety rules, and is documented.
# Usage: tests/validate.sh [repo-dir]   (defaults to this repo)
set -uo pipefail

REPO="$(cd "${1:-$(dirname "${BASH_SOURCE[0]}")/..}" && pwd)"
fail=0
err() { echo "FAIL: $*"; fail=1; }

# Parses YAML frontmatter with a real YAML parser and prints name, description and model separated by \x1f,
# or exits non-zero with a reason.
frontmatter() {
  ruby -ryaml -e '
    text = File.read(ARGV[0])
    m = text.match(/\A---\n(.*?)\n---\n/m) or abort("missing frontmatter block")
    begin
      data = YAML.safe_load(m[1])
    rescue Psych::Exception => e
      abort("invalid YAML: #{e.message.lines.first.strip}")
    end
    abort("frontmatter is not a mapping") unless data.is_a?(Hash)
    puts [data["name"], data["description"], data["model"]].map { |v| v.to_s.gsub(/\s+/, " ") }.join("\x1f")
  ' "$1" 2>&1
}

SAFETY_FILE="$REPO/templates/safety.md"
[[ -s "$SAFETY_FILE" ]] || err "templates/safety.md missing or empty"

# True if file $1 contains the whole safety block verbatim.
has_safety_block() {
  ruby -e 'exit(File.read(ARGV[0]).include?(File.read(ARGV[1]).strip) ? 0 : 1)' "$1" "$SAFETY_FILE" 2>/dev/null
}

check_entry() {
  local file="$1" expected="$2" out name desc model
  if ! out="$(frontmatter "$file")"; then
    err "$file: $out"
    return
  fi
  IFS=$'\x1f' read -r name desc model <<<"$out"
  [[ "$name" == "$expected" ]] || err "$file: name '$name' does not match '$expected'"
  [[ "$name" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]] || err "$file: name '$name' is not kebab-case"
  [[ ${#desc} -ge 40 ]] || err "$file: description missing or too short"
  [[ -z "$model" || "$model" =~ ^(inherit|opus|sonnet|haiku|claude-[a-z0-9.-]+)$ ]] || err "$file: unknown model '$model'"
  has_safety_block "$file" || err "$file: does not contain the block from templates/safety.md verbatim"
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
done

for d in "${skills[@]}"; do
  d="${d%/}"
  [[ -f "$d/SKILL.md" ]] || { err "$d: missing SKILL.md"; continue; }
  check_entry "$d/SKILL.md" "$(basename "$d")"
done

# Settings must parse, deny the core secret locations, and keep committed .env templates readable.
settings_problem="$(ruby -rjson -e '
  begin
    deny = JSON.parse(File.read(ARGV[0])).dig("permissions", "deny") || []
  rescue JSON::ParserError
    puts "settings.example.json is not valid JSON"; exit
  end
  required = ["Read(**/.env)", "Read(**/.env.local)", "Read(**/.env.production)", "Read(~/.ssh/**)", "Read(~/.azure/**)", "Read(~/.config/gh/**)", "Read(**/*.pem)"]
  missing = required - deny
  puts "settings.example.json misses deny rules: #{missing.join(", ")}" unless missing.empty?
  wild = deny.grep(/\ARead\((\*\*\/)?\.env\.\*\)\z/)
  puts "settings.example.json denies .env templates via #{wild.join(", ")}" unless wild.empty?
' "$REPO/settings.example.json" 2>&1)"
[[ -z "$settings_problem" ]] || err "$settings_problem"

[[ $fail -eq 0 ]] && echo "validate: all checks passed (${#agents[@]} agents, ${#skills[@]} skills)"
exit $fail
