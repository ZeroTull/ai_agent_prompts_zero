---
name: pr-description
description: Drafts a pull request title and description (and optional Conventional Commits messages) from the current diff, following the team PR template and linking the ADO work item, with risk and test notes. Draft only - never opens or pushes the PR. Use for "write the PR description", "describe my changes", "draft commit messages".
---

# PR Description

Drafts PR text from the diff. The user reviews, edits and submits it.

## Steps

1. **Diff.** `git diff $(git merge-base HEAD origin/main)...HEAD` (use the real target branch) plus `git log --oneline` for the branch. Use staged changes if the user asks.

2. **Work item.** Find the ADO ID in the branch name or commits (`AB#1234`, `feature/1234-...`). If none, ask for it; do not guess. Read its title and acceptance criteria (Azure DevOps MCP tools or `az boards work-item show`) and check the diff addresses them.

3. **Analyze.** What changed and why, in plain language (not a file-by-file restatement). Risk areas: auth, shared config, data handling, migrations, public API contracts, anything listed in `.ai/context/conventions.md`. Tests added or changed; flag a behavior change with no test change. Breaking changes or required follow-ups (config, docs, migration).

4. **Draft** using the template from `.ai/context/conventions.md` or the repo's PR template. Default:
   ```
   <type>: <summary> (AB#<id>)

   ## Summary         what and why
   ## Work Item       AB#<id>
   ## Risk / Impact
   ## Testing         what was run, what was added
   ## Checklist       only items relevant to this diff
   ```
   If asked for commit messages: Conventional Commits, one per logical change.

5. **Hand back.** Show the draft. Do not create, push or submit the PR unless the user asks for it explicitly. If the diff touches a risk area, recommend the right reviewer.
