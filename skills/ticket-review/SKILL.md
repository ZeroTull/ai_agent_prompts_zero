---
name: ticket-review
description: Reviews an ADO user story, bug or task for readiness before development - clarity, testable acceptance criteria, atomic scope, traceability, Definition of Ready, testability, non-functional requirements, duplicates and risk - and drafts concrete rewrites and questions. Read-only. Use for "review ticket 1234", "is this story ready?", "check the AC on <item>".
---

# Ticket Readiness Review

Assesses a work item before it enters development. Read-only: it does not edit, comment on or move the ticket.

## Steps

1. **Retrieve** the work item with the Azure DevOps MCP tools or `az boards work-item show --id <ID>`: title, description, acceptance criteria, links, tags, priority/severity, area, iteration. Read `.ai/context/conventions.md` for the required fields (Definition of Ready).

2. **Assess** each criterion as Pass / Partial / Fail with a one-line reason:
   - **Clarity:** would two developers read it the same way?
   - **Acceptance criteria:** present and objectively testable. Flag "works correctly", "fast", "user-friendly".
   - **Atomic scope:** one coherent unit, or should it be split?
   - **Traceability:** parent epic/feature, related bugs, test cases, design docs.
   - **Definition of Ready:** required fields filled (priority, area, iteration, estimate).
   - **Testability:** can QA write tests from this alone? List the questions a tester would ask.
   - **Non-functional:** security, performance, accessibility and compliance addressed, or assumed silently.
   - **Duplicates/conflicts:** search open items for overlap.
   - **Risk:** touches auth, PII, configuration or compliance-controlled modules.

3. **Output:**
   ```
   ## Readiness          table: criterion | Pass/Partial/Fail | reason
   ## Suggested Rewrites concrete new wording for each Partial/Fail
   ## Questions for the Author
   ## Verdict            Ready / Needs clarification / Needs split - reason
   ```

Do not treat missing acceptance criteria as present, and do not resolve stakeholder disagreements; surface them. Post questions or edits to ADO only if the user asks for it explicitly.
