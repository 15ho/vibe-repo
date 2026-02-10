# Testing Anti-Patterns for Go Kratos Projects

**Load this reference when:** writing or changing tests, adding mocks, or tempted to add test-only methods to production code.

## Core Principle

Test what the code does, not what the mocks do. Mocks isolate; they are not the thing being tested.

## The Iron Laws

```
1. NEVER test mock behavior
2. NEVER add test-only methods to production structs
3. NEVER mock without understanding dependencies
4. NEVER use mockgen — hand-write mocks in mock_test.go
```

## Anti-Pattern 1: Testing Mock Behavior

**Bad:**
```go
func TestSigningUsecase_CallsRepo(t *testing.T) {
    repo := NewMockSessionRepo()
    uc := newTestSigningUsecase(repo, nil, nil)
    uc.InitiateSign(ctx, "key-1", hash, "req-1")
    // Only checking mock was called — proves nothing about business logic
    require.Len(t, repo.CreateCalls, 1)
}
```

**Good:**
```go
func TestSigningUsecase_CreatesValidSession(t *testing.T) {
    repo := NewMockSessionRepo()
    uc := newTestSigningUsecase(repo, engine, nil)

    session, _, err := uc.InitiateSign(ctx, "key-1", hash, "req-1")

    require.NoError(t, err)
    require.Equal(t, "key-1", session.KeyID)
    require.NotEmpty(t, session.ID)
    // Verify interaction as secondary assertion
    require.Equal(t, session.ID, repo.CreateCalls[0].Session.ID)
}
```

**Rule:** Assert on behavior first, verify mock interactions second (if at all).

## Anti-Pattern 2: Test-Only Methods in Production

**Bad:**
```go
// internal/biz/mpc_engine.go
func (e *MPCEngineImpl) ResetForTesting() {
    e.sessions = make(map[string]*tssSession)
}
```

**Good:**
```go
// internal/biz/mpc_engine_test.go
func newCleanEngine() *MPCEngineImpl {
    return NewMPCEngineImpl(log.DefaultLogger) // fresh instance per test
}
```

**Rule:** Create fresh instances per test instead of adding reset/destroy methods to production code.

## Anti-Pattern 3: Mocking Without Understanding

**Bad:**
```go
func TestUnlock_Success(t *testing.T) {
    // Mocks KeyShareLoader.LoadEncrypted but doesn't understand
    // that UnlockManager also checks IsLocked() state
    loader := &MockKeyShareLoader{LoadErr: nil}
    mgr := newTestUnlockManager(loader)

    err := mgr.Unlock(ctx, "password")
    // Fails mysteriously because IsLocked() check wasn't considered
}
```

**Good:**
```go
func TestUnlock_Success(t *testing.T) {
    loader := &MockKeyShareLoader{}
    loader.AddShare("share_1", testShareData)
    mgr := newTestUnlockManager(loader)
    // Ensure locked state first
    require.True(t, mgr.IsLocked())

    err := mgr.Unlock(ctx, "password")
    require.NoError(t, err)
    require.False(t, mgr.IsLocked())
}
```

**Before mocking, answer:**
1. What side effects does the real method have?
2. Does this test depend on any of those side effects?
3. What state preconditions are needed?

## Anti-Pattern 4: Incomplete Mock Data

**Bad:**
```go
mockUC.sessions["s-1"] = &biz.SignSession{
    ID: "s-1",
    // Missing: KeyID, Status, MessageHash, CreatedAt
    // Downstream code panics on nil access
}
```

**Good:**
```go
mockUC.sessions["s-1"] = &biz.SignSession{
    ID:          "s-1",
    KeyID:       "key-1",
    Status:      v1.SessionStatus_PENDING,
    MessageHash: validHash,
    CreatedAt:   time.Now(),
}
```

**Rule:** Mirror the complete data structure as it exists in reality.

## Anti-Pattern 5: Over-Mocking (Mock Everything)

**Bad:**
```go
func TestSessionRepo_Create(t *testing.T) {
    mockRedis := NewMockRedisClient()
    mockRedis.SetResult = "OK"
    repo := &sessionRepo{rdb: mockRedis}

    err := repo.Create(ctx, session)
    require.NoError(t, err)
    // You're testing your mock Redis, not the real serialization/storage logic
}
```

**Good:**
```go
func TestSessionRepo_Create(t *testing.T) {
    // Use real Redis (via TestSuite) or inMemoryRedis for data layer
    repo := newTestSessionRepo(t)
    _ = testSuite.ClearRedis()

    err := repo.Create(ctx, session)
    require.NoError(t, err)

    got, err := repo.Get(ctx, session.ID)
    require.NoError(t, err)
    require.Equal(t, session.KeyID, got.KeyID)
}
```

**Rule:** Data layer tests should use real storage (Redis/inMemoryRedis via TestSuite). Mock at the layer boundary, not inside it.

## Anti-Pattern 6: gRPC Mock Without Proto Validation

**Bad:**
```go
func TestService_InitiateSign(t *testing.T) {
    // Skips proto validation that would catch invalid requests in production
    svc := &signingService{uc: mockUC}
    resp, err := svc.InitiateSign(ctx, &v1.InitiateSignRequest{})
    require.Error(t, err) // might pass for wrong reason
}
```

**Good:**
```go
func TestService_InitiateSign_MissingKeyID(t *testing.T) {
    svc := &testableSigningService{mockUC: mockUC, log: logHelper}

    req := &v1.InitiateSignRequest{
        KeyId:       "", // explicitly empty
        MessageHash: make([]byte, 32),
    }
    _, err := svc.InitiateSign(ctx, req)

    require.Error(t, err)
    require.True(t, v1.IsKeyNotFound(err))
}
```

**Rule:** Test with explicit invalid values, not zero-value structs. Verify specific error types using generated error helpers.

## Mock Design Checklist

Hand-written mock in `mock_test.go` must have:

- [ ] `sync.RWMutex` for thread safety
- [ ] Call tracking slices (e.g., `CreateCalls []CreateCall`)
- [ ] Error injection fields (e.g., `CreateErr error`)
- [ ] Constructor function (e.g., `NewMockSessionRepo()`)
- [ ] `Reset()` method to clear state between tests
- [ ] Complete interface implementation (all methods)

## Quick Reference

| Anti-Pattern | Fix |
|--------------|-----|
| Assert only on mock calls | Assert on behavior first |
| Test-only methods in prod | Fresh instances per test |
| Mock without understanding | Understand side effects first |
| Incomplete mock data | Mirror complete real structures |
| Mock Redis in data layer | Use TestSuite/inMemoryRedis |
| Zero-value proto requests | Explicit invalid values |

## Red Flags

- Mock setup is >50% of test body
- Test fails when you remove a mock
- Can't explain why mock is needed
- Mocking "just to be safe"
- Using `interface{}` or `any` in mock signatures
- Generated mocks (mockgen/gomock) — hand-write instead

## TDD Prevents These

Write test first → forces you to think about what you're testing.
Watch it fail → confirms test tests real behavior, not mocks.
Minimal implementation → no test-only methods creep in.

If you're testing mock behavior, you violated TDD.
