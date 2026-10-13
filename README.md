# AI Agent Prompts

Prompts for setting up a local AI agent workflow for QA automation and Java PR reviews. They're built for **Claude Code**, in the terminal or inside IntelliJ IDEA, and should also work with other agentic coding tools.

## Two kinds of prompts

Not every file here is something you paste into a chat. There are two kinds:

| Kind | What it does | How often you use it |
|---|---|---|
| **Generator prompt** | Tells the AI to create files and folders in your repo: agent definitions, templates, scripts, configs. | **Once** per repo. After that you use the files it generated. |
| **Agent instructions** | Defines how an agent behaves every time it runs. | **Save it as a file** once. The tool loads it automatically, so you don't paste it every time. |

## Files

| File | Kind | Purpose |
|---|---|---|
| [`ecosystem_prompt`](ecosystem_prompt) | Generator | Builds the full `.agents/` layout (`configs/` plus `skills/<name>/` with `SKILL.md`, `README.md`, `references/`, `scripts/`, `templates/`) for 13 skills: pr-review-agent, test-developer, test-maintainer, api-test-developer, api-test-maintainer, scale-test-developer, code-reviewer, bug-reporter, test-data-manager, merge-request-creator, k8s-observer, orchestrator, shared. |
| [`test_developer_agent_prompt`](test_developer_agent_prompt) | Generator | Builds a Test Developer agent that reads Acceptance Criteria and Scenarios from text files, Excel, or Confluence and writes the missing automated tests. |
| [`test_maintainer_agent_prompt`](test_maintainer_agent_prompt) | Generator | Builds a Test Maintainer agent that finds flaky, duplicated, or slow tests, weak assertions, and dead code, then proposes fixes. |
| [`pr_review_agent_prompt`](pr_review_agent_prompt) | Agent instructions | A Java PR review agent for **Azure DevOps** (via MCP). It reviews only what the PR changes, reports findings, and asks which ones to fix before changing anything. |

## Quick start

### Prerequisites

- [Claude Code](https://claude.com/claude-code) installed (CLI or the IntelliJ plugin)
- A git repo to set the agents up in, usually your test automation or service repo
- For the PR review agent: an **Azure DevOps MCP server** configured in Claude Code
- For Confluence input: an **Atlassian MCP server**, or Confluence pages exported to text

### Option A: full skill setup (recommended)

1. Open your work repo in a terminal and start a branch:
   ```bash
   git checkout -b chore/ai-agents
   claude
   ```
2. Paste the whole contents of `ecosystem_prompt` and send it.
3. Paste the contents of `pr_review_agent_prompt` with a line like:
   > Use this as the full instructions for `.agents/skills/pr-review-agent/SKILL.md`.
4. *(Optional)* Do the same with `test_developer_agent_prompt` and `test_maintainer_agent_prompt` as detailed specs for the `test-developer` and `test-maintainer` skills.
5. Review what it generated, fill in the placeholders in `.agents/configs/` (**never commit real tokens**; add them to `.gitignore`), then commit.

### Option B: one agent only

**PR reviewer:** save the prompt as a Claude Code subagent:

```bash
mkdir -p .claude/agents
{
  printf -- '---\nname: pr-reviewer\ndescription: Reviews Azure DevOps Java PRs. Use when given a PR URL.\n---\n\n'
  cat pr_review_agent_prompt
} > .claude/agents/pr-reviewer.md
```

**Test developer / maintainer:** paste the prompt into Claude Code in your test repo once and let it generate the project files.

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

- **Adjust to your stack.** The prompts assume Java and Azure DevOps. If you use GitHub or GitLab, edit the platform references before generating.
- **Treat generated files as a starting point.** Fill the `references/` folders with your real coding standards and architecture notes. That's what makes the agents useful.
- **Keep secrets out of git.** Config files are generated with placeholders only.
- **Commit the generated `.agents/` / `.claude/` folders** so your whole team gets the same agents.
