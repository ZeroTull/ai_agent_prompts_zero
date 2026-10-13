---
name: bug-ticket
description: Drafts an ADO bug from a failing test, log, stack trace or CI run - checks for duplicates, writes repro steps, expected vs actual, severity with reasoning, links the test case and build - and files it only after approval. Use for "file a bug for this failure", "create a bug from <run/log>", "write up this defect".
---

# Bug Ticket

Turns a confirmed failure into a properly-fielded ADO bug. The bug is filed only after the user confirms the draft.

## Steps

1. **Read conventions.** `.ai/context/conventions.md` for title format, repro structure, severity/priority taxonomy and area paths. If missing, use a conservative default and flag it.

2. **Gather.** Failing test name, log/stack trace, CI run link, linked test case and work item (Azure DevOps MCP tools or `az boards`). If the failure looks intermittent, suggest the `flaky-test-triager` agent first; a flaky test is not a product bug.

3. **Duplicate check.** Search open bugs by error signature, test name and component (ADO MCP search or `az boards query --wiql`). Report what you found.

4. **Analyze.** What failed and why, based only on the evidence. Regression (passed before, with the last green run) or new. Affected component and area path. Severity by user impact; if unsure, choose the conservative level and mark it "needs triage".

5. **Draft:**
   ```
   Title:        <component>: <failure condition>   (not "test X failed")
   Repro steps:  1. ... (from the test/log, with environment and build)
   Expected:     ...
   Actual:       ...
   Severity / Priority: ... - reason
   Area path:    ...
   Links:        test case, CI run/build, related work item
   Evidence:     short log/stack excerpt
   Possible duplicates: none / <links>
   ```
   Before you show it, remove anything credential-shaped and any sensitive data defined in the conventions (tokens, connection strings, PII, customer data) from the steps and excerpts.

6. **File only after approval.** Create the bug (ADO MCP tools or `az boards work-item create --type Bug`), and return the ID and link.
