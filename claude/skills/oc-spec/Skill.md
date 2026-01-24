---
name: oc-spec
description: Deep product/software specification interviewer. Use when user wants to create or refine a product spec through in-depth interviews. Triggers on requests to interview about a spec, refine a spec, create a spec through questions, or when user shares a SPEC file and asks for detailed questioning. Outputs a spec file ready to serve as a development plan starting point.
---

# OC-Spec: Deep Specification Interviewer

Create comprehensive product specifications through systematic, in-depth interviews that uncover critical implementation decisions early.

## File Location Convention

**All SPEC files MUST be stored in `.claude/spec/` directory within the project root.**

- **Read**: Look for existing specs in `.claude/spec/`
- **Create**: Always write new specs to `.claude/spec/`
- **Naming**: Use descriptive names - this name will also be used by the corresponding plan file
  - `.claude/spec/SPEC.md` (default for single spec projects)
  - `.claude/spec/[feature-name].md` (for multi-spec projects)
  - Example: `.claude/spec/auth.md` → later generates `.claude/plan/auth.md`

Before starting, ensure the directory exists:
```bash
mkdir -p .claude/spec
```

## Core Workflow

1. **Check `.claude/spec/`** for existing SPEC or create directory if needed
2. **Read existing SPEC** (if found) or acknowledge starting from scratch
3. **Interview systematically** - ask multiple deep questions per round
4. **Track coverage** - ensure all critical areas are addressed
5. **Complete when** - user confirms AND all key areas covered
6. **Output SPEC** - write to `.claude/spec/` as development plan starting point

## Interview Strategy

### Question Principles

- Ask questions that **impact implementation decisions** - things that must be decided or ruled out early
- Prioritize **feasibility first**, then **extensibility**
- Avoid obvious questions - dig into non-trivial tradeoffs
- Ask multiple related questions per round (3-5 questions)
- Build on previous answers to go deeper

### Question Categories (Priority Order)

**1. Feasibility & Core Scope**
- What's the MVP vs future scope?
- What are the hard technical constraints?
- What existing systems must this integrate with?
- What's absolutely out of scope?

**2. Data & State**
- What data needs to persist vs ephemeral?
- Who owns the data? Where does it live?
- What's the source of truth for X?
- How does state flow between components?

**3. Edge Cases & Error Handling**
- What happens when X fails?
- How to handle partial success?
- What are the concurrent access scenarios?
- What inputs are invalid and how to respond?

**4. User Experience Decisions**
- What feedback does user need at each step?
- How to handle loading/waiting states?
- What's the undo/recovery story?
- How does this behave offline or degraded?

**5. Security & Permissions**
- Who can do what?
- What needs authentication vs authorization?
- What data is sensitive?
- What audit trail is needed?

**6. Performance & Scale**
- What's the expected load?
- What operations must be fast vs can be async?
- What are the caching strategies?
- How does this scale if 10x users?

**7. Extensibility & Maintenance**
- What's likely to change?
- What customization points are needed?
- How will this be tested?
- What monitoring/debugging is needed?

## Interview Execution

### Opening
```
I'll interview you to build a comprehensive spec. I'll ask multiple deep questions 
per round, focusing on decisions that impact implementation. Let me know when you 
feel we've covered enough, but I'll also flag if I think critical areas remain.

[If SPEC provided]: I've read the spec. Let me start with questions about [area].
[If from scratch]: Let's start with the core concept. What are you building and why?
```

### During Interview
- Group related questions together
- Explicitly note when moving to a new category
- Summarize key decisions after each round
- Flag assumptions that need validation
- Note areas marked for future consideration vs current scope

### Completion Check
Before concluding, verify coverage:
- [ ] Core scope and MVP defined
- [ ] Key data models understood
- [ ] Critical edge cases addressed
- [ ] UX decisions for main flows
- [ ] Security model clear
- [ ] Performance expectations set
- [ ] Extension points identified

Ask user: "I believe we've covered the critical areas. Ready to generate the spec, or are there areas you want to explore further?"

## SPEC Output Format

Output a markdown file structured as a development plan starting point:

```markdown
# [Project Name] Specification

## Overview
Brief description, goals, and success criteria.

## Scope
### In Scope (MVP)
### In Scope (Future)
### Out of Scope

## Core Concepts
Key domain terms and their definitions.

## Functional Requirements
### [Feature Area 1]
- Requirement with acceptance criteria
- Edge case handling

## Technical Architecture
### Data Model
### System Components
### Integration Points

## User Experience
### Key Flows
### States and Feedback
### Error Handling UX

## Security & Permissions
### Authentication
### Authorization Model
### Data Sensitivity

## Performance Requirements
### Response Time Expectations
### Scale Targets
### Caching Strategy

## Extensibility
### Planned Extension Points
### Configuration Options

## Open Questions
Items requiring further investigation.

## Decisions Log
Key decisions made during spec creation with rationale.
```

## Notes

- The spec should be actionable - developers can start planning tasks from it
- Include rationale for non-obvious decisions
- Mark uncertainties explicitly rather than glossing over them
- Keep technical jargon appropriate to the team's level
