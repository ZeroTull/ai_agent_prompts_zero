## Platforms

Detect the platform from the link or ID in the request; if there is none, from `git remote get-url origin`. Use that platform's tool: it handles login, so never ask for, read or pass tokens. If the tool is missing or not logged in, say which one to set up and stop. MCP tool names differ between servers, so pick the tool that does the step (for example "get issue" or "search with JQL"). Use the command forms below; they print and exit, while interactive views (such as `glab ci view`) hang an agent.

| Step | Azure DevOps | GitHub | GitLab | Jira |
|---|---|---|---|---|
| Recognize | `dev.azure.com`, `AB#123` | `github.com`, `#123` | a `gitlab` host, `!123` | `/browse/KEY-123`, `KEY-123` |
| Tool | Azure DevOps MCP, or `az` with the `azure-devops` extension | `gh` | `glab` | Cloud (`*.atlassian.net`): Atlassian MCP. Data Center: `jira` CLI |
| Read a PR/MR | `az repos pr show --id N` | `gh pr view N`, `gh pr diff N` | `glab mr view N`, `glab mr diff N --raw` | - |
| Read a pipeline run | `az pipelines runs show --id N` | `gh run view N --log-failed` | `glab ci get -p N -d` | - |
| Read a job log | in the MCP run details | `gh run view N --log-failed` | `glab ci trace <job-id> -p N` | - |
| Run history | `az pipelines runs list` | `gh run list -w <workflow>` | `glab ci list -r <branch>` | - |
| Read an item | `az boards work-item show --id N` | `gh issue view N` | `glab issue view N` | MCP get issue; `jira issue view KEY --plain` |
| Search items | `az boards query --wiql "..."` | `gh issue list --search "..."` | `glab issue list --search "..."` | MCP JQL search; `jira issue list -q "<JQL>" --plain` |
| Create a bug (after approval) | `az boards work-item create --type Bug` | `gh issue create --label bug` | `glab issue create --label bug` | MCP create issue (type Bug); `jira issue create -tBug --no-input` |
| Test cases | ADO Test Plans via the MCP | - | - | Zephyr Scale MCP if configured; otherwise a Zephyr Scale CSV import file |
