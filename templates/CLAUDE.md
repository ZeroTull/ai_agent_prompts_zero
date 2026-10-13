# CLAUDE.md

## Project context

Read `.ai/context/conventions.md` before drafting tickets, test cases, PR text or tests. Other files in `.ai/context/` (testing rules, framework patterns, known flaky tests) hold project knowledge; read the ones relevant to the task. If `.ai/context/` does not exist, suggest running `/qa-conventions`.

## QA agents and skills

| Task | Use |
|---|---|
| Write automated tests from requirements | `test-developer` agent |
| Review a pull request | `pr-reviewer` agent |
| Audit / clean up the test framework | `test-maintainer` agent |
| Pipeline failed | `ci-failure-diagnoser` agent |
| Test fails intermittently | `flaky-test-triager` agent |
| Test cases for ADO Test Plans | `/test-cases` |
| File a bug from a failure | `/bug-ticket` |
| Check a ticket is ready for dev | `/ticket-review` |
| Draft a PR description | `/pr-description` |
| Set up or update conventions | `/qa-conventions` |
| Monthly accuracy check of the agents | `/agent-calibration` |

## Working rules

- Analyze, propose a plan, and wait for approval before writing files, running tests or changing anything in Azure DevOps.
- Never read credentials, tokens, `.env` files or secret-bearing configs. Use MCP tools or CLIs that handle auth themselves (`az login`, `gh auth`).
- Never copy sensitive data (as defined in `conventions.md`) into tickets, PRs, comments or logs.
- Run only impacted tests. On failure, stop and report; do not loop.
