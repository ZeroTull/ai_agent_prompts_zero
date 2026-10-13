# AI Agent Prompts

Prompts for setting up a local AI agent workflow for QA automation and Java PR reviews. They're built for **Claude Code**, in the terminal or inside IntelliJ IDEA.

## Two kinds of prompts

Not every file here is something you paste into a chat. There are two kinds:

| Kind | What it does | How often you use it |
|---|---|---|
| **Generator prompt** | Tells the AI to create files and folders in your repo: agent definitions, templates, scripts, configs. | **Once** per repo. After that you use the files it generated. |
| **Agent instructions** | Defines how an agent behaves every time it runs. | **Save it as a file** once, in a place Claude Code loads (see below). You don't paste it every time. |

## Files

| File | Kind | Purpose |
|---|---|---|
| [`ecosystem_prompt`](ecosystem_prompt) | Generator | Builds the full `.agents/` layout (`configs/` plus `skills/<name>/` with `SKILL.md`, `README.md`, `references/`, `scripts/`, `templates/`) for 13 skills: pr-review-agent, test-developer, test-maintainer, api-test-developer, api-test-maintainer, scale-test-developer, code-reviewer, bug-reporter, test-data-manager, merge-request-creator, k8s-observer, orchestrator, shared. |
| [`test_developer_agent_prompt`](test_developer_agent_prompt) | Generator | Builds a Test Developer agent project. The agent reads Acceptance Criteria and Scenarios from text files, Excel, or Confluence and, after you approve its plan, writes the missing automated tests. |
| [`test_maintainer_agent_prompt`](test_maintainer_agent_prompt) | Generator | Builds a Test Maintainer agent project. The agent finds flaky, duplicated, or slow tests, weak assertions, and dead code, then proposes fixes. |
| [`pr_review_agent_prompt`](pr_review_agent_prompt) | Agent instructions | A Java PR review agent for **Azure DevOps** (via MCP). It reviews only what the PR changes, reports findings, and asks which ones to fix before changing anything. |

## Where Claude Code looks for agents

By default, Claude Code loads agents and skills from these locations:

| Location | Scope |
|---|---|
| `<repo>/.claude/agents/<name>.md` | Subagents for this repo |
| `<repo>/.claude/skills/<name>/SKILL.md` | Skills for this repo |
| `~/.claude/agents/`, `~/.claude/skills/` | Your personal ones, for every repo |
| `<repo>/CLAUDE.md` | Project instructions, always loaded |

Agent and skill files need a frontmatter header with `name` and `description`. **Claude Code does not load the `.agents/` folder by itself**, so the steps below connect it.

Run `/agents` inside Claude Code to see which agents it found.

## Quick start

### Prerequisites

- [Claude Code](https://claude.com/claude-code) installed (CLI or the IntelliJ plugin)
- A clone of this repo, e.g. `~/ai_agent_prompts`
- A git repo to set the agents up in, usually your test automation or service repo
- For the PR review agent: an **Azure DevOps MCP server** configured in Claude Code
- For Confluence input: an **Atlassian MCP server**, or Confluence pages exported to text

### Option A: full skill setup

1. Open your work repo in a terminal, start a branch, and launch Claude Code:
   ```bash
   cd ~/path/to/work-repo
   git checkout -b chore/ai-agents
   claude
   ```
2. Paste the whole contents of `ecosystem_prompt`, then add this at the end and send:
   > Every SKILL.md must start with YAML frontmatter containing `name` and `description`. Also add `.claude/skills` as a relative symlink to `../.agents/skills` so Claude Code loads the skills.
3. Replace the generated PR review skill with the full agent instructions. Paste the contents of `pr_review_agent_prompt` with:
   > Replace the body of `.agents/skills/pr-review-agent/SKILL.md` with these instructions. Keep the frontmatter.
4. *(Optional)* Do the same with `test_developer_agent_prompt` and `test_maintainer_agent_prompt`, as detailed specs for the `test-developer` and `test-maintainer` skills.
5. Restart Claude Code and check that the skills show up (type `/` to see them in the command list).

> **Windows:** git symlinks don't work in every Windows checkout. If the skills don't show up, ask Claude to copy `.agents/skills` into `.claude/skills` instead.

### Option B: PR reviewer only (simplest)

Save the prompt as a Claude Code subagent. Run this **from your work repo**, with `PROMPTS` set to where you cloned this repo:

```bash
PROMPTS=~/ai_agent_prompts
mkdir -p .claude/agents
{
  printf -- '---\nname: pr-reviewer\ndescription: Reviews Azure DevOps Java PRs. Use when given a PR URL.\n---\n\n'
  cat "$PROMPTS/pr_review_agent_prompt"
} > .claude/agents/pr-reviewer.md.tmp && mv .claude/agents/pr-reviewer.md.tmp .claude/agents/pr-reviewer.md
```

For a personal agent that works in every repo, use `~/.claude/agents/` instead of `.claude/agents/`.

**Test developer / maintainer:** paste the prompt into Claude Code in your test repo once and let it generate the project files.

## Secrets and configs

Generated config files (`.agents/configs/*.json`) contain placeholders only. Before you put real tokens in them:

1. Add the files to `.gitignore`: `.agents/configs/*.json`. This covers `ado-config.json` and `mcp-config.json` too, since they can hold access tokens. Keep committed examples in `.agents/configs/templates/`.
2. Fill in your real values.
3. Run `git status` and make sure the token files aren't listed. If they were committed earlier, run `git rm --cached <file>`.

## Day-to-day usage

After setup you **don't paste the long prompts again**. Give short commands instead:

```text
Review this PR: https://dev.azure.com/<org>/<project>/_git/<repo>/pullrequest/123
Review this PR, only performance: <url>
Generate tests from this Confluence page: <link>
Generate missing tests from ./requirements/login.xlsx
Analyze the UI test suite for flaky tests and propose fixes
```

The agents are designed to **propose first and wait for your approval** before editing code or running tests. Read the plan before you say yes.

## Tips

- **Adjust to your stack.** The PR reviewer assumes Java and Azure DevOps. The ecosystem configs include GitLab and Atlassian tokens. Edit platform references before generating if yours differ.
- **Treat generated files as a starting point.** Fill the `references/` folders with your real coding standards and architecture notes. That's what makes the agents useful.
- **Commit the generated `.agents/` and `.claude/` folders** (not the tokens) so your whole team gets the same agents.
