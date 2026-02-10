# Removal Plan Template

Guide for identifying and safely removing dead code, unused dependencies, and deprecated patterns in Go projects.

## Identification Prompts

### Dead Code Detection

Scan for the following categories:

1. **Unexported functions with zero callers**
   - Search for `func lowerCase(` definitions and verify usage with grep/IDE references
   - Exception: functions used via `reflect`, template actions, or test helpers

2. **Commented-out code blocks**
   - Any block of `// code` spanning 3+ lines
   - Commented-out imports
   - `/* ... */` blocks containing executable code

3. **Unused exports**
   - Exported functions/types not referenced outside their package
   - Exception: API handlers, wire providers, interface implementations

4. **Deprecated API usage**
   - `ioutil` package (deprecated since Go 1.16) → use `io` and `os`
   - `golang.org/x/net/context` → use `context` from stdlib
   - Old-style GORM v1 APIs if project uses GORM v2

5. **Orphaned test helpers**
   - Test utilities in `_test.go` files that are no longer called by any test

6. **Unused proto definitions**
   - Proto messages/RPCs defined but never referenced in service code

### Dependency Audit

- Unused entries in `go.mod` — run `go mod tidy` mentally
- Redundant indirect dependencies
- Libraries used for only one trivial function that could be replaced with stdlib

## Classification

For each removal candidate, classify:

### Safe to Remove

Criteria:
- Zero references in codebase (verified)
- No reflection-based access
- No external consumers (internal package or unexported)
- Not a wire provider

Action: Remove in this PR with brief comment explaining removal.

### Deferred Removal

Criteria:
- Possibly used via reflection, templates, or dynamic dispatch
- Exported from a shared library package
- Removed feature that may be re-enabled (check with team)

Action: Add `// Deprecated: <reason>. Remove after <date or milestone>.` annotation. Create follow-up ticket.

## Removal Plan Template

```markdown
### Removal: [description]

**Type**: Dead code / Deprecated API / Unused dependency
**Files affected**: [list]
**Classification**: Safe / Deferred

**Verification**:
- [ ] Grep confirms zero references
- [ ] No reflection-based access
- [ ] Not used in build tags or platform-specific code
- [ ] Tests pass after removal

**Rollback**: Revert commit [hash] if issues arise.
```

## Go-Specific Removal Patterns

### Replacing ioutil (Safe)

```go
// BEFORE
data, err := ioutil.ReadFile("config.yaml")
err := ioutil.WriteFile("out.txt", data, 0644)
tmpDir, err := ioutil.TempDir("", "prefix")

// AFTER
data, err := os.ReadFile("config.yaml")
err := os.WriteFile("out.txt", data, 0644)
tmpDir, err := os.MkdirTemp("", "prefix")
```

### Removing Global State (Deferred)

Global `var db *gorm.DB` patterns should be migrated to dependency injection, but require broader refactoring. Mark as deferred and plan migration.

### Removing Unused Wire Providers (Safe)

If a wire provider set includes functions no longer used by any injector, remove the provider function and update the provider set. Re-run `wire` to verify `wire_gen.go` still compiles.
