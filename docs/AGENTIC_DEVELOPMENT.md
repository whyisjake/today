# Agentic Development Guide

## Writing Issues That Agents Can Execute

**Version:** 1.0
**Date:** June 2026
**Audience:** Engineering teams adopting AI-assisted development

---

## The Core Idea

AI coding agents can take well-scoped issues 80–90% to completion before human review. The key word is **well-scoped**. A vague issue produces vague code. A precise issue produces precise code.

This guide teaches you how to write issues that agents can actually execute, how to configure the workflow for your chosen provider, and how to integrate Compound Engineering when using Claude.

---

## Provider Overview

| Provider | AGENT_PROVIDER value | Required secret | Notes |
|----------|---------------------|-----------------|-------|
| Claude + Compound Engineering | `claude` (default) | `CLAUDE_CODE_OAUTH_TOKEN` | Full support — complexity-aware, planning phase for high complexity |
| OpenAI Codex | `openai-codex` | `OPENAI_API_KEY` | Stub — configure the `trigger-openai-codex` job |
| GitHub Copilot (gh-aw) | `copilot` | _(gh-aw setup)_ | Stub — configure the `trigger-copilot` job |
| Custom / bring-your-own | `custom` | _(your own)_ | Dispatches `repository_dispatch` event; add your listener |

Set `AGENT_PROVIDER` in **Settings → Secrets and variables → Variables**. If not set, the workflow defaults to `claude`.

---

## The 5 Elements of an Agent-Ready Issue

### 1. Clear Summary (One Sentence)

State what needs to happen in a single sentence. If you can't, the scope is too big.

**❌ Bad:**
> Improve the data pipeline

**✅ Good:**
> Add a REST endpoint that returns the latest pipeline run status as JSON

---

### 2. Context (Why This Matters)

Agents don't have institutional knowledge. Tell them:

- Why this feature exists
- Who uses it
- What problem it solves
- How it fits into the bigger picture

**Example:**
> External monitoring tools need programmatic access to pipeline status. Currently the status is only visible in the admin dashboard. A REST endpoint enables integration with Datadog, PagerDuty, and custom alerting scripts.

---

### 3. Acceptance Criteria (Checkboxes)

Define "done" with measurable criteria. Each criterion should be testable.

**❌ Vague:**
- [ ] API works correctly
- [ ] Good error handling

**✅ Specific:**
- [ ] `GET /api/v1/pipeline/status` returns `{ status, last_run_at, duration_ms }`
- [ ] Returns 404 when pipeline has never run
- [ ] Returns 503 when pipeline is currently failing
- [ ] Response includes `Cache-Control: no-cache` header
- [ ] Unit tests cover success, 404, and 503 cases

---

### 4. Scope Boundaries (In/Out)

Explicitly state what's included and excluded. Agents try to be helpful — sometimes too helpful. Boundaries prevent scope creep.

**Example:**
```
In scope:
- GET endpoint for current status
- JSON response format
- Error handling for missing/failed pipeline
- Unit tests

Out of scope:
- Authentication (existing endpoints are public)
- Historical run data (separate issue)
- Webhook notifications for status changes
```

---

### 5. Technical Notes (The Cheat Sheet)

Give the agent everything it needs to match your codebase:

- **Key files** to read or modify
- **Patterns to follow** (link to similar implementations)
- **Dependencies** and configuration
- **Testing approach**

**Example:**
```
Key files:
- src/api/routes/pipeline.ts (create here)
- src/api/routes/health.ts (pattern reference)

Patterns to follow:
- Route registration in src/api/index.ts
- Error response format matches src/api/errors.ts

Testing:
- Jest tests in src/api/__tests__/
- Follow health.test.ts structure
```

---

## The Agent-Ready Checklist

Before labeling an issue `agent-ready`:

- [ ] **Scope is bounded** — Can be completed in one PR
- [ ] **Success is measurable** — Clear pass/fail criteria
- [ ] **Context is sufficient** — Agent can understand why without asking
- [ ] **Patterns are referenced** — Links to similar code in the repo
- [ ] **No external blockers** — API keys available, dependencies installed
- [ ] **Complexity is labeled** — `complexity:low`, `complexity:medium`, or `complexity:high`

---

## Complexity Levels

### `complexity:low`
- Single file changes
- Following an obvious existing pattern
- Bug fixes with clear reproduction steps
- Adding tests for existing code

**Example:** Add validation for empty input in an existing form handler

### `complexity:medium`
- Multiple related files
- New feature following established patterns
- Refactoring with clear before/after states
- Integration with one external system

**Example:** Add REST endpoints following existing API patterns in the codebase

### `complexity:high`
- Architectural decisions required
- Multiple system integrations
- New patterns being established
- Performance-critical code paths

**Example:** Design and implement a multi-provider data pipeline with fallback logic

> **Note:** `complexity:high` issues trigger a planning phase when using Claude + CE. The agent generates an implementation plan that a human approves before any code is written.

---

## The Workflow

```
┌─────────────────────────────────────────────────────────────┐
│  1. DEFINE (Human)                                          │
│     Write agent-ready issue with all 5 elements             │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│  2. PLAN (Agent + Human)  — complexity:high only            │
│     Agent proposes implementation plan                      │
│     Human reviews: reply /approve-plan to proceed           │
│     (Skipped for low/medium complexity)                     │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│  3. EXECUTE (Agent)                                         │
│     Agent implements against issue (and plan if present)    │
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
│     Deploy via your standard process                        │
│     Close issue                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## Compound Engineering Integration

[Compound Engineering](https://github.com/EveryInc/compound-engineering-plugin) is a Claude Code plugin that provides structured planning (`/ce-plan`) and work execution (`/ce-work`) skills.

When `AGENT_PROVIDER=claude`, the trigger workflow uses CE automatically:

### Low/Medium Complexity Flow

```
agent-ready label applied
        ↓
agent-ready-trigger.yml fires
        ↓
Claude invokes /ce-work on the issue
        ↓
/ce-work reads the issue, implements the feature, opens a PR
```

### High Complexity Flow

```
agent-ready label applied
        ↓
agent-ready-trigger.yml fires
        ↓
Claude invokes /ce-plan on the issue
        ↓
Plan committed to docs/plans/ on a branch
        ↓
Claude posts comment: "Review plan → reply /approve-plan to implement"
        ↓
Human reviews the plan (in docs/plans/)
        ↓
Human replies /approve-plan
        ↓
plan-approval-gate.yml fires
        ↓
Claude invokes /ce-work with the plan as context
        ↓
/ce-work implements the plan and opens a PR
```

### Using CE Interactively (Outside the Workflow)

You can also invoke CE manually in your local Claude Code session:

```bash
# Plan a feature from an issue
claude "/ce-plan [paste issue description or use issue URL]"

# Execute a plan
claude "/ce-work docs/plans/2026-01-15-001-feat-my-feature-plan.md"

# Or work from the issue directly
claude "/ce-work Implement the feature described in GitHub issue #42"
```

CE is a Claude Code plugin. Other providers use equivalent plain-language prompts without the CE skill layer — the workflow adapts the prompt accordingly.

---

## GitHub Setup

### Initial Setup (One Time)

1. **Use the template** — Click "Use this template" on GitHub
2. **Enable the template flag** — Settings → General → check "Template repository"
3. **Sync labels** — Actions → Setup Labels → Run workflow
4. **Set your provider** — Settings → Secrets and variables → Variables → `AGENT_PROVIDER`
5. **Add your secret** — Settings → Secrets and variables → Secrets → add the required token

### Labels

The workflow uses 7 labels. All are created by the Setup Labels workflow.

| Label | Applied by | Meaning |
|-------|-----------|---------|
| `agent-ready` | Human or auto-labeler | Issue is scoped for agent execution |
| `agent-candidate` | Issue screener | Screener flagged as promising — human review needed |
| `agent-generated` | Agent | PR was created by an agent |
| `needs-planning` | Human | Manual flag: this issue needs a plan before execution |
| `complexity:low` | Human | Single file, clear pattern |
| `complexity:medium` | Human | Multiple files, established patterns |
| `complexity:high` | Human | Architectural work — triggers planning phase |

### Adding CI Checks

This template intentionally omits a CI workflow — linting and testing commands are too stack-specific to generalize. Add your own:

```yaml
# .github/workflows/ci.yml
name: CI
on: [push, pull_request]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Install
        run: npm install  # or: pip install, bundle install, etc.
      - name: Lint
        run: npm run lint
      - name: Test
        run: npm test
```

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
- Error handling present and correct?
- Boundary conditions covered?

**4. Security**
- Input validation present?
- No exposed secrets?
- Data properly sanitized?

**5. Tests**
- Are tests actually testing behavior?
- Edge cases covered?
- Not just the happy path?

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

> For these cases, use agents in **interactive mode** — work alongside them rather than delegating fully.

---

## Anti-Patterns to Avoid

### The Kitchen Sink Issue
**Problem:** Issue tries to do too much
**Fix:** Split into focused issues, link them with dependencies

### The Assumption Issue
**Problem:** Assumes agent knows your conventions
**Fix:** Link to specific examples, name the patterns explicitly

### The Moving Target
**Problem:** Requirements change during execution
**Fix:** New requirements = new issue. Keep original scope.

### The Mystery Context
**Problem:** No explanation of why
**Fix:** Always include context explaining purpose and users

### The Perfectionist Trap
**Problem:** Expecting production-perfect output
**Fix:** Expect 80–90%. Plan for human review and refinement.

---

## Extending Provider Stubs

The `openai-codex` and `copilot` jobs in `agent-ready-trigger.yml` are intentional stubs. To activate them:

1. Open `.github/workflows/agent-ready-trigger.yml`
2. Find the stub job for your provider (search for `# TODO: extend`)
3. Replace the stub `run:` block with your actual invocation
4. Add the required secret (see the job's `env:` block)

If you build a working provider integration, consider contributing it back via a PR!

---

## Quick Reference

| Element | Question It Answers |
|---------|---------------------|
| Summary | What are we building? |
| Context | Why does it matter? |
| Acceptance Criteria | How do we know it's done? |
| Scope Boundaries | What's in and out? |
| Technical Notes | How do we build it? |

---

## Getting Started

1. **Start small** — Pick a `complexity:low` issue for your first agent-assisted task
2. **Use the template** — It forces good structure
3. **Review agent output** — Learn what works and what needs refinement
4. **Iterate on issues** — Improve your issue-writing based on results
5. **Share learnings** — Document patterns that work for your codebase

---

_This is a living document. Update it as you learn what works for your team._
