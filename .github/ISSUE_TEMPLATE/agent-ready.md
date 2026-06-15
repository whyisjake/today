---
name: '🤖 Agent-Ready Task'
about: Well-scoped issue for AI-assisted development
title: ''
labels: 'agent-ready'
assignees: ''
---

## Summary

<!-- One sentence: What needs to be built or fixed? If you need more than one sentence, the scope may be too big. -->

## Context

<!-- Why does this matter? Who uses it? How does it fit into the bigger picture?
     Agents don't have institutional knowledge — give them the "why" so they make good trade-offs. -->

## Acceptance Criteria

<!-- Define "done" with specific, testable criteria. Each should be verifiable. -->

- [ ]
- [ ]
- [ ]
- [ ] Tests pass (unit + integration as appropriate)
- [ ] Passes linting and code standards (project-specific)
- [ ] Code review approved

## Scope

**In scope:**

<!-- Be explicit about what this issue includes -->

-
-

**Out of scope:**

<!-- Explicitly exclude things to prevent scope creep. "Future enhancement" is fine. -->

-
-

## Technical Notes

<!-- Give the agent everything it needs to match your codebase patterns -->

**Key files:**

<!-- Files to create, modify, or use as reference -->

```
- src/path/to/file-to-modify.ext
- src/path/to/pattern-reference.ext  (for reference)
```

**Patterns to follow:**

<!-- Name specific patterns, link to examples in the codebase -->

- See `src/...` for similar implementation
- Follow project coding standards

**Dependencies:**

<!-- Required packages, API keys, environment setup, etc. -->

-

**Testing approach:**

<!-- How should this be tested? What test files to create/update? -->

- Add tests to `tests/` or the project's test directory
-

## Complexity

<!-- Delete the ones that don't apply -->

- [ ] `complexity:low` — Single file, obvious pattern, quick fix
- [x] `complexity:medium` — Multiple files, follows established patterns
- [ ] `complexity:high` — Architectural decisions, new patterns, needs planning phase

## Agent Readiness

<!-- Verify before adding the agent-ready label -->

- [ ] Scope is bounded (can be done in one PR)
- [ ] Success criteria are measurable
- [ ] Context explains the "why"
- [ ] Patterns are linked, not assumed
- [ ] No external blockers (APIs available, dependencies installed)
- [ ] Complexity is appropriate for agent execution

---

<!--
TIPS FOR GOOD AGENT ISSUES:

✅ DO:
- Be specific about file locations
- Link to similar implementations in the codebase
- Define clear boundaries
- Include error cases in acceptance criteria

❌ DON'T:
- Use vague language ("improve", "enhance", "make better")
- Assume the agent knows your conventions
- Combine unrelated changes
- Skip the context section

See docs/AGENTIC_DEVELOPMENT.md for full guidelines.
-->
