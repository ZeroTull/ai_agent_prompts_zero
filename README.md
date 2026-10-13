# QA Agents for Claude Code

Ready-to-use [Claude Code](https://claude.com/claude-code) agents and skills for QA automation on Java projects with Azure DevOps: writing tests from requirements, reviewing PRs, diagnosing CI failures, triaging flaky tests, and drafting test cases, bugs and PR descriptions.

There is nothing to generate. Install once and the agents are available in every repo. Each agent reads the project it runs in (build tool, test framework, conventions) and adapts on the spot.

## What's inside

**Agents** run in their own context. Claude picks one automatically from your request, or you name it ("use the pr-reviewer agent").

| Agent | Use it for |
|---|---|
| `test-developer` | Write missing automated tests from a text file, Excel, Confluence page or ADO work item. Checks existing coverage first. |
| `pr-reviewer` | Review a Java PR (ADO or GitHub): correctness, conventions, performance, security, concurrency, tests. Findings with severity and confidence. |
| `test-maintainer` | Audit a test framework for flakiness, duplication, weak assertions, dead code and slow setup. Gives a health report and an improvement plan. |
| `ci-failure-diagnoser` | Find the root cause of a failed pipeline run, with log evidence. Read-only. |
| `flaky-test-triager` | Decide whether an intermittent failure is flaky or a real regression, based on run history. Read-only. |

**Skills** are workflows you run with a slash command in your conversation.

| Skill | Use it for |
|---|---|
| `/qa-conventions` | **Run first in each repo.** Builds `.ai/context/conventions.md` (ADO fields, severity scale, PR template, test naming, sensitive-data rules) from what the team already has. |
| `/test-cases` | Test cases for ADO Test Plans from a work item, with a coverage map. Pushes only approved cases. |
| `/bug-ticket` | Draft an ADO bug from a failing test or log, with a duplicate check. Files only after approval. |
| `/ticket-review` | Check whether a story or bug is ready for development (clear AC, testable, scoped). |
| `/pr-description` | Draft a PR title and description from your diff, linked to the ADO work item. |
| `/agent-calibration` | Monthly check: where humans corrected the agents, and what to change. |

Every agent and skill follows the same rules. It analyzes and proposes first, then waits for your approval before writing files, running tests or changing anything in ADO. It never reads credentials.

## Install

Requirements: Claude Code, `git`, `bash`. Optional: `python3` with `openpyxl` (Excel input), the `az` CLI with the `azure-devops` extension or an Azure DevOps MCP server, and an Atlassian MCP server (Confluence input).

```bash
git clone https://github.com/ZeroTull/ai_agent_prompts_zero.git ~/qa-agents
cd ~/qa-agents
```

**For yourself (all repos):**

```bash
./install.sh
```

This symlinks the agents into `~/.claude/agents/` and the skills into `~/.claude/skills/`. Run `git pull` to get updates. It never overwrites files you already have, and `./install.sh --uninstall` removes only its own links.

**For your team (one repo):**

```bash
./install.sh --project ~/path/to/work-repo
```

This copies the agents and skills into `<repo>/.claude/` and adds `.claude/settings.json` and a `CLAUDE.md` if they don't exist yet. Commit the result and everyone on the team gets the same agents.

Then, in the work repo:

```text
claude
> /qa-conventions
```

Check that the agents loaded with `/agents`. Type `/` to see the skills.

## Connect Azure DevOps and Confluence safely

The agents never handle tokens. Authentication stays in tools that manage it themselves:

- **Azure DevOps:** `az login` plus `az extension add --name azure-devops` and `az devops configure --defaults organization=https://dev.azure.com/<org> project=<project>`, or the [Azure DevOps MCP server](https://github.com/microsoft/azure-devops-mcp) (`claude mcp add ...`, see its README).
- **Confluence:** the Atlassian MCP server. Without it, export the page to a file and pass the file.

`settings.example.json` holds deny rules that stop Claude Code from reading `.env` files, `*-token.json` files, `~/.ssh`, `~/.aws`, `~/.azure` and Maven/Gradle credential files. The user install doesn't change your settings; merge this file into `~/.claude/settings.json` yourself. Deny rules cover Claude's file tools. A shell command could still read a file, so keep secrets outside the repo, and consider [sandbox mode](https://docs.claude.com/en/docs/claude-code/sandboxing) for stronger isolation.

## Day-to-day examples

```text
Create tests from ./requirements/login.xlsx
Generate missing API tests for story 48213
Review this PR: https://dev.azure.com/<org>/<project>/_git/<repo>/pullrequest/123
Why did build 9876 fail?
Is LoginTest#expiredPassword flaky?
Audit the checkout module tests
/test-cases 48213
/bug-ticket   (after a failure in the conversation)
/pr-description
```

## Project knowledge: `.ai/context/`

Agents get better when the repo explains itself. `/qa-conventions` creates these files in your work repo, and the agents read them and suggest additions:

| File | Holds |
|---|---|
| `conventions.md` | ADO fields, severity scale, PR template, naming, sensitive-data rules |
| `testing-rules.md`, `framework-patterns.md`, `reusable-components.md` | How tests are written here and what to reuse |
| `known-flaky-tests.md`, `known-issues.md` | Known problems, so agents don't rediscover them |

Commit `.ai/context/` with the project.

## Customizing

- Each agent is one Markdown file in `agents/`. Each skill is a folder with `SKILL.md` in `skills/`. Edit them, open a PR, and the CI checks they still load.
- `model:` in an agent sets its model (`opus`, `sonnet`, `haiku` or `inherit`). `pr-reviewer` uses `opus` because review needs judgment. The read-only diagnosers use `sonnet`.
- For a stack other than Java or ADO, adjust the commands in the agent files (for example `gh` instead of `az`, `pytest` instead of `mvn`).

## Development

```bash
tests/validate.sh       # frontmatter, names, docs list every agent/skill
tests/test_install.sh   # installer behavior in a temp directory
```

CI runs both, plus `shellcheck`, on every PR.
