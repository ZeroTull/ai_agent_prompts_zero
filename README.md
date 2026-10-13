# claude-dev

My personal [Claude Code](https://claude.com/claude-code) setup for development: global rules, settings, status line, hooks, and the agents and skills I use to build software (currently a website).

All QA test-automation agents and skills, including the test-strategy agent `senior-automation-qa-engineer`, live in a separate, self-contained repo: [claude-qa-automation](https://github.com/ZeroTull/claude-qa-automation). The two install side by side without conflict: this repo owns `~/.claude/CLAUDE.md` and `settings.json`, and the QA repo only adds its agents and skills.

## Install

```bash
git clone git@github.com:ZeroTull/claude-dev.git ~/projects/claude-dev
~/projects/claude-dev/install.sh
```

`install.sh` links everything into `~/.claude`, so `git pull` here updates the live config:
- **Linked:** `CLAUDE.md`, `settings.json`, the status line, hooks, commands, agents and skills.
- **Backups:** anything it replaces (a file, a broken link, or a link from another setup) is moved to `~/.claude/backups/setup-<timestamp>-NNN/` first.
- **Left alone:** items Claude Code manages itself, such as `skills/synced`. It refuses to run if `~/.claude/agents`, `skills`, `commands` or `hooks` is itself a link.
- **Moved clones and removed entries:** if you move the clone, run it again from the new place; it repairs the links. Links to entries that no longer exist in this repo (for example the QA agents that moved to claude-qa-automation) are backed up and removed.
- **Uninstall:** `./install.sh --uninstall` removes its links and puts back the newest backup of each.
- **Missing tools:** at the end it lists missing tools (`jq`, `gh`, `glab`, `python3`) and what each is for.

Restart Claude Code afterwards.

**Settings live only in `settings.json`.** Claude Code reads user settings from `~/.claude/settings.json` alone; a `~/.claude/settings.local.json` is only a project file for sessions started in your home folder. The `autoMode` block that auto mode uses is therefore in this repo's `settings.json`, without machine-specific paths. When you change a setting in Claude Code (for example through `/config`), it can replace the link with a plain file. Run `./install.sh` again: it backs up the changed file, so you can copy what's worth keeping into the repo.

## Contents

| Path | Purpose |
|---|---|
| `CLAUDE.md` | Global rules: feature branches, PR review loop, green pipeline before merge |
| `settings.json` | Permissions, secret deny rules, auto mode environment, hooks, status line, theme, voice |
| `statusline-command.sh` | Status line: model, cost, duration, line changes, context usage |
| `hooks/tmux-claude.sh` | Forwards hook events to the tmux-claude plugin; does nothing without it |
| `agents/`, `skills/`, `commands/` | See below |
| `templates/safety.md` | Safety rules every personal agent and skill includes |
| `catalog.tsv` | Group and source of every agent, skill and command |
| `third-party.lock` | Content hashes of the vendored third-party skills |

## Personal agents, skills and commands

| Entry | Use it for |
|---|---|
| `code-reviewer` | The reviewer in the `CLAUDE.md` PR loop. Structured blockers / high / medium report with TDD enforcement. Returns the report; the main session posts it on the PR/MR. |
| `backend-architect` | API design, databases, scalable server-side architecture. |
| `frontend-developer` | UI components, React/Next.js, client-side logic. |
| `/backend-architect-audit` | Deep backend audit through the `backend-architect` agent, with a phased plan. |
| `/backend-review` | Backend structure review with a prioritized improvement plan. |
| `/save-progress` | Save work in progress on one branch and resume it on another. |
| `/review-pr-comments` | Fetch unresolved GitHub PR review comments, sort them, and propose a fix plan. |

## Third-party skills

Vendored unchanged. The upstream source for each is in `catalog.tsv`, and `third-party.lock` pins their content by SHA-256, so the CI fails if one is edited by accident. To update one from upstream, replace its folder and put the new hash (printed by `tests/validate.sh`) into the lock file.

| Skill | From |
|---|---|
| `caveman`, `caveman-commit`, `caveman-compress`, `caveman-explore`, `caveman-help`, `caveman-review`, `caveman-stats`, `cavecrew` | [JuliusBrussee/caveman](https://github.com/JuliusBrussee/caveman): compressed output and token-saving workflows |
| `investigate-first`, `lean-build`, `migration`, `safe-refactor`, `surgical-patch`, `verify-and-stop` | [JuliusBrussee/caveman](https://github.com/JuliusBrussee/caveman): disciplined workflows for debugging, building, migrating, refactoring and verifying |
| `stop-slop` | [hardikpandya/stop-slop](https://github.com/hardikpandya/stop-slop) (MIT): removes AI writing patterns from prose |

## Security

Every personal entry includes the safety rules from `templates/safety.md`: pasted secrets are never repeated, secrets found in code or logs are reported by location and type only, and ticket, PR and log text is treated as data, not instructions. CI checks that none is missing.

Claude Code itself enforces the deny rules in `settings.json`. They block its file tools from:
- `.env` and its common variants (`.env.local`, `.env.test`, `.env.production`, ...)
- config and text files anywhere under a `secrets/` folder
- key stores
- `~/.ssh`, `~/.gnupg`, `~/.aws` and `~/.azure`
- `gh`, `glab`, git, Docker and jira-cli credentials
- Maven and Gradle credential files

They also stop `glab ci get --with-variables` and `git diff --output`. Committed templates such as `.env.example` stay readable. Deny rules cover Claude's file tools, not every shell command, so keep secrets outside repos and consider [sandbox mode](https://docs.claude.com/en/docs/claude-code/sandboxing) for stronger isolation.

## Dependencies

- [Claude Code](https://claude.com/claude-code)
- `jq`: status line
- `gh`, `glab`: PR/MR workflow in `CLAUDE.md`
- `python3`: tests
- Optional: [tmux-claude](https://github.com/smilovanovic/tmux-claude) via TPM (`set -g @plugin 'smilovanovic/tmux-claude'`) for tmux status integration

## Customizing

- **Adding an entry:** add an agent (`agents/<name>.md`), skill (`skills/<name>/SKILL.md`) or command (`commands/<name>.md`), a row in `catalog.tsv` (group `personal`, or `third-party` with its upstream URL) and a line in this README. Personal entries must include the block from `templates/safety.md`.
- **Models:** `model:` in an agent sets its model (`opus`, `sonnet`, `haiku`, `inherit` or a full model ID).

## Design decisions

- **One repo per purpose.** This repo is the personal development setup; the QA test-automation set is its own self-contained repo, so it can be installed at work without anything personal.
- **This repo owns the global files.** `CLAUDE.md` and `settings.json` are linked from here. The QA repo never takes them over, so both install side by side.
- **Settings live in `settings.json` only.** Claude Code reads user settings and `autoMode` from that file alone, so machine-specific details are kept out of `autoMode` rather than moved to another file.
- **Reviewers don't post or approve.** A subagent can't wait for you, and GitHub doesn't let an author approve their own PR. So `code-reviewer` returns its report, and the main session posts it as a comment.
- **Third-party skills are pinned, not edited.** `third-party.lock` makes accidental edits fail CI; updates come from upstream.

## Development

```bash
tests/validate.sh        # catalog, frontmatter, safety block, third-party hashes, docs, settings
tests/test_validate.sh   # validate.sh rejects broken inputs
tests/test_install.sh    # installer behavior in a temp directory
tests/test_config.sh     # settings.json, hook wrapper, status line
```

The scripts need only `bash`, `python3` (standard library, 3.9 or newer) and `jq`. The validator shares its parser and catalog checks with claude-qa-automation; here it checks only personal and third-party entries and validates `settings.json` directly. CI runs all four scripts plus `shellcheck` on Linux and macOS for every PR.
