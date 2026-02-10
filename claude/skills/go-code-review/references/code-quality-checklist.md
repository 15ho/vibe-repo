# Go Code Quality Checklist

Error handling, performance, boundary conditions, and testing quality prompts specific to Go, gRPC, GORM, and Kratos.

## Table of Contents

1. [Error Handling](#error-handling)
2. [Performance](#performance)
3. [Boundary Conditions](#boundary-conditions)
4. [Testing Quality](#testing-quality)
5. [Memory Leak Patterns](#memory-leak-patterns)
6. [Logging & Observability](#logging--observability)
7. [Graceful Shutdown & Lifecycle](#graceful-shutdown--lifecycle)
8. [API Contract Quality](#api-contract-quality)
9. [Database & Migration Safety](#database--migration-safety)

---

## Error Handling

### Swallowed Errors (P1)

- **Detect**: Error return values assigned to `_` or not checked
- **Prompt**: Scan for `_ = someFunc()`, `someFunc()` on a line by itself when the function returns error, `defer file.Close()` without checking close error on write operations.
- **Fix**: Handle every error. For deferred closes on write, use named returns.

```go
// BAD
_ = json.Unmarshal(data, &v)

// GOOD
if err := json.Unmarshal(data, &v); err != nil {
    return fmt.Errorf("unmarshal config: %w", err)
}
```

### Missing Error Context (P2)

- **Detect**: `return err` without wrapping, losing call-site context
- **Prompt**: Look for `return err` that doesn't add context via `fmt.Errorf("...: %w", err)`. Multiple layers of bare `return err` make debugging impossible.
- **Fix**: Wrap errors at each layer boundary with descriptive context

```go
// BAD
func GetUser(id string) (*User, error) {
    user, err := repo.Find(id)
    if err != nil {
        return nil, err  // no context about what failed
    }
    return user, nil
}

// GOOD
func GetUser(id string) (*User, error) {
    user, err := repo.Find(id)
    if err != nil {
        return nil, fmt.Errorf("get user %s: %w", id, err)
    }
    return user, nil
}
```

### Improper Error Type Usage (P2)

- **Detect**: String comparison on errors instead of `errors.Is`/`errors.As`
- **Prompt**: Scan for `err.Error() == "..."`, `strings.Contains(err.Error(), ...)`. Check for custom error types that don't implement `Unwrap()`.
- **Fix**: Use sentinel errors with `errors.Is()`, custom error types with `errors.As()`

### Panic in Request Handlers (P0)

- **Detect**: `panic()` in HTTP/gRPC handlers or business logic
- **Prompt**: Scan for `panic()` calls outside of `main()`, `init()`, or truly unrecoverable situations. Check that recovery middleware is in place.
- **Fix**: Return errors, use recovery middleware as safety net

### Log.Fatal in Library Code (P1)

- **Detect**: `log.Fatal` or `os.Exit` in non-main packages
- **Prompt**: These terminate the process immediately without cleanup or deferred function execution. Only acceptable in `main()`.
- **Fix**: Return errors to callers, let `main()` decide on exit

---

## Performance

### N+1 Query Problem (P1)

- **Detect**: DB query inside a loop, loading associations one by one
- **Prompt**: Look for patterns like `for _, item := range items { db.Find(&related, item.ID) }`. Check GORM usage for missing `Preload()` or `Joins()`.
- **Fix**: Use GORM `Preload`, `Joins`, or batch queries

```go
// BAD: N+1 queries
for _, order := range orders {
    db.Where("order_id = ?", order.ID).Find(&order.Items)
}

// GOOD: eager loading
db.Preload("Items").Find(&orders)
```

### Unnecessary Memory Allocation (P2)

- **Detect**: Allocations in hot paths that could be avoided
- **Prompt**: Check for:
  - Slice created without capacity hint: `make([]T, 0)` → `make([]T, 0, expectedLen)`
  - String concatenation in loops: use `strings.Builder`
  - `fmt.Sprintf` for simple conversions: use `strconv`
  - Pointer to small value types where value semantics suffice
  - Creating objects inside loops that could be reused

```go
// BAD
var result string
for _, s := range items {
    result += s + ","
}

// GOOD
var b strings.Builder
for _, s := range items {
    b.WriteString(s)
    b.WriteByte(',')
}
result := b.String()
```

### Reflection in Hot Paths (P2)

- **Detect**: `reflect` package used in request-handling code
- **Prompt**: Scan for `reflect.ValueOf`, `reflect.TypeOf` in handler/service code. Reflection is 10-100x slower than direct calls.
- **Fix**: Use type switches, generics, or code generation instead

### Missing sync.Pool (P3)

- **Detect**: Frequent allocation and discard of large, uniform objects
- **Prompt**: Look for `bytes.Buffer`, `[]byte` slices, or encoder/decoder objects created per-request that could be pooled
- **Fix**: Use `sync.Pool` for frequently allocated temporary objects

### GORM Performance (P1)

- **Detect**: GORM patterns that cause performance issues
- **Prompt**: Check for:
  - `SELECT *` when only a few fields needed → use `Select("id", "name")`
  - Missing batch operations → use `CreateInBatches` for bulk inserts
  - Missing connection pool config → set `MaxIdleConns`, `MaxOpenConns`, `ConnMaxLifetime`
  - `AutoMigrate` in production code → should only run in dev/migration scripts
  - Missing database indexes for query patterns

### GORM Large Table Awareness (P1)

Tables grow over time. Patterns that work at 10K rows fail catastrophically at 10M+. Review every GORM query with the question: **"What happens when this table has 10 million rows?"**

- **Detect**: Queries that will degrade as data volume grows
- **Prompt**: Check for:

**Indexing issues**:
  - `WHERE` clauses on columns without indexes
  - Composite queries where index column order doesn't match query order
  - `LIKE '%keyword%'` (leading wildcard defeats index) — consider full-text search
  - `ORDER BY` on non-indexed columns in large result sets
  - Unique constraints missing where business logic assumes uniqueness

```go
// BAD: no index on status + created_at, will full-scan at scale
db.Where("status = ? AND created_at > ?", status, since).Find(&orders)

// GOOD: ensure composite index exists
// CREATE INDEX idx_orders_status_created ON orders(status, created_at)
```

**Pagination traps**:
  - `OFFSET`-based pagination on large tables → degrades linearly. At offset=100000, DB still scans 100K rows to skip them
  - Fix: Use cursor-based (keyset) pagination with indexed column

```go
// BAD: O(offset) performance
db.Offset(page * size).Limit(size).Find(&items)

// GOOD: cursor-based, O(1) seek
db.Where("id > ?", lastID).Order("id ASC").Limit(size).Find(&items)
```

**Unbounded queries**:
  - `db.Find(&allRecords)` without `Limit` — will OOM on large tables
  - `db.Count(&count)` on large tables without index — full table scan
  - Missing pagination on list APIs — a single request returns millions of rows
  - Fix: Always enforce `Limit`, use `COUNT` with indexed columns or approximate counts

**Soft delete pitfalls**:
  - GORM soft delete adds `WHERE deleted_at IS NULL` to every query — if 90% of rows are soft-deleted, the index is useless
  - Fix: Consider partial index `WHERE deleted_at IS NULL`, or archive/purge deleted rows

**Join & subquery on large tables**:
  - Joining two large tables without proper indexes → full scan × full scan
  - `WHERE id IN (SELECT ...)` subqueries that return huge result sets
  - Fix: Verify EXPLAIN plan, add indexes on join columns, consider denormalization for read-heavy paths

**Schema evolution awareness**:
  - Will this column eventually need sharding or partitioning?
  - Is `created_at` indexed for time-range queries that will be the primary access pattern at scale?
  - Should this be a separate table rather than adding more columns to an already wide table?
  - Are `TEXT`/`JSON` columns bloating row size and slowing scans?

---

## Boundary Conditions

### Nil Pointer Dereference (P0)

- **Detect**: Using pointers, interfaces, maps, or slices without nil checks
- **Prompt**: Scan for:
  - Function returning `(*T, error)` where caller uses `result.Field` without checking error first
  - Interface values used without nil check
  - Map access without checking if map is initialized
  - Optional proto message fields accessed without nil guard
  - Type assertions without comma-ok: `v := i.(Type)` → should be `v, ok := i.(Type)`

```go
// BAD
resp, err := client.Do(req)
defer resp.Body.Close()  // panic if err != nil

// GOOD
resp, err := client.Do(req)
if err != nil {
    return fmt.Errorf("http request: %w", err)
}
defer resp.Body.Close()
```

### Empty Collection Handling (P1)

- **Detect**: Operations on slices/maps that may be empty
- **Prompt**: Check for `items[0]` without length check, `range` over nil map (safe, but intent may be wrong), returning nil slice vs empty slice inconsistently.
- **Fix**: Check length before index access, be consistent about nil vs empty returns

### Integer Overflow (P2)

- **Detect**: Arithmetic on user-supplied integers without bounds checking
- **Prompt**: Look for unchecked `int32` → `int16` conversions, multiplication without overflow check, `time.Duration` constructed from user input (can overflow on large values).
- **Fix**: Validate ranges, use `math.MaxInt32` checks before casting

### Off-by-One (P2)

- **Detect**: Loop bounds, slice indexing, pagination calculations
- **Prompt**: Check `for i := 0; i <= len(s)` (should be `<`), `s[len(s)]` (out of bounds), pagination with `offset = page * size` vs `offset = (page-1) * size`.
- **Fix**: Verify loop bounds and slice indices against actual use

### Resource Leaks (P1)

- **Detect**: Opened resources not properly closed
- **Prompt**: Check for:
  - `os.Open` / `os.Create` without `defer f.Close()`
  - `http.Get` response body not closed
  - `sql.Rows` not closed
  - `gRPC` streams not closed
  - `context.WithCancel`/`WithTimeout` without calling cancel
- **Fix**: Always `defer` close/cancel immediately after creation, before error checks on usage

```go
// BAD: cancel never called if function returns early
ctx, cancel := context.WithTimeout(parent, 5*time.Second)
result, err := doWork(ctx)
if err != nil {
    return err  // cancel leaked!
}
cancel()

// GOOD: defer cancel immediately
ctx, cancel := context.WithTimeout(parent, 5*time.Second)
defer cancel()
result, err := doWork(ctx)
```

---

## Testing Quality

### Missing Test Coverage (P2)

- **Detect**: Changed/added code without corresponding tests
- **Prompt**: For each new exported function or method, verify a test exists. For bug fixes, verify a regression test that reproduces the original bug.
- **Fix**: Add tests following Go conventions: `func TestXxx(t *testing.T)`

### Test Isolation (P1)

- **Detect**: Tests depending on external state, ordering, or shared mutable state
- **Prompt**: Check for:
  - Tests using real databases without cleanup
  - Global variable mutation in tests
  - Tests that fail when run in parallel
  - `TestMain` that sets up state not properly torn down
- **Fix**: Use test fixtures, `t.Cleanup()`, `t.Parallel()`, test containers

### Table-Driven Tests (P3)

- **Detect**: Repetitive test cases that could be consolidated
- **Prompt**: Look for multiple test functions testing the same function with different inputs. If >3 similar test cases exist, suggest table-driven pattern.
- **Fix**: Use `[]struct{ name string; input X; want Y }` pattern with `t.Run`

```go
// GOOD: table-driven
tests := []struct {
    name    string
    input   string
    want    int
    wantErr bool
}{
    {"valid", "42", 42, false},
    {"empty", "", 0, true},
    {"negative", "-1", -1, false},
}
for _, tt := range tests {
    t.Run(tt.name, func(t *testing.T) {
        got, err := Parse(tt.input)
        if (err != nil) != tt.wantErr {
            t.Errorf("Parse(%q) error = %v, wantErr %v", tt.input, err, tt.wantErr)
        }
        if got != tt.want {
            t.Errorf("Parse(%q) = %v, want %v", tt.input, got, tt.want)
        }
    })
}
```

### Mockability (P2)

- **Detect**: External dependencies not mockable in tests
- **Prompt**: Verify that repository interfaces, HTTP clients, and external service clients are injected as interfaces. Check if `biz/` tests can run without real DB.
- **Fix**: Accept interfaces in constructors, create mock implementations for testing

---

## Memory Leak Patterns

Go-specific memory leaks are subtle because the GC handles most cleanup. These patterns cause memory to grow unboundedly even with a working GC.

### time.After in Loops (P0)

- **Detect**: `time.After()` called inside `for/select` loops
- **Prompt**: Each `time.After` creates a timer that is NOT garbage collected until it fires. In a tight loop, this leaks timers.
- **Fix**: Use `time.NewTimer` with `Reset()`, or `time.NewTicker`

```go
// BAD: leaks a timer every iteration
for {
    select {
    case msg := <-ch:
        handle(msg)
    case <-time.After(5 * time.Second):
        handleTimeout()
    }
}

// GOOD: reuse timer
timer := time.NewTimer(5 * time.Second)
defer timer.Stop()
for {
    timer.Reset(5 * time.Second)
    select {
    case msg := <-ch:
        handle(msg)
    case <-timer.C:
        handleTimeout()
    }
}
```

### Ticker Not Stopped (P0)

- **Detect**: `time.NewTicker` without corresponding `Stop()`
- **Prompt**: Scan for `time.NewTicker` and verify every instance has `defer ticker.Stop()` or is stopped on context cancellation.
- **Fix**: Always `defer ticker.Stop()` immediately after creation

### Subslice Reference to Large Array (P1)

- **Detect**: Small slice derived from a large slice/array, keeping the entire backing array alive
- **Prompt**: Look for patterns where a large `[]byte` (e.g., file content, HTTP body) is sliced and the small subslice is stored long-term.
- **Fix**: Copy the needed portion into a new slice

```go
// BAD: holds entire 1MB backing array in memory
data := readLargeFile() // 1MB
header = data[:64]      // only need 64 bytes, but 1MB stays alive

// GOOD: copy to release backing array
header = make([]byte, 64)
copy(header, data[:64])
```

### Unclosed Channels Blocking Goroutines (P0)

- **Detect**: Goroutines blocked on channel send/receive with no exit path
- **Prompt**: For every channel, verify: (a) all senders will eventually close or stop sending, (b) all receivers will eventually drain or stop receiving, (c) context cancellation can unblock the goroutine.
- **Fix**: Use buffered channels where appropriate, `select` with `ctx.Done()`, or ensure channel lifecycle matches goroutine lifecycle

### String Interning Leak (P2)

- **Detect**: Holding references to substrings of large strings
- **Prompt**: In Go, `s[i:j]` shares the underlying string memory. If `s` is a 10MB HTTP response body and you keep `s[0:10]`, the whole 10MB stays alive.
- **Fix**: Use `strings.Clone()` (Go 1.20+) or `string([]byte(s[0:10]))` to copy

### Finalizer Misuse (P2)

- **Detect**: `runtime.SetFinalizer` used for resource cleanup
- **Prompt**: Finalizers are not guaranteed to run, can delay GC, and can resurrect objects. They should NOT be the primary cleanup mechanism.
- **Fix**: Use explicit `Close()` methods with `defer`, context cancellation, or `io.Closer` interfaces

---

## Logging & Observability

### Structured Logging (P2)

- **Detect**: Unstructured log output — `fmt.Println`, `log.Printf` with format strings
- **Prompt**: All production services should use structured logging (Kratos `log`, `zerolog`, `zap`, `slog`). Scan for `fmt.Print*` and stdlib `log.*` in non-test code.
- **Fix**: Use the project's structured logger with typed fields

```go
// BAD
log.Printf("user %s created order %d", userID, orderID)

// GOOD (Kratos log)
log.Infow("order created", "user_id", userID, "order_id", orderID)
```

### Log Level Discipline (P2)

- **Detect**: Incorrect log level usage
- **Prompt**: Check for:
  - `Error` level for non-errors (e.g., "user not found" in a search endpoint is not an error)
  - `Info` level for high-frequency per-request debug data (will flood logs in production)
  - `Debug` data left enabled in production code paths
  - Missing `Error` log when actually swallowing errors
- **Guidelines**:
  - `Error`: Something is broken and needs attention
  - `Warn`: Unexpected but handled situation
  - `Info`: Significant business events (user created, order placed)
  - `Debug`: Diagnostic data for development

### Sensitive Data in Logs (P0)

- **Detect**: Passwords, tokens, PII, credit card numbers, full request bodies logged
- **Prompt**: Scan log statements for `%+v` on request/user structs, fields named `password`, `token`, `secret`, `ssn`, `credit_card`. Check gRPC/HTTP interceptor logging for full payload dumps.
- **Fix**: Use field allowlists in log interceptors, redact sensitive fields, never log auth headers

### Trace Context Propagation (P1)

- **Detect**: Missing or broken distributed tracing
- **Prompt**: Verify:
  - Kratos tracing middleware is in the middleware chain
  - `context.Context` is passed through all layers (not `context.Background()` mid-chain)
  - Outgoing HTTP/gRPC calls propagate trace headers
  - DB queries include trace context (GORM plugin or manual span)
- **Fix**: Ensure Kratos `tracing.Server()` / `tracing.Client()` middleware, pass `ctx` everywhere

### Metrics Exposure (P2)

- **Detect**: No Prometheus/metrics endpoint, or critical operations unmeasured
- **Prompt**: Check for:
  - Missing request duration, error rate, and throughput metrics
  - No metrics on external dependency calls (DB, Redis, HTTP clients)
  - Custom business metrics absent (e.g., orders per minute)
- **Fix**: Use Kratos metrics middleware, add custom counters/histograms for key operations

### Health Check Endpoints (P2)

- **Detect**: No health/readiness probes
- **Prompt**: Verify liveness and readiness endpoints exist. Readiness should check downstream dependencies (DB connection, Redis, etc.).
- **Fix**: Implement `/healthz` (liveness) and `/readyz` (readiness) endpoints

---

## Graceful Shutdown & Lifecycle

### Signal Handling (P1)

- **Detect**: Process does not handle SIGTERM/SIGINT gracefully
- **Prompt**: Verify that the `main()` function or Kratos `App` captures OS signals and initiates graceful shutdown. Look for `os.Exit(0)` or `log.Fatal` that would bypass cleanup.
- **Fix**: Use Kratos `kratos.New(...).Run()` which handles signals, or manual `signal.NotifyContext`

```go
// GOOD: Kratos handles lifecycle
app := kratos.New(
    kratos.Name(Name),
    kratos.Server(httpServer, grpcServer),
)
if err := app.Run(); err != nil {
    log.Fatal(err)
}
```

### In-Flight Request Draining (P1)

- **Detect**: Server stops accepting new requests but doesn't wait for in-flight requests to complete
- **Prompt**: Check if HTTP/gRPC servers use graceful stop. For Kratos, verify `grpc.Server` uses `GracefulStop()` not `Stop()`. For HTTP, verify `Shutdown(ctx)` not `Close()`.
- **Fix**: Use server's graceful shutdown method with a deadline context

### Background Goroutine Cleanup (P1)

- **Detect**: Background workers (cron jobs, watchers, consumers) not stopped on shutdown
- **Prompt**: Scan for `go func()` launched during initialization. Verify each has a cancellation mechanism tied to the application's root context or shutdown signal.
- **Fix**: Use a lifecycle-managed context. In Kratos, register cleanup via `kratos.AfterStop()`

```go
// BAD: goroutine runs forever, orphaned on shutdown
go func() {
    for {
        processQueue()
        time.Sleep(time.Second)
    }
}()

// GOOD: respects cancellation
go func() {
    ticker := time.NewTicker(time.Second)
    defer ticker.Stop()
    for {
        select {
        case <-ticker.C:
            processQueue()
        case <-ctx.Done():
            return
        }
    }
}()
```

### Resource Cleanup Order (P1)

- **Detect**: Resources cleaned up in wrong order (e.g., DB closed before in-flight requests finish)
- **Prompt**: Check that shutdown order is reverse of startup: stop accepting requests → drain in-flight → close background workers → close DB/Redis/MQ connections.
- **Fix**: Use Kratos `AfterStop` hooks in correct order, or explicit sequencing in `main()`

### Connection Pool Shutdown (P2)

- **Detect**: DB/Redis/MQ connection pools not explicitly closed on shutdown
- **Prompt**: Verify `sqlDB.Close()` (from `db.DB()`), Redis client `Close()`, MQ consumer `Close()` are called during shutdown.
- **Fix**: Register cleanup in Kratos lifecycle or `defer` in `main()`

---

## API Contract Quality

### gRPC Status Code Correctness (P1)

- **Detect**: Incorrect or lazy gRPC status code usage
- **Prompt**: Scan for:
  - `codes.Internal` used as catch-all → should be specific: `NotFound`, `InvalidArgument`, `PermissionDenied`, etc.
  - `codes.OK` returned with error message
  - Business errors returned as `codes.Unknown`
  - `codes.Unavailable` for non-transient errors (should be for load balancer retry signals only)
- **Guidelines**:

| Situation | Correct Code |
|-----------|-------------|
| Resource not found | `codes.NotFound` |
| Invalid request field | `codes.InvalidArgument` |
| Auth token missing/invalid | `codes.Unauthenticated` |
| No permission | `codes.PermissionDenied` |
| Duplicate resource | `codes.AlreadyExists` |
| Rate limited | `codes.ResourceExhausted` |
| Unimplemented endpoint | `codes.Unimplemented` |
| Downstream service failed | `codes.Unavailable` |
| Bug / unexpected state | `codes.Internal` |

### Kratos Error Code Consistency (P1)

- **Detect**: Inconsistent error handling between Kratos error types and gRPC status codes
- **Prompt**: Check if project defines errors via proto `errors` option or Kratos `errors.New()`. Verify:
  - Error reasons are defined in proto, not hardcoded strings
  - HTTP and gRPC error codes map correctly (e.g., `NotFound` → HTTP 404 / gRPC 5)
  - Error metadata (reason, message, details) is consistent across endpoints
- **Fix**: Define errors in proto, use generated error helpers

```proto
// errors/user.proto
enum ErrorReason {
  USER_NOT_FOUND = 0;
  USER_ALREADY_EXISTS = 1;
}
```

```go
// GOOD: use generated error
errors.IsUserNotFound(err)
return errors.UserNotFound("user %s not found", userID)
```

### Proto Backward Compatibility (P0)

- **Detect**: Breaking changes in proto definitions
- **Prompt**: Check for:
  - Removed or renamed fields (breaks existing clients)
  - Changed field numbers (data corruption)
  - Changed field types (deserialization failure)
  - Required fields added without defaults (breaks old clients)
  - Enum values reordered or removed
- **Fix**: Use `reserved` for removed fields/numbers. Add new fields with new numbers. Never change existing field types.

```proto
message User {
  reserved 3, 7;                  // previously used field numbers
  reserved "old_field_name";      // previously used names
  string id = 1;
  string name = 2;
  string email = 4;              // new field, new number
}
```

### API Response Consistency (P2)

- **Detect**: Inconsistent response shapes across endpoints
- **Prompt**: Check for:
  - Some endpoints return `{data, message}` while others return raw objects
  - Pagination responses with different field names (`total` vs `count`, `items` vs `list`)
  - Timestamps in different formats across endpoints
  - Null vs empty array inconsistency
- **Fix**: Define shared response wrapper messages in proto, enforce via code review

### Request Validation Completeness (P1)

- **Detect**: Endpoints accepting invalid or dangerous input
- **Prompt**: For each RPC, verify:
  - String fields have max length constraints
  - Numeric fields have range validation
  - Enum fields reject unknown values
  - Repeated fields have max count limits
  - Nested messages validate recursively
- **Fix**: Use `protoc-gen-validate` or `buf validate` rules in proto definitions

---

## Database & Migration Safety

### Migration Backward Compatibility (P0)

- **Detect**: Migrations that break the running application during rolling deployment
- **Prompt**: During a rolling deploy, old code and new code run simultaneously. Check if migration:
  - Renames or drops a column that old code still reads → **BREAKING**
  - Adds a NOT NULL column without default → **BREAKING** (old code inserts fail)
  - Drops a table → **BREAKING**
  - Adds a column with default → Safe
  - Adds an index → Safe (but may lock table)
- **Fix**: Use expand-contract pattern: (1) add new column, (2) deploy code using both, (3) migrate data, (4) deploy code using only new, (5) drop old column

### Large Table DDL Risk (P0)

- **Detect**: ALTER TABLE on large tables without online DDL consideration
- **Prompt**: On MySQL/MariaDB, `ALTER TABLE` may lock the table for the entire duration on large tables. Check for:
  - Adding indexes on tables with 1M+ rows without `ALGORITHM=INPLACE` or tools like `pt-online-schema-change` / `gh-ost`
  - Adding columns with defaults on large tables
  - Changing column types
- **Fix**: Use online DDL tools, schedule during low-traffic windows, test migration time on production-sized data first

### GORM AutoMigrate in Production (P1)

- **Detect**: `db.AutoMigrate()` called in production startup
- **Prompt**: `AutoMigrate` can silently alter tables, add columns, and change indexes. In production with large tables, this can lock tables and cause outages.
- **Fix**: Use explicit migration files (golang-migrate, goose, atlas). Only use `AutoMigrate` in development.

### GORM Hook Side Effects (P1)

- **Detect**: GORM hooks (`BeforeCreate`, `AfterUpdate`, etc.) with external side effects
- **Prompt**: Check for hooks that:
  - Make HTTP/RPC calls (what if they fail? is the transaction still committed?)
  - Write to other tables (not in the same transaction)
  - Send messages to MQ (should be after commit, not in hook)
  - Have heavy computation (runs on every single insert/update)
- **Fix**: Move side effects to explicit service-layer calls after successful DB commit. Use outbox pattern for event publishing.

```go
// BAD: side effect in hook, if MQ fails the order is still created
func (o *Order) AfterCreate(tx *gorm.DB) error {
    return mq.Publish("order.created", o) // dangerous!
}

// GOOD: explicit in service layer
func (s *OrderService) CreateOrder(ctx context.Context, req *CreateOrderReq) error {
    if err := s.repo.Create(ctx, order); err != nil {
        return err
    }
    // publish after successful commit
    return s.eventBus.Publish(ctx, "order.created", order)
}
```

### Soft Delete Consistency (P2)

- **Detect**: Inconsistent soft delete handling across queries
- **Prompt**: If using GORM `gorm.DeletedAt`:
  - Are all queries automatically filtered? (GORM does this, but raw queries don't)
  - Do unique constraints account for soft-deleted rows? (`UNIQUE(email)` will conflict with soft-deleted rows)
  - Are foreign key cascades aware of soft deletes?
  - Is there a cleanup/archival process for old soft-deleted rows?
- **Fix**: Use partial unique indexes, add archival cron jobs, be explicit about soft delete in raw queries

### Transaction Isolation Awareness (P2)

- **Detect**: Transactions with incorrect isolation level for the operation
- **Prompt**: Check for:
  - Read-then-write patterns without `SELECT ... FOR UPDATE` (lost update problem)
  - Inventory/balance deductions without pessimistic locking
  - Long-running transactions holding locks
- **Fix**: Use appropriate isolation level, minimize transaction duration, use `FOR UPDATE` for read-modify-write