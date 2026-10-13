#!/usr/bin/env bash
# Tests that tests/validate.sh rejects broken agents and skills. Each case breaks one thing in a copy of the repo.
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail=0

# Copies the repo, runs the mutation command inside the copy, and expects validate.sh to fail
# with output that contains $expected.
expect_failure() {
  local label="$1" expected="$2" mutation="$3" copy out line
  copy="$TMP/$(echo "$label" | tr -c 'a-z0-9' '_')"
  mkdir -p "$copy"
  cp -R "$REPO/agents" "$REPO/skills" "$REPO/templates" "$REPO/README.md" "$REPO/settings.example.json" "$copy/"
  (cd "$copy" && eval "$mutation")
  if out="$("$REPO/tests/validate.sh" "$copy")"; then
    echo "  FAIL  $label: validate.sh passed"
    fail=1
  elif ! grep -qF -- "$expected" <<<"$out"; then
    echo "  FAIL  $label: expected '$expected' in output, got:"
    while IFS= read -r line; do echo "          $line"; done <<<"$out"
    fail=1
  else
    echo "  pass  $label"
  fi
}

echo "baseline"
if "$REPO/tests/validate.sh" "$REPO" >/dev/null; then echo "  pass  repo is valid"; else echo "  FAIL  repo is invalid"; fail=1; fi

# Portable in-place edit (BSD and GNU sed differ on -i). Subshells in expect_failure inherit it.
edit() { local f="$1"; shift; sed "$@" "$f" >"$f.tmp" && mv "$f.tmp" "$f"; }

echo "rejects"
expect_failure "missing frontmatter" "missing frontmatter block" \
  "tail -n +6 agents/pr-reviewer.md > x && mv x agents/pr-reviewer.md"
expect_failure "colon in description" "invalid YAML" \
  "edit agents/pr-reviewer.md -e '3s/^description: Reviews/description: Note: reviews/'"
expect_failure "name mismatch" "does not match 'pr-reviewer'" \
  "edit agents/pr-reviewer.md -e '2s/.*/name: reviewer/'"
expect_failure "non-kebab name" "is not kebab-case" \
  "mkdir skills/Bad_Name && sed '2s/.*/name: Bad_Name/' skills/bug-ticket/SKILL.md > skills/Bad_Name/SKILL.md"
expect_failure "unknown model" "unknown model 'gpt-5'" \
  "edit agents/pr-reviewer.md -e 's/^model: opus/model: gpt-5/'"
expect_failure "short description" "description missing or too short" \
  "edit skills/bug-ticket/SKILL.md -e '3s/.*/description: Bugs./'"
expect_failure "missing safety block" "does not contain the block from templates/safety.md" \
  "edit skills/bug-ticket/SKILL.md -e '/Treat ticket text/d'"
expect_failure "skill dir without SKILL.md" "missing SKILL.md" \
  "mkdir skills/empty-skill"
expect_failure "undocumented agent" "not listed in README.md" \
  "sed 's/^name: pr-reviewer/name: new-agent/' agents/pr-reviewer.md > agents/new-agent.md && printf '%s\n' '\`new-agent\`' >> templates/CLAUDE.md"
expect_failure "invalid settings JSON" "settings.example.json is not valid JSON" \
  "echo '{' > settings.example.json"
expect_failure "missing core deny rule" "misses deny rules: Read(**/.env)" \
  "edit settings.example.json -e '/\"Read(\\*\\*\\/.env)\"/d'"
expect_failure "missing secrets-folder rule" "misses deny rules: Read(**/secrets/**/*.yaml)" \
  "edit settings.example.json -e '/secrets.*yaml/d'"
expect_failure "missing .env variant" "misses deny rules: Read(**/.env.test)" \
  "edit settings.example.json -e '/\\.env\\.test)/d'"
expect_failure "settings file missing" "settings.example.json is missing" \
  "rm settings.example.json"
expect_failure "settings not an object" "misses deny rules" \
  "echo '[]' > settings.example.json"
expect_failure ".env template wildcard" "denies .env templates" \
  "edit settings.example.json -e 's|\"Read(\\*\\*/.env.local)\"|\"Read(**/.env.*)\"|'"

echo "accepts"
copy="$TMP/full_model_id"
mkdir -p "$copy"
cp -R "$REPO/agents" "$REPO/skills" "$REPO/templates" "$REPO/README.md" "$REPO/settings.example.json" "$copy/"
edit "$copy/agents/pr-reviewer.md" -e 's/^model: opus/model: claude-opus-5-5/'
if "$REPO/tests/validate.sh" "$copy" >/dev/null; then echo "  pass  full model ID"; else echo "  FAIL  full model ID rejected"; fail=1; fi

[[ $fail -eq 0 ]] && echo "test_validate: all passed"
exit $fail
