---
name: qa-conventions
description: Sets up a project for the QA agents - builds the shared conventions file `.ai/context/conventions.md` (ADO fields, severity taxonomy, PR template, test naming, data-sensitivity rules) from what the team already has, and creates the other `.ai/context/` starter files. Use once per repo, or when conventions change - "set up conventions", "init the QA agents here", "update conventions".
---

# QA Conventions Setup

Creates the single source of truth that all QA agents and skills read: `.ai/context/conventions.md`. It does not invent conventions. It collects existing ones, asks about gaps, and flags assumptions.

## Steps

1. **Check what exists.** Read `.ai/context/` if present, `CLAUDE.md`, `CONTRIBUTING.md`, the PR template (`.azuredevops/pull_request_template.md`, `.github/pull_request_template.md`), linter/formatter configs (`checkstyle.xml`, `.editorconfig`, spotless), and existing test naming in `src/test`. Do not open secret-bearing files.

2. **Collect, then ask about gaps.** Ask the user (one compact list of questions, not one at a time) for anything not found:
   - ADO: required fields per work item type, area path structure, standard tags, severity and priority definitions with an example each.
   - PR: title format, required sections, definition of done.
   - Tests: naming pattern, test type tags, where test data lives.
   - Bugs: title format, repro-step structure.
   - Data sensitivity: what counts as sensitive here (field names and formats of PII, customer data, regulated data). Agents must not copy it into tickets, PRs or logs.
   - Compliance: modules or changes that need extra review.

3. **Surface conflicts.** If two sources disagree (e.g. two severity scales), show both and ask which one wins. Do not merge them silently.

4. **Draft and confirm.** Show the draft of `.ai/context/conventions.md`:
   ```
   # Conventions
   ## Code Style        (pointer to linter config if one exists - do not duplicate it)
   ## ADO Fields        work item types, required fields, area paths, tags
   ## Severity / Priority  definitions + one example each
   ## Pull Requests     title format, sections, definition of done
   ## Test Cases        naming, required fields, type tags
   ## Bug Tickets       title format, repro structure
   ## Sensitive Data    what it looks like here; never include in any artifact
   ## Compliance        modules/changes needing extra review
   ## Assumed (confirm) items defaulted because nothing existed
   ```
   Write it only after the user approves.

5. **Starter files.** Offer to create empty, headed files the agents read and fill over time: `architecture.md`, `testing-rules.md`, `framework-patterns.md`, `reusable-components.md`, `known-flaky-tests.md`, `known-issues.md`. If the repo has no `CLAUDE.md`, offer to add a short one that points to `.ai/context/` and lists the QA agents.

6. **Remind** the user to commit `.ai/context/` so the whole team shares it, and to re-run this skill when the process changes.
