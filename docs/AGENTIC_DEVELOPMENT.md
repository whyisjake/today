# Agentic Development Guide

## Writing Issues That Agents Can Execute

**Version:** 1.0
**Date:** February 2026
**Audience:** Pew Research Center Engineering Team

---

## The Core Idea

AI coding agents can take well-scoped issues 80-90% to completion before human review. The key word is **well-scoped**. A vague issue produces vague code. A precise issue produces precise code.

This guide teaches you how to write issues that agents can actually execute.

---

## The 5 Elements of an Agent-Ready Issue

### 1. Clear Summary (One Sentence)

State what needs to happen in a single sentence. If you can't, the scope is too big.

**❌ Bad:**

> Improve the PDF extraction system

**✅ Good:**

> Add REST API endpoints for retrieving extracted text in plain, markdown, and JSON formats

---

### 2. Context (Why This Matters)

Agents don't have institutional knowledge. Tell them:

- Why this feature exists
- Who uses it
- What problem it solves
- How it fits into the bigger picture

**Example:**

> LLMs and research tools need programmatic access to extracted topline data. Currently, content is only accessible via the WordPress admin. REST endpoints enable integration with external tools like NotebookLM, custom chatbots, and research pipelines.

---

### 3. Acceptance Criteria (Checkboxes)

Define "done" with measurable criteria. Each criterion should be testable.

**❌ Vague:**

- [ ] API works correctly
- [ ] Good error handling

**✅ Specific:**

- [ ] `GET /prc-api/v3/pdf-extraction/text/{id}` returns extracted text
- [ ] Returns 404 with error message when extraction doesn't exist
- [ ] Returns 400 when format parameter is invalid
- [ ] Response includes `X-OCR-Provider` and `X-Extraction-Date` headers
- [ ] All endpoints require no authentication (public data)
- [ ] Unit tests cover success and error cases

---

### 4. Scope Boundaries (In/Out)

Explicitly state what's included and excluded. Agents will try to be helpful — sometimes too helpful. Boundaries prevent scope creep.

**Example:**

```
In scope:
- Three GET endpoints (status, text, list)
- JSON response format
- Basic error handling
- Unit tests

Out of scope:
- Authentication/rate limiting (Phase 2)
- Caching layer (separate issue)
- Admin UI for API keys
- Webhook notifications
```

---

### 5. Technical Notes (The Cheat Sheet)

Give the agent everything it needs to match your codebase patterns:

- **Key files** to read or modify
- **Patterns to follow** (link to similar implementations)
- **Dependencies** and imports
- **Configuration** locations
- **Testing approach**

**Example:**

```
Key files:
- /plugins/prc-pdf-text-extraction/includes/rest-api/ (create here)
- /plugins/prc-platform-core/includes/api/ (pattern reference)

Patterns to follow:
- REST endpoint registration via prc_api_endpoints filter
- Response format matches existing PRC API v3 endpoints
- Error handling follows class-api-error-handler.php

Testing:
- PHPUnit tests in /tests/rest-api/
- Follow test-content-type.php structure
```

---

## The Agent-Ready Checklist

Before labeling an issue `agent-ready`, verify:

- [ ] **Scope is bounded** — Can be completed in one PR
- [ ] **Success is measurable** — Clear pass/fail criteria
- [ ] **Context is sufficient** — Agent can understand why without asking
- [ ] **Patterns are referenced** — Links to similar code in the repo
- [ ] **No external blockers** — API keys available, dependencies installed
- [ ] **Complexity is labeled** — `low`, `medium`, or `high`

---

## Complexity Levels

### Low Complexity

- Single file changes
- Following an obvious existing pattern
- Bug fixes with clear reproduction steps
- Adding tests for existing code

**Example:** Add validation for empty PDF attachments in the upload handler

### Medium Complexity

- Multiple related files
- New feature following established patterns
- Refactoring with clear before/after states
- Integration with one external system

**Example:** Add REST endpoints for text extraction following existing API patterns

### High Complexity

- Architectural decisions required
- Multiple system integrations
- New patterns being established
- Performance-critical code

**Example:** Design and implement multi-provider OCR orchestration with fallback logic

> **Note:** High complexity issues benefit from a planning phase before execution. Have the agent propose an implementation plan for human review before coding.

---

## When Agents Excel

✅ **Use agents for:**

- Implementing features against clear specs
- Following established patterns to new areas
- Writing tests for existing code
- Refactoring with defined outcomes
- Bug fixes with clear reproduction steps
- Documentation generation
- Boilerplate and scaffolding

---

## When Agents Struggle

⚠️ **Be cautious with:**

- Vague requirements ("make it better")
- Novel architecture decisions
- Performance optimization without metrics
- Security-critical code (always human review)
- Code requiring deep institutional knowledge
- Tasks requiring external research

> For these cases, use agents in **interactive mode** — work alongside them rather than delegating fully.

---

## Anti-Patterns to Avoid

### The Kitchen Sink Issue

**Problem:** Issue tries to do too much
**Symptom:** Multiple unrelated acceptance criteria
**Fix:** Split into focused issues, link them with dependencies

### The Assumption Issue

**Problem:** Assumes agent knows your conventions
**Symptom:** "Follow our standard approach"
**Fix:** Link to specific examples, name the patterns

### The Moving Target

**Problem:** Requirements change during execution
**Symptom:** Comments adding new requirements mid-PR
**Fix:** New requirements = new issue. Keep original scope.

### The Mystery Context

**Problem:** No explanation of why
**Symptom:** Agent makes wrong trade-offs
**Fix:** Always include context section explaining purpose

### The Perfectionist Trap

**Problem:** Expecting production-perfect output
**Symptom:** Frustration when agent code needs polish
**Fix:** Expect 80-90%. Plan for human review and refinement.

---

## The Workflow

```
┌─────────────────────────────────────────────────────────────┐
│  1. DEFINE (Human)                                          │
│     Write agent-ready issue with all 5 elements             │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│  2. PLAN (Agent + Human)                                    │
│     Agent proposes implementation plan                      │
│     Human reviews and approves                              │
│     (Skip for low complexity)                               │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│  3. EXECUTE (Agent)                                         │
│     Agent implements against approved plan                  │
│     Creates PR with summary and testing notes               │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│  4. VALIDATE (Human + CI)                                   │
│     CI runs automated checks                                │
│     Human reviews for correctness, security, patterns       │
│     Request changes or approve                              │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│  5. FINALIZE (Human)                                        │
│     Merge PR                                                │
│     Deploy via standard process                             │
│     Close issue                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## Planning Phase Deep Dive

For medium and high complexity issues, the planning phase prevents wasted cycles.

**What to ask for:**

```
Based on this issue, provide an implementation plan including:
1. Files to create or modify
2. Key functions/classes to implement
3. How this integrates with existing code
4. Potential risks or blockers
5. Testing approach
6. Estimated scope (small/medium/large PR)
```

**Review the plan for:**

- Correct understanding of requirements
- Alignment with codebase patterns
- Reasonable scope
- Nothing obviously missing

**Then:** Approve the plan or provide corrections before execution begins.

---

## Issue Template

```markdown
## Summary

<!-- One sentence: what needs to happen -->

## Context

<!-- Why this matters, who uses it, how it fits -->

## Acceptance Criteria

- [ ] Criterion with measurable outcome
- [ ] Another specific criterion
- [ ] Tests pass
- [ ] Code review approved

## Scope

**In scope:**

- Specific deliverable 1
- Specific deliverable 2

**Out of scope:**

- Explicitly excluded item
- Future enhancement (separate issue)

## Technical Notes

**Key files:**

- `/path/to/relevant/file.php`
- `/path/to/pattern/reference.php`

**Patterns to follow:**

- Name the pattern, link to example

**Dependencies:**

- Required packages, API keys, etc.

**Testing:**

- How to verify this works

## Complexity

`complexity:medium`

## Agent Readiness

- [ ] Scope is bounded
- [ ] Success is measurable
- [ ] Context is sufficient
- [ ] Patterns are referenced
- [ ] No external blockers
```

---

## Quick Reference

| Element             | Question It Answers       |
| ------------------- | ------------------------- |
| Summary             | What are we building?     |
| Context             | Why does it matter?       |
| Acceptance Criteria | How do we know it's done? |
| Scope Boundaries    | What's in and out?        |
| Technical Notes     | How do we build it?       |

---

## Getting Started

1. **Start small** — Pick a low-complexity issue for your first agent-assisted task
2. **Use the template** — It forces good structure
3. **Review agent output** — Learn what works and what needs refinement
4. **Iterate on issues** — Improve your issue-writing based on results
5. **Share learnings** — Document patterns that work for your codebase

---

## GitHub Integration

### Labels for Agent Workflow

Set up these labels in your repository:

| Label               | Purpose                                        |
| ------------------- | ---------------------------------------------- |
| `agent-ready`       | Issue is properly scoped for agent execution   |
| `needs-planning`    | Requires agent planning phase before execution |
| `agent-generated`   | PR was created by an agent                     |
| `complexity:low`    | Single file, clear pattern                     |
| `complexity:medium` | Multiple files, established patterns           |
| `complexity:high`   | Architectural decisions, needs planning        |

### Using GitHub Copilot Workspace

[Copilot Workspace](https://githubnext.com/projects/copilot-workspace) can take issues directly to PRs:

1. **Open an agent-ready issue** in your browser
2. **Click "Open in Workspace"** (Copilot button)
3. **Review the generated plan** — Copilot analyzes the issue and proposes changes
4. **Edit the plan** if needed — Add/remove files, adjust approach
5. **Generate code** — Copilot implements the plan
6. **Review and refine** — Edit generated code in the workspace
7. **Create PR** — Push directly to a branch and open PR

**Tips for Copilot Workspace:**

- Well-structured issues = better plans
- The Technical Notes section is especially important
- Review the plan carefully before generating code
- Use "Regenerate" if the plan misses the mark

### Using Cursor Background Agents

[Cursor's long-running agents](https://cursor.com/agents) can work autonomously:

1. **Clone the repo** in Cursor
2. **Reference the GitHub issue** — Paste URL or issue content
3. **Request a plan** — "Based on issue #123, create an implementation plan"
4. **Review and approve** the plan
5. **Execute** — Agent implements, can run for hours
6. **Review output** — Agent creates branch with changes
7. **Push and PR** — Create PR from the agent's branch

**Tips for Cursor Agents:**

- Use for medium/high complexity issues
- Always do planning phase first
- Check in periodically on long runs
- Agent can run while you do other work

### Using Claude Code / Codex CLI

For command-line agent workflows:

```bash
# Navigate to repo
cd ~/Sites/prc-platform

# Have agent read and plan
claude "Read issue #2130 and create an implementation plan for Phase 4"

# Review plan, then execute
claude "Implement the approved plan for the REST API endpoints"

# Agent works, creates commits
# Push branch and create PR via gh CLI
gh pr create --title "Add REST API endpoints" --body "Closes #2130"
```

### PR Template for Agent-Generated Code

Create `.github/PULL_REQUEST_TEMPLATE/agent-generated.md`:

```markdown
## Agent-Generated PR

**Issue:** #[issue_number]
**Agent:** [Copilot Workspace / Cursor / Claude Code]
**Complexity:** [low / medium / high]

### Summary

<!-- What this PR does -->

### Implementation Notes

<!-- Key decisions made, patterns followed -->

### Testing Done

- [ ] Automated tests pass
- [ ] Manual testing performed
- [ ] Edge cases considered

### Review Checklist

- [ ] Code follows project patterns
- [ ] No security concerns
- [ ] No hardcoded values that should be config
- [ ] Tests are meaningful (not just coverage)
- [ ] Documentation updated if needed

### Human Reviewer Notes

<!-- Anything the reviewer should pay special attention to -->
```

### CI Requirements for Agent PRs

Configure required checks in branch protection:

```yaml
# .github/workflows/agent-pr-checks.yml
name: Agent PR Validation

on:
    pull_request:
        types: [opened, synchronize]

jobs:
    validate:
        runs-on: ubuntu-latest
        steps:
            - uses: actions/checkout@v4

            - name: Lint
              run: npm run lint

            - name: Type Check
              run: npm run typecheck

            - name: Unit Tests
              run: npm test

            - name: Security Scan
              uses: github/codeql-action/analyze@v2
```

**Required checks before merge:**

- All linting passes
- All tests pass
- Security scan clean
- At least one human approval

### Code Review Guidelines for Agent PRs

When reviewing agent-generated code, focus on:

**1. Intent Match**

- Does the code actually solve the issue?
- Are acceptance criteria met?

**2. Pattern Adherence**

- Does it follow existing codebase patterns?
- Are naming conventions consistent?

**3. Edge Cases**

- What happens with empty inputs?
- Error handling present?
- Boundary conditions covered?

**4. Security**

- Input validation present?
- No exposed secrets?
- Proper escaping/sanitization?

**5. Performance**

- Any obvious N+1 queries?
- Reasonable complexity?
- Caching where appropriate?

**6. Tests**

- Are tests actually testing behavior?
- Edge cases covered?
- Not just happy path?

### Automation Ideas

**Auto-label agent-ready issues:**

```yaml
# .github/workflows/auto-label.yml
name: Auto Label

on:
    issues:
        types: [opened, edited]

jobs:
    label:
        runs-on: ubuntu-latest
        steps:
            - uses: actions/github-script@v7
              with:
                  script: |
                      const body = context.payload.issue.body || '';
                      const hasAllSections =
                        body.includes('## Summary') &&
                        body.includes('## Acceptance Criteria') &&
                        body.includes('## Scope') &&
                        body.includes('## Technical Notes');

                      if (hasAllSections) {
                        await github.rest.issues.addLabels({
                          owner: context.repo.owner,
                          repo: context.repo.repo,
                          issue_number: context.issue.number,
                          labels: ['agent-ready']
                        });
                      }
```

**Notify on agent-ready:**

```yaml
# Post to Slack/Discord when issue is labeled agent-ready
- name: Notify
  if: contains(github.event.label.name, 'agent-ready')
  run: |
      curl -X POST $SLACK_WEBHOOK -d '{
        "text": "Issue #${{ github.event.issue.number }} is ready for agent execution"
      }'
```

---

## Resources

**Agent Platforms:**

- [Cursor Long-Running Agents](https://cursor.com/blog/long-running-agents) — Autonomous agent capabilities
- [GitHub Copilot Workspace](https://githubnext.com/projects/copilot-workspace) — Issue-to-PR in browser
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) — CLI-based coding agent
- [OpenAI Codex CLI](https://github.com/openai/codex) — OpenAI's coding agent

**Background Reading:**

- [Cursor: Self-Driving Codebases](https://cursor.com/blog/self-driving-codebases) — Vision for agent-assisted development
- [GitHub: AI-Powered Development](https://github.blog/ai-and-ml/) — GitHub's AI roadmap

**This Repository:**

- Issue Template: `/.github/ISSUE_TEMPLATE/agent-ready.md`
- PR Template: `/.github/PULL_REQUEST_TEMPLATE/agent-generated.md`
- Example Issues: See `agent-ready` label

---

_This is a living document. Update it as you learn what works for your team and codebase._
