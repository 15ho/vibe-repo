---
name: kratos-tdd
description: >
  Test-Driven Development skill for Go Kratos microservices. Use when implementing any feature,
  bug fix, or refactoring in this project. Triggers on: "implement", "add feature", "fix bug",
  "refactor", "new endpoint", "add API", "write code", "develop", or any task that produces
  production Go code. Enforces strict Red-Green-Refactor cycle adapted for Kratos DDD layers
  (biz, data, service, server). Covers unit tests with hand-written mocks, integration tests
  with TestSuite/Redis, and E2E tests. Always use this skill before writing production code.
---

# Kratos TDD

Write the test first. Watch it fail. Write minimal code to pass.

**Core principle:** If you didn't watch the test fail, you don't know if it tests the right thing.

## The Iron Law

```
NO PRODUCTION CODE WITHOUT A FAILING TEST FIRST
```

Write code before the test? Delete it. Start over. No exceptions.

## Red-Green-Refactor Cycle

### RED - Write Failing Test

Write one minimal test demonstrating desired behavior.

```go
func TestSigningUsecase_RejectEmptyKeyID(t *testing.T) {
    repo := NewMockSessionRepo()
    engine := NewMockMPCEngine()
    uc := newTestSigningUsecase(repo, engine, nil)

    _, _, err := uc.InitiateSign(context.Background(), "", validHash, "req-1")

    require.Error(t, err)
    require.True(t, v1.IsKeyNotFound(err))
}
```

Requirements:
- One behavior per test
- Clear name: `Test<Unit>_<Scenario>` or `Test<Unit>_<Method>_<Scenario>`
- Use `testify/require` (not `assert`) — fail fast
- Real code paths, mocks only for external dependencies

### Verify RED - Watch It Fail (MANDATORY)

```bash
go test -v -run TestSigningUsecase_RejectEmptyKeyID ./internal/biz/...
```

Confirm:
- Test **fails** (not compile error)
- Failure is because feature is missing
- Not because of typos or wrong setup

Test passes immediately? You're testing existing behavior. Fix the test.

### GREEN - Minimal Code

Write the simplest code to make the test pass.

```go
func (uc *SigningUsecase) InitiateSign(ctx context.Context, keyID string, ...) (...) {
    if keyID == "" {
        return nil, nil, v1.ErrorKeyNotFound("key_id is required")
    }
    // ...existing logic
}
```

Don't add features, refactor other code, or "improve" beyond the test.

### Verify GREEN - Watch It Pass (MANDATORY)

```bash
go test -v -run TestSigningUsecase_RejectEmptyKeyID ./internal/biz/...
```

Then run all tests in the package:

```bash
go test -race ./internal/biz/...
```

All must pass. Other tests fail? Fix now.

### REFACTOR - Clean Up

After green only:
- Remove duplication
- Improve names
- Extract helpers

Keep tests green. Don't add behavior.

### Repeat

Next failing test for next behavior.

## Layer-by-Layer TDD Strategy

Follow the DDD onion architecture. Work inside-out: biz → data → service → server.

### Biz Layer (Business Logic)

Test file: `internal/biz/<feature>_test.go`

**Mock pattern** — hand-written mocks in `mock_test.go`:

```go
type MockSessionRepo struct {
    mu           sync.RWMutex
    sessions     map[string]*biz.SignSession
    CreateCalls  []CreateCall
    CreateErr    error
}

func NewMockSessionRepo() *MockSessionRepo {
    return &MockSessionRepo{sessions: make(map[string]*biz.SignSession)}
}

func (m *MockSessionRepo) Create(ctx context.Context, s *biz.SignSession) error {
    m.mu.Lock()
    defer m.mu.Unlock()
    m.CreateCalls = append(m.CreateCalls, CreateCall{Session: s})
    if m.CreateErr != nil {
        return m.CreateErr
    }
    m.sessions[s.ID] = s
    return nil
}
```

**Mock rules:**
- Thread-safe (`sync.RWMutex`)
- Track all calls for verification
- Support error injection
- Provide `Reset()` method
- Define in `mock_test.go` of the same package

**Test pattern:**

```go
func TestFeature_Success(t *testing.T) {
    // Arrange
    repo := NewMockSessionRepo()
    engine := NewMockMPCEngine()
    uc := newTestSigningUsecase(repo, engine, nil)

    // Act
    result, err := uc.DoSomething(ctx, input)

    // Assert
    require.NoError(t, err)
    require.Equal(t, expected, result)
    require.Len(t, repo.CreateCalls, 1) // verify interaction
}
```

### Data Layer (Repository Implementation)

Test file: `internal/data/<feature>_test.go`

Uses `TestSuite` with real or in-memory Redis:

```go
func TestSessionRepo_Create_Success(t *testing.T) {
    repo := newTestSessionRepo(t)
    ctx := context.Background()
    _ = testSuite.ClearRedis()

    session := &biz.SignSession{ID: "s-1", KeyID: "key-1"}
    err := repo.Create(ctx, session)
    require.NoError(t, err)

    got, err := repo.Get(ctx, "s-1")
    require.NoError(t, err)
    require.Equal(t, "s-1", got.ID)
}
```

Fallback: `fake_redis_test.go` provides `inMemoryRedis` when real Redis unavailable.

### Service Layer (gRPC Implementation)

Test file: `internal/service/<feature>_test.go`

Use testable wrapper with mock usecase injection:

```go
type testableSigningService struct {
    mockUC *MockSigningUsecase
    log    *log.Helper
}

func TestSigningService_InitiateSign_InvalidHash(t *testing.T) {
    mockUC := NewMockSigningUsecase()
    svc := &testableSigningService{mockUC: mockUC, log: log.NewHelper(log.DefaultLogger)}

    req := &v1.InitiateSignRequest{
        KeyId:       "key-1",
        MessageHash: make([]byte, 20), // wrong length
    }
    _, err := svc.InitiateSign(context.Background(), req)

    require.Error(t, err)
    require.True(t, v1.IsInvalidMessageHashLength(err))
}
```

### Server Layer (Middleware/Interceptor)

Test file: `internal/server/<feature>_test.go`

Mock transport interfaces:

```go
type mockLockChecker struct{ locked bool }
func (m *mockLockChecker) IsLocked() bool { return m.locked }

func TestLockCheckMiddleware_BlocksWhenLocked(t *testing.T) {
    checker := &mockLockChecker{locked: true}
    mw := LockCheckMiddleware(checker)
    handler := func(ctx context.Context, req interface{}) (interface{}, error) {
        return "ok", nil
    }
    tr := &mockTransporter{operation: "/signing.v1.SigningService/InitiateSign"}
    ctx := transport.NewServerContext(context.Background(), tr)

    _, err := mw(handler)(ctx, nil)
    require.Error(t, err)
}
```

### E2E Tests

Location: `tests/e2e/`

Build tag: `//go:build e2e`

```go
//go:build e2e

func TestNewFeature_E2E(t *testing.T) {
    WithTestSetup(t, func(t *testing.T) {
        ctx, cancel := context.WithTimeout(context.Background(), 120*time.Second)
        defer cancel()

        result, err := suite.GetCaller().DoSomething(ctx, input)
        require.NoError(t, err)
        require.NotNil(t, result)
    })
}
```

Run: `go test -v -race -tags e2e -timeout 300s ./tests/e2e/...`

Requires Redis on 127.0.0.1:6379. Uses isolated port (HTTP:18000, gRPC:19000) and DB 15.

## Table-Driven Tests

Use for multiple scenarios of the same behavior:

```go
func TestValidateMessageHash(t *testing.T) {
    tests := []struct {
        name    string
        hash    []byte
        wantErr bool
    }{
        {"valid 32 bytes", make([]byte, 32), false},
        {"too short", make([]byte, 20), true},
        {"too long", make([]byte, 64), true},
        {"empty", nil, true},
    }

    for _, tc := range tests {
        t.Run(tc.name, func(t *testing.T) {
            err := validateMessageHash(tc.hash)
            if tc.wantErr {
                require.Error(t, err)
            } else {
                require.NoError(t, err)
            }
        })
    }
}
```

## Running Tests

```bash
# Single test
go test -v -run TestName ./internal/biz/...

# Package tests
go test -race ./internal/biz/...

# All unit tests
go test -race ./...

# Full check (format + test + lint) — run before commit
make check

# E2E only
go test -v -race -tags e2e -timeout 300s ./tests/e2e/...
```

## Common Rationalizations (All Rejected)

| Excuse | Reality |
|--------|---------|
| "Too simple to test" | Simple code breaks. Test takes 30 seconds. |
| "I'll test after" | Tests passing immediately prove nothing. |
| "Already manually tested" | Ad-hoc != systematic. No record, can't re-run. |
| "Need to explore first" | Fine. Throw away exploration, start with TDD. |
| "Test hard = skip test" | Hard to test = hard to use. Listen to the test. |
| "Deleting work is wasteful" | Sunk cost fallacy. Keeping unverified code is debt. |

## Red Flags - STOP and Start Over

- Code before test
- Test passes immediately
- Can't explain why test failed
- Tests added "later"
- Rationalizing "just this once"
- "Keep code as reference"

**All mean: Delete code. Start over with TDD.**

## Verification Checklist

Before marking work complete:

- [ ] Every new function/method has a test
- [ ] Watched each test fail before implementing
- [ ] Each test failed for expected reason
- [ ] Wrote minimal code to pass each test
- [ ] All tests pass (`go test -race ./...`)
- [ ] Lint clean (`golangci-lint run ./...`)
- [ ] `make check` passes
- [ ] Mocks are hand-written, thread-safe, in `mock_test.go`
- [ ] Edge cases and error paths covered

## Kratos Conventions

When creating new files, adding endpoints, or implementing any layer, read @references/kratos-conventions.md for:
- Project layout and layer responsibilities (biz → data → service → server)
- Proto definition templates (service, messages, error reasons, HTTP annotations)
- Layer implementation patterns (ProviderSet, interface definition, factory functions)
- Wire dependency injection setup
- Import organization, logging, error handling, concurrency safety
- New feature checklist (proto → generate → biz → data → service → server → wire → test)

**Quick rules:**
- Biz defines interfaces, Data implements them (dependency inversion)
- Service embeds `v1.Unimplemented<X>Server`, defines its own usecase interface
- Data factory returns `(instance, cleanup, error)`, repo factory returns biz interface
- One `ProviderSet` per package, `wire.Bind` for interface→impl mapping
- Comments in English, imports in 3 groups (stdlib / third-party / local)
- Errors: `v1.ErrorXxx()` to create, `v1.IsXxx()` to check
- After `make api` or `make config`, never edit generated files

## Anti-Patterns

When writing tests with mocks, read @references/testing-anti-patterns.md to avoid:
- Testing mock behavior instead of real behavior
- Adding test-only methods to production code
- Mocking without understanding dependencies
- Incomplete mock data structures

## Wire Integration

After TDD produces working code, wire it up:

```bash
wire ./cmd/mpc-signing-service/...
```

Don't modify `wire_gen.go` manually. Update `wire.go` and ProviderSets instead.
