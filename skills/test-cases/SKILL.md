---
name: test-cases
description: Drafts manual/test-plan test cases (title, preconditions, steps, expected result, priority, type) from an ADO work item or requirements doc, de-duplicates against existing cases, shows a coverage map, and pushes only approved cases to ADO Test Plans. Use for "write test cases for story 1234", "generate test cases from <doc>". For automated test code, use the test-developer agent instead.
---

# Test Case Generation

Produces test case definitions for ADO Test Plans. These are QA planning artifacts, not code (that is the `test-developer` agent).

## Steps

1. **Read conventions.** `.ai/context/conventions.md` for test case naming, required fields and type tags. If it does not exist, suggest running `/qa-conventions` first, or continue with the defaults and flag them.

2. **Retrieve.** Get the work item (title, description, acceptance criteria, linked docs and bugs) with the Azure DevOps MCP tools, or `az boards work-item show --id <ID>`. Also get test cases already linked to it or its parent feature. For a file or Confluence page, read it (Atlassian MCP for Confluence).

3. **Generate.** For each testable condition:
   - Title (convention format), preconditions, numbered steps (one action each), specific expected result, priority (inherit from the work item unless there is a reason), type tag (functional / negative / boundary / regression / accessibility / performance).
   - Cover: the happy path, every acceptance criterion, implied negative and boundary cases (empty, invalid, limits, roles/permissions), and any stated non-functional requirement.
   - Do not invent requirements. If a case needs an assumption, list it as a question.

4. **De-duplicate.** Compare with existing cases; skip or merge duplicates. Flag acceptance criteria that cannot be tested as written.

5. **Present:**
   ```
   ## Proposed Test Cases     (table or numbered list)
   ## Coverage Map            AC -> case(s); uncovered ACs with reason
   ## Questions / Assumptions
   ```

6. **Push only after approval.** Create only the approved cases in the test plan/suite the user names (ADO MCP tools), then return the created IDs and links. Never push without approval.
