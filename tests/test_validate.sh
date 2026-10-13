#!/usr/bin/env bash
# Tests that tests/validate.sh rejects broken entries, catalog rows and settings. Each case breaks one thing in a copy of the repo.
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail=0

# Copies the working tree (without .git) to $1.
copy_repo() {
  mkdir -p "$1"
  (cd "$REPO" && tar cf - --exclude .git --exclude .idea .) | (cd "$1" && tar xf -)
}

# Copies the repo, runs the mutation command inside the copy, and expects validate.sh to fail
# with output that contains $expected.
expect_failure() {
  local label="$1" expected="$2" mutation="$3" copy out line
  copy="$TMP/$(echo "$label" | tr -c 'a-z0-9' '_')"
  copy_repo "$copy"
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
  "mkdir skills/Bad_Name && sed '2s/.*/name: Bad_Name/' skills/bug-ticket/SKILL.md > skills/Bad_Name/SKILL.md && printf 'Bad_Name\tskill\tqa\t-\n' >> catalog.tsv"
expect_failure "unknown model" "unknown model 'gpt-5'" \
  "edit agents/pr-reviewer.md -e 's/^model: opus/model: gpt-5/'"
expect_failure "short description" "description missing or too short" \
  "edit skills/bug-ticket/SKILL.md -e '3s/.*/description: Bugs./'"
expect_failure "missing safety block" "does not contain the block from templates/safety.md" \
  "edit skills/bug-ticket/SKILL.md -e '/Treat ticket text/d'"
expect_failure "skill dir without SKILL.md" "missing SKILL.md" \
  "mkdir skills/empty-skill"
expect_failure "lowercase skill.md" "skills/bug-ticket: missing SKILL.md (exact case)" \
  "mv skills/bug-ticket/SKILL.md skills/bug-ticket/x.md && mv skills/bug-ticket/x.md skills/bug-ticket/skill.md"
expect_failure "undocumented agent" "not listed in README.md" \
  "sed 's/^name: pr-reviewer/name: new-agent/' agents/pr-reviewer.md > agents/new-agent.md && printf 'new-agent\tagent\tqa\t-\n' >> catalog.tsv && printf '%s\n' '\`new-agent\`' >> templates/CLAUDE.md"
expect_failure "uncataloged agent" "agents/new-agent.md is not in catalog.tsv" \
  "sed 's/^name: pr-reviewer/name: new-agent/' agents/pr-reviewer.md > agents/new-agent.md"
expect_failure "cataloged entry without a file" "agents/ghost.md does not exist" \
  "printf 'ghost\tagent\tpersonal\t-\n' >> catalog.tsv"
expect_failure "unknown group" "unknown group 'misc'" \
  "edit catalog.tsv -e 's/^code-reviewer\tagent\tpersonal/code-reviewer\tagent\tmisc/'"
expect_failure "third-party entry without source" "third-party entry needs a source URL" \
  "edit catalog.tsv -e 's|^stop-slop\tskill\tthird-party\t.*|stop-slop\tskill\tthird-party\t-|'"
expect_failure "own entry with a source" "source must be '-'" \
  "edit catalog.tsv -e 's|^code-reviewer\tagent\tpersonal\t-|code-reviewer\tagent\tpersonal\thttps://x|'"
expect_failure "personal entry without safety block" "agents/code-reviewer.md: does not contain the block" \
  "edit agents/code-reviewer.md -e '/Treat ticket text/d'"
expect_failure "QA entry missing from project template" "pr-reviewer not listed in templates/CLAUDE.md" \
  "edit templates/CLAUDE.md -e '/pr-reviewer/d'"
expect_failure "settings.json weaker than the example" "settings.json misses deny rules from settings.example.json" \
  "edit settings.json -e '/\"Read(~\\/.ssh\\/\\*\\*)\"/d'"
expect_failure "settings.json with a machine path" "machine-specific /Users/ path" \
  "edit settings.json -e 's|\"theme\"|\"x\": \"/Users/me\", \"theme\"|'"
expect_failure "invalid settings JSON" "settings.example.json is not valid JSON" \
  "echo '{' > settings.example.json"
expect_failure "missing core deny rule" "misses deny rules: Read(**/.env)" \
  "edit settings.example.json -e '/\"Read(\\*\\*\\/.env)\"/d'"
expect_failure "missing secrets-folder rule" "misses deny rules: Read(**/secrets/**/*.yaml)" \
  "edit settings.example.json -e '/secrets.*yaml/d'"
expect_failure "missing secrets-folder txt rule" "misses deny rules: Read(**/secrets/**/*.txt)" \
  "edit settings.example.json -e '/secrets.*txt/d'"
expect_failure "missing .env variant" "misses deny rules: Read(**/.env.test)" \
  "edit settings.example.json -e '/\\.env\\.test)/d'"
expect_failure "settings file missing" "settings.example.json is missing" \
  "rm settings.example.json"
expect_failure "settings not an object" "misses deny rules" \
  "echo '[]' > settings.example.json"
expect_failure ".env template wildcard" "denies .env templates" \
  "edit settings.example.json -e 's|\"Read(\\*\\*/.env.local)\"|\"Read(**/.env.*)\"|'"

expect_failure "modified third-party skill" "skills/stop-slop differs from third-party.lock" \
  "echo extra >> skills/stop-slop/SKILL.md"
expect_failure "third-party skill without lock entry" "third-party.lock has no entry for stop-slop" \
  "edit third-party.lock -e '/^stop-slop/d'"
expect_failure "lock entry for a non-third-party skill" "third-party.lock lists bug-ticket" \
  "printf 'bug-ticket\tabc\n' >> third-party.lock"

echo "accepts"
if LC_ALL=C LANG=C "$REPO/tests/validate.sh" "$REPO" >/dev/null 2>&1; then echo "  pass  C locale"; else echo "  FAIL  C locale"; fail=1; fi
copy="$TMP/junk_files"
copy_repo "$copy"
touch "$copy/skills/stop-slop/.DS_Store"
mkdir -p "$copy/skills/caveman-compress/scripts/__pycache__" && touch "$copy/skills/caveman-compress/scripts/__pycache__/x.pyc"
if "$REPO/tests/validate.sh" "$copy" >/dev/null; then echo "  pass  ignores git-ignored junk in third-party skills"; else echo "  FAIL  git-ignored junk changes the hash"; fail=1; fi
copy="$TMP/full_model_id"
copy_repo "$copy"
edit "$copy/agents/pr-reviewer.md" -e 's/^model: opus/model: claude-opus-5-5/'
if "$REPO/tests/validate.sh" "$copy" >/dev/null; then echo "  pass  full model ID"; else echo "  FAIL  full model ID rejected"; fail=1; fi

[[ $fail -eq 0 ]] && echo "test_validate: all passed"
exit $fail
