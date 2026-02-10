# Go Style + SOLID Checklist

Detailed prompts for detecting idiomatic Go violations, SOLID principle breaches, and architecture smells. Apply each section against the scoped code.

## Table of Contents

1. [Idiomatic Go Style](#idiomatic-go-style)
2. [SOLID Principles](#solid-principles)
3. [Kratos Architecture](#kratos-architecture)
4. [Common Code Smells](#common-code-smells)

---

## Idiomatic Go Style

### Naming

- **Packages**: lowercase, single word, no underscores. `httputil` not `http_util`.
- **Exported symbols**: `PascalCase`. Every exported symbol MUST have a godoc comment.
- **Unexported symbols**: `camelCase`. No stuttering — `http.Server` not `http.HTTPServer`.
- **Interfaces**: name by behavior with `-er` suffix when single method. `Reader`, `Writer`, `Closer`. Multi-method interfaces use descriptive nouns: `FileSystem`, `Repository`.
- **Getters**: no `Get` prefix. Use `user.Name()` not `user.GetName()`. Exception: gRPC generated code.
- **Acronyms**: all caps — `ID`, `HTTP`, `URL`, `API`. Not `Id`, `Http`.
- **Error variables**: `err` prefix for sentinel errors — `ErrNotFound`, `ErrTimeout`.
- **Boolean**: prefer positive — `isValid` over `isNotInvalid`.

**Anti-pattern prompt**: Scan for stuttering names (e.g., `user.UserName`), `Get` prefixed methods, lowercase acronyms, packages named `util`/`common`/`helper`/`misc`.

### Package Design

- Each package has a **single, clear purpose**.
- No circular imports.
- Internal packages (`internal/`) for implementation details.
- Avoid `package main` logic leaking into reusable code.
- `cmd/` for entry points only — minimal code, wire up dependencies, start servers.

**Anti-pattern prompt**: Look for packages with mixed responsibilities, packages importing each other, business logic in `cmd/`, catch-all `utils` packages.

### Interface Usage

- Define interfaces **at the consumer site**, not the implementation site.
- Keep interfaces small: 1–3 methods preferred.
- Accept interfaces, return concrete types.
- Do NOT create interfaces preemptively "for testing" — only abstract when there are multiple implementations or a genuine need to decouple.

**Anti-pattern prompt**: Scan for large interfaces (>5 methods), interfaces defined next to their only implementation, interfaces matching 1:1 with a struct's methods.

### Error Handling Patterns

- Always handle errors immediately after the call.
- Wrap errors with context: `fmt.Errorf("create user: %w", err)`.
- Use `errors.Is()` and `errors.As()` for error inspection.
- Define sentinel errors for expected conditions: `var ErrNotFound = errors.New("not found")`.
- Return `error` as the last return value.
- Do NOT use `panic` in library/business code — only in `main()` or truly unrecoverable init failures.

**Anti-pattern prompt**: Look for `_ = fn()`, bare `return err` without wrapping, `log.Fatal` in non-main packages, panic in request handlers, `if err != nil { return err }` chains without context.

### Concurrency Patterns

- Always pass `context.Context` as the first parameter.
- Do NOT store `context.Context` in a struct.
- Use `errgroup.Group` for coordinating goroutines.
- Every goroutine must have a clear exit path — no fire-and-forget unless genuinely intended.
- Prefer channels for communication, mutexes for state protection.

**Anti-pattern prompt**: Scan for `context.Context` in struct fields, goroutines without exit conditions, `go func()` without error propagation, `sync.WaitGroup` used where `errgroup` would be better.

---

## SOLID Principles

### S — Single Responsibility Principle

A struct/package should have one reason to change.

**Smell prompts**:
- Struct has >7 methods spanning multiple domains (e.g., handles both HTTP parsing and DB queries)
- Function >80 lines or >4 levels of nesting
- A single file >500 lines
- Package has imports from 3+ unrelated domains

### O — Open/Closed Principle

Extend behavior through composition and interfaces, not modification.

**Smell prompts**:
- `switch` or `if/else` chains on type tags that grow with each new feature
- Functions taking boolean flags that fundamentally change behavior
- Adding a feature requires modifying 3+ existing files

### L — Liskov Substitution Principle

Interface implementations must be interchangeable.

**Smell prompts**:
- Interface method implementation that panics or returns `ErrNotImplemented`
- Implementation that ignores interface method parameters
- Subtypes that add preconditions not in the interface contract

### I — Interface Segregation Principle

No client should be forced to depend on methods it doesn't use.

**Smell prompts**:
- Interfaces with >5 methods
- Functions receiving a large interface but only calling 1-2 methods
- "God interfaces" that combine unrelated capabilities

### D — Dependency Inversion Principle

High-level modules should not depend on low-level modules. Both should depend on abstractions.

**Smell prompts**:
- Business logic (`biz/`) importing infrastructure packages directly (`data/`, `pkg/database`)
- Constructor directly instantiating dependencies instead of accepting interfaces
- No dependency injection — hard-wired `sql.Open()` or `redis.NewClient()` in business code

---

## Kratos Architecture

### Layer Separation

Kratos follows a clean architecture pattern:

```
api/        → Proto definitions, generated code
cmd/        → Entry point, wire injection
configs/    → Configuration files
internal/
  biz/      → Business logic, domain entities, use cases
  data/     → Data access, repository implementations
  service/  → gRPC/HTTP service implementations (transport layer)
  server/   → Server setup (HTTP, gRPC)
```

**Checklist**:
- [ ] `service/` (transport) only handles request/response mapping — no business logic
- [ ] `biz/` contains domain logic and defines repository interfaces
- [ ] `data/` implements `biz/` repository interfaces — `biz/` never imports `data/`
- [ ] Domain models in `biz/` are separate from GORM models in `data/`
- [ ] Proto-generated types do NOT leak into `biz/` layer
- [ ] Dependency flow: `service → biz → data` (never reversed)

**Anti-pattern prompt**: Scan for `biz/` importing `data/`, service handlers with SQL queries, GORM models used as domain entities, business logic in `service/` layer.

### Wire Dependency Injection

- [ ] All dependencies injected via constructors — no global state
- [ ] `wire.go` files define provider sets per layer
- [ ] `wire_gen.go` is auto-generated — never manually edited

**Anti-pattern prompt**: Look for `init()` functions that create global singletons, manual dependency construction in `main()` without wire, global `var db *gorm.DB`.

### Kratos Middleware

- [ ] Standard middleware chain: recovery → logging → tracing → metrics → auth
- [ ] Custom middleware follows `middleware.Middleware` signature
- [ ] Error responses use Kratos error types with proper codes

### Config Management

- [ ] Configs loaded via Kratos `config` package
- [ ] Sensitive values from environment variables or secret managers, not hardcoded
- [ ] Config changes handled gracefully (hot reload or restart)

---

## Common Code Smells

| Smell | Description | Go-specific indicator |
|-------|-------------|----------------------|
| **God struct** | One struct does everything | >10 fields, >10 methods |
| **Feature envy** | Method uses another struct's data more than its own | Excessive field access on passed-in structs |
| **Shotgun surgery** | One change requires modifying many files | Adding an API field touches >5 files |
| **Primitive obsession** | Using `string`/`int` where a domain type fits | User IDs as `string`, money as `float64` |
| **Long parameter list** | Function with >5 parameters | Should use an options struct or functional options |
| **Deep nesting** | >3 levels of indentation | Extract early returns or helper functions |
| **Boolean blindness** | Functions with boolean params | `CreateUser(name, true, false)` — use options or separate functions |
| **Copy-paste** | Duplicated blocks of logic | Extract shared function or use generics |
