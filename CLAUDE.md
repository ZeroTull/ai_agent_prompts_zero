# Global Rules

## PR / MR Workflow (mandatory, no exceptions)

Every code change must follow these steps in order:

1. **Feature branch** — never commit directly to main.
2. **Commit & push** to the feature branch.
3. **Open a PR/MR** (`glab mr create` or `gh pr create`).
4. **Review loop — up to 20 cycles:**
   - Run the code-reviewer agent on the diff.
   - Post all findings as comments on the MR.
   - Fix every comment, push the fixes.
   - Re-run the code-reviewer agent.
   - Repeat until the reviewer returns APPROVED with no blocking comments.
5. **Wait for a green pipeline** — poll CI until status is `success`.
   - If the pipeline fails, fix the cause, push, and go back to step 4.
6. **Merge** — only after BOTH review approval AND green pipeline.

**Never merge if any review comment is unresolved or the pipeline is not green.**

## General Rules

- Always use feature branches — never push directly to main.
- No PR without test coverage for new functionality.
- `glab ci *`, `glab mr *`, `glab api *` commands are pre-approved and do not need user confirmation.
