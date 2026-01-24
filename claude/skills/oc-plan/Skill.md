---
name: oc-plan
description: Development plan generator using Claude's plan mode. Use when user wants to create a development plan from a spec, break down tasks, or manage project progress. Triggers on requests to create a plan, generate tasks from spec, or track development progress. Reads from `.claude/spec/` and outputs to `.claude/plan/`. Leverages Claude's native plan mode for structured planning.
---

# OC-Plan: Development Plan Generator

Generate actionable development plans from SPEC files using Claude's plan mode, with tasks broken down to minimal modules, dependency tracking, and progress management.

## File Location Convention

- **Read SPEC from**: `.claude/spec/`
- **Write Plan to**: `.claude/plan/`
- **Naming**: Plan filename must match the corresponding SPEC filename
  - `.claude/spec/SPEC.md` → `.claude/plan/SPEC.md`
  - `.claude/spec/auth-spec.md` → `.claude/plan/auth-spec.md`
  - `.claude/spec/[feature-name].md` → `.claude/plan/[feature-name].md`

Before starting:
```bash
mkdir -p .claude/plan
```

## Core Workflow

1. **Read SPEC** from `.claude/spec/` - understand the full scope
2. **Enter plan mode** - use `shift+tab` or start message with `plan:` to activate plan mode
3. **Generate structured plan** - leverage plan mode's structured thinking for task breakdown
4. **Interview to refine** - clarify ambiguities, adjust granularity, confirm dependencies
5. **Write plan to project** - explicitly write finalized plan to `.claude/plan/` (NOT the default `~/.claude/plans`)

## Plan Mode Integration

### Activating Plan Mode

Plan mode can be activated by:
- Pressing `shift+tab` to toggle into plan mode
- Prefixing message with `plan:`
- User explicitly requesting "plan this" or "create a plan"

### Plan Mode Behavior

When in plan mode:
- Focus on analysis and planning, not immediate execution
- Break down the SPEC into structured, actionable tasks
- Identify dependencies and sequence
- Present plan for user review before any implementation
- Ask clarifying questions about ambiguities

### Critical: Plan File Location

**DO NOT use the default plan mode save location (`~/.claude/plans`).**

After plan mode generates the plan:
1. Ensure `.claude/plan/` directory exists in project root
2. Write the final plan using the **same filename as the source SPEC**
   - Source: `.claude/spec/SPEC.md` → Output: `.claude/plan/SPEC.md`
   - Source: `.claude/spec/auth.md` → Output: `.claude/plan/auth.md`
3. The plan must live within the project, not in user's home directory

```bash
# Always write to project directory with matching filename
mkdir -p .claude/plan
# If reading from .claude/spec/feature-x.md
# Write plan to .claude/plan/feature-x.md
```

This ensures:
- Clear 1:1 mapping between spec and plan files
- Version controlled with the project
- Accessible to all team members
- Easy to find the plan for any given spec

## Task Breakdown Principles

- **Atomic tasks**: Each task completable in one focused session
- **Single responsibility**: One task = one clear outcome
- **Testable**: Each task has verifiable completion criteria
- **Dependency-aware**: Explicit prerequisites for each task

### Granularity Guidelines

Break down until each task:
- Touches ideally one file or one logical unit
- Has no hidden sub-steps
- Can be understood without additional context
- Has clear "done" criteria

### Dependency Types

- `blocked-by: [task-id]` - Cannot start until dependency complete
- `related: [task-id]` - Shares context, benefits from sequential work
- `parallel: [task-id]` - Can be worked on simultaneously

## Plan Generation Process

In plan mode, analyze SPEC and:

1. **Extract functional areas** from SPEC's requirements
2. **Identify technical layers** (data, logic, UI, integration)
3. **Map dependencies** between components
4. **Break into phases**:
   - Phase 1: Foundation (data models, core setup)
   - Phase 2: Core Features (main functionality)
   - Phase 3: Integration (connecting components)
   - Phase 4: Polish (edge cases, UX refinement)
5. **Decompose each feature** into atomic tasks
6. **Present draft for review** before finalizing

## Interview for Refinement

After presenting draft plan, ask targeted questions:

- "Task X seems complex. Should I break it into [suggested subtasks]?"
- "I assumed X depends on Y. Correct, or can they be parallel?"
- "Which phase is MVP-critical vs nice-to-have?"
- "Any existing patterns/code to follow?"

## Plan Output Format

```markdown
# [Project Name] Development Plan

> Source SPEC: `.claude/spec/[filename].md`
> Plan file: `.claude/plan/[filename].md`
> Last updated: [date]

## Overview
Brief summary of what this plan covers.

## Progress Summary
- Total tasks: X
- Completed: Y (Z%)
- In Progress: N
- Blocked: M

## Phases

### Phase 1: Foundation
> Goal: [phase objective]

#### Module: [module-name]

- [ ] `P1-001` **Task title**
  - Description: What to implement
  - Outcome: Verifiable completion criteria
  - Dependencies: none
  - Files: `path/to/file.ts`

- [ ] `P1-002` **Task title**
  - Description: What to implement
  - Outcome: Verifiable completion criteria
  - Dependencies: `blocked-by: P1-001`
  - Files: `path/to/file.ts`

### Phase 2: Core Features
> Goal: [phase objective]

[Continue for all phases...]

## Deferred / Future
Tasks identified but not in current scope:
- [ ] `FUTURE-001` **Task description** - Reason for deferral

## Notes
- Implementation decisions and rationale
- Known risks or uncertainties
```

## Progress Tracking

### Status Markers
- `- [ ]` → Not started
- `- [x]` → Completed
- `- [~]` → In progress
- `- [!]` → Blocked

### Progress Commands
- "Mark P1-001 as done" → Update checkbox, recalculate summary
- "What's blocked?" → List tasks with unmet dependencies
- "What can I work on next?" → List tasks with all dependencies met
- "Update progress" → Review and update multiple task statuses

## Development Workflow

After plan is created:
1. Exit plan mode to begin implementation
2. Reference task IDs when working
3. Check dependencies before starting a task
4. Update task status after completion
5. Re-enter plan mode if scope changes require re-planning

## Notes

- Keep tasks atomic - if explanation is long, task is too big
- Dependencies should form a DAG (no cycles)
- Re-enter plan mode if major scope changes occur
- Plan is living document - update as understanding evolves
