---
name: go-code-review
description: Expert Go code review skill specialized for Kratos, gRPC, and GORM ecosystems. Use when the user asks to review Go code, check Go code quality, audit a Go project, or submits .go files for review. Also triggers on "code review", "review this", "check my code" when Go code is involved. Covers idiomatic Go style, SOLID principles, architecture, concurrency safety, error handling, security, performance, and framework-specific best practices. Always use this skill when Go code review is mentioned, even partially.
---

# Go Code Review Expert

Perform structured, senior-engineer-level code reviews for Go projects, with deep expertise in the Kratos + gRPC + GORM ecosystem. Output findings by severity (P0–P3) with actionable fix suggestions.

## Workflow

Follow these steps in order. Do NOT skip any step.

### Step 1: Preflight — Determine Review Mode

Two modes are supported. **Incremental is the default** unless the user explicitly requests a full/codebase/全量 review.

---

#### Mode A: Incremental Review (Default)

Triggered by: no special instruction, or user says "review", "review my changes", "check my code".

1. Run `git diff --name-only HEAD` (and `git diff --staged --name-only`) to identify changed files
2. Filter to `.go` files only
3. **Skip auto-generated files**: `*.pb.go`, `*_gen.go`, `wire_gen.go`, `*_string.go`, `*.pb.validate.go`
4. **Skip vendor/**: Do not review vendored dependencies
5. If no git changes found, tell user and suggest full codebase review instead
6. Run `git diff` on scoped files to get the actual change content

Output:
```
📋 Mode: Incremental (git changes)
Scoped N files for review: [file list]
Skipped M generated/vendor files.
```

---

#### Mode B: Full Codebase Review

Triggered by: user says "full review", "full codebase", "review the whole project", "全量 review", "全量审查", or similar.

This mode performs a systematic, project-wide review. Because a full codebase can be large, follow this phased scan strategy:

**Phase 1: Project Structure Audit**

```bash
# Map the project layout
find . -name "*.go" -not -path "./vendor/*" -not -name "*.pb.go" -not -name "*_gen.go" -not -name "wire_gen.go" | head -200
```

Check:
- [ ] Follows Kratos layout (`api/`, `cmd/`, `configs/`, `internal/{biz,data,service,server}/`)
- [ ] `go.mod` module path and Go version are appropriate
- [ ] No business logic in `cmd/`
- [ ] Internal packages used correctly
- [ ] Package dependency graph has no cycles (scan import statements)

**Phase 2: Dependency & Config Scan**

- Review `go.mod` for outdated or vulnerable dependencies
- Scan for hardcoded secrets across all `.go` files: `grep -rn "password\|secret\|api_key\|token" --include="*.go" .`
- Check config files for sensitive data committed to repo
- Verify `.gitignore` excludes sensitive files

**Phase 3: Core Layer Review**

Review each layer in priority order (highest risk first):

1. **`internal/data/`** — Repository implementations, GORM usage, SQL, connection management
2. **`internal/biz/`** — Business logic, domain models, use case correctness
3. **`internal/service/`** — Transport layer, request validation, error mapping
4. **`internal/server/`** — Server config, middleware chain, interceptors
5. **`api/`** (non-generated) — Proto design, API conventions

For each layer, apply Steps 2–5 (SOLID, Removal, Security, Quality) against ALL files in that layer.

**Phase 4: Cross-Cutting Concerns**

- **Error handling consistency**: Is there a unified error model across layers?
- **Logging**: Structured? Consistent levels? Sensitive data redacted?
- **Observability**: Tracing propagated? Metrics exposed? Health checks present?
- **Testing**: Run `go test ./... -count=1` mentally — estimate coverage gaps. Check if critical paths (`biz/`) have tests.
- **Build & CI**: Verify linter config, Makefile/build scripts, Dockerfile best practices

**Phase 5: Architecture Summary**

Produce an additional section at the top of the report:

```markdown
## 🏗️ Architecture Overview

**Project**: [module name from go.mod]
**Go Version**: [version]
**Framework**: Kratos / Standard / Other
**Structure Compliance**: ✅ Good / ⚠️ Partial / ❌ Non-standard

### Dependency Graph
[Brief description of layer dependencies, any violations]

### Tech Stack
- HTTP/gRPC: [framework]
- ORM: [GORM / sqlx / raw]
- DI: [wire / manual]
- Config: [Kratos config / viper / env]

### Key Observations
- [Top 3 architectural observations]
```

Output:
```
📋 Mode: Full Codebase Review
Project: [module name]
Total .go files: N (excluding generated/vendor)
Scanning in 5 phases...
```

### Step 2: Go Style + SOLID + Architecture

Read `references/go-solid-checklist.md` and apply every prompt against the scoped code.

> **Full Codebase mode**: Apply per-layer during Phase 3. Start with the most critical layer (`data/`, then `biz/`).

Focus areas:
- **Idiomatic Go**: naming, package design, interface usage, error patterns
- **SOLID violations**: god structs, leaky abstractions, concrete dependencies
- **Kratos architecture**: layer separation (transport → service → biz → data), wire DI
- **Code smells**: deep nesting, long functions, feature envy, shotgun surgery

### Step 3: Removal Candidates

Read `references/removal-plan.md` and identify:

- Dead code: unexported functions/types with zero callers
- Commented-out code blocks
- Unused imports (should already be caught by `goimports`, but verify)
- Deprecated API usage
- Orphaned test helpers

For each candidate, classify as **safe to remove** or **deferred removal** (needs verification).

### Step 4: Security Scan

Read `references/security-checklist.md` and scan for:

- **Go-specific**: unsafe pointer usage, CGo risks, insecure random (`math/rand` for crypto)
- **Concurrency**: data races, goroutine leaks, missing context propagation
- **gRPC**: missing auth interceptors, unvalidated input, excessive message sizes
- **GORM**: SQL injection via raw queries, mass assignment, missing transaction rollback
- **General**: hardcoded secrets, path traversal, SSRF, improper TLS config

### Step 5: Code Quality

Read `references/code-quality-checklist.md` and check:

- **Error handling**: swallowed errors, missing error wrapping, bare `log.Fatal` in library code
- **Performance**: N+1 queries, unnecessary allocations, missing slice preallocation, reflection in hot paths
- **GORM large table awareness**: missing indexes, OFFSET pagination on large tables, unbounded queries, soft delete pitfalls
- **Boundary conditions**: nil pointer dereference, empty slice/map access, integer overflow, off-by-one
- **Memory leaks**: `time.After` in loops, unclosed tickers, subslice backing array retention, blocked goroutines
- **Logging & observability**: structured logging, log level discipline, sensitive data in logs, trace propagation, metrics
- **Graceful shutdown**: signal handling, request draining, background goroutine cleanup, resource cleanup order
- **API contract quality**: gRPC status code correctness, Kratos error consistency, proto backward compatibility, request validation
- **Database safety**: migration backward compatibility, large table DDL risks, GORM hook side effects, soft delete consistency
- **Testing**: adequate coverage for changed code, table-driven tests, proper test isolation

### Step 6: Output — Findings Report

Save the report as a markdown file to `.claude/issues/` in the project root. Use a timestamp filename with mode prefix.

```bash
mkdir -p .claude/issues
# Incremental: .claude/issues/review-YYYY-MM-DD_HH-MM-SS.md
# Full:        .claude/issues/full-review-YYYY-MM-DD_HH-MM-SS.md
```

Present all findings in a single structured report, grouped by severity.

#### Severity Definitions

| Level | Name     | Action                  | Examples                                                                     |
|-------|----------|-------------------------|------------------------------------------------------------------------------|
| P0    | Critical | Must block merge        | Data race, SQL injection, goroutine leak, panic in prod, breaking proto change, migration drops column |
| P1    | High     | Should fix before merge | Swallowed error, missing auth check, N+1 query, no timeout, no graceful shutdown, wrong gRPC status code, large table full scan |
| P2    | Medium   | Fix or create follow-up | Naming violation, missing godoc, suboptimal pattern, no structured logging, missing metrics |
| P3    | Low      | Optional improvement    | Code style nit, minor simplification, additional test case                   |

#### Report Format

```markdown
# Go Code Review Report

**Date**: [YYYY-MM-DD HH:MM:SS]
**Mode**: Incremental (git changes) / Full Codebase
**Scope**: [file list or description]
**Verdict**: 🔴 Block / 🟡 Fix Before Merge / 🟢 Approve

[If Full Codebase mode, insert Architecture Overview section from Phase 5 here]

## Summary

| Category              | Findings | Highest Severity |
|-----------------------|----------|------------------|
| Style + SOLID         | N        | P?               |
| Removal Candidates    | N        | P?               |
| Security              | N        | P?               |
| Code Quality          | N        | P?               |
| Memory Leaks          | N        | P?               |
| Logging & Observability | N      | P?               |
| Lifecycle & Shutdown  | N        | P?               |
| API Contract          | N        | P?               |
| Database & Migration  | N        | P?               |

## P0 — Critical (Must Block Merge)

### [P0-01] Title
- **File**: `path/to/file.go:42`
- **Category**: Security / Concurrency / ...
- **Issue**: Clear description of the problem
- **Risk**: What can go wrong in production
- **Fix**:
​```go
// Before
<problematic code>

// After
<suggested fix>
​```

## P1 — High (Should Fix Before Merge)

### [P1-01] Title
- **File**: `path/to/file.go:88`
- **Category**: Error Handling / Performance / ...
- **Issue**: Description
- **Fix**: Suggested change

## P2 — Medium (Fix or Follow-up)

### [P2-01] Title
- **File**: `path/to/file.go:15`
- **Issue**: Description
- **Suggestion**: Improvement approach

## P3 — Low (Optional)

### [P3-01] Title
- **File**: `path/to/file.go:7`
- **Note**: Minor suggestion

## ✅ Good Practices Observed

- [Highlight well-written code patterns worth keeping]

## Action Checklist

1. [ ] 🔴 P0-01: ...
2. [ ] 🟠 P1-01: ...
3. [ ] 🟡 P2-01: ...
4. [ ] 🟢 P3-01: ...
```

### Step 7: Confirmation

After saving the report to `.claude/issues/<timestamp>.md`:

1. Print the saved file path to the user
2. Ask the user if they want to **auto-fix** any findings
3. If yes, only fix findings the user explicitly approves
4. Group fixes by file to minimize diff churn
5. After applying fixes, re-run a quick validation to ensure no regressions
6. Update the report file with fix status (append a `## Fix Log` section noting which issues were resolved)

## Review Principles

1. **Pragmatic over pedantic** — Focus on real impact. Working code with minor style issues is P3, not P1.
2. **Always provide a fix** — Every finding must include a concrete code suggestion, not just "this is wrong."
3. **Respect context** — Adjust strictness based on project stage (prototype vs production), team norms, and performance requirements.
4. **Acknowledge good code** — Positive feedback reinforces good practices.
5. **Don't manufacture issues** — If the code is solid, say so. A short report is a good report.
6. **Go proverbs apply** — "A little copying is better than a little dependency", "Don't just check errors, handle them gracefully", "The bigger the interface, the weaker the abstraction."