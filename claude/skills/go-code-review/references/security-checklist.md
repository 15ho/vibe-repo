# Go Security Checklist

Security and reliability review prompts specific to Go, gRPC, GORM, and Kratos ecosystems. Every item includes detection guidance and risk classification.

## Table of Contents

1. [Concurrency Safety](#concurrency-safety)
2. [Input Validation & Injection](#input-validation--injection)
3. [Authentication & Authorization](#authentication--authorization)
4. [Secrets & Sensitive Data](#secrets--sensitive-data)
5. [Cryptography](#cryptography)
6. [gRPC Security](#grpc-security)
7. [GORM Security](#gorm-security)
8. [Network & TLS](#network--tls)
9. [Dependency & Supply Chain](#dependency--supply-chain)

---

## Concurrency Safety

### Data Races (P0)

- **Detect**: Shared variables accessed from multiple goroutines without synchronization
- **Prompt**: Scan for struct fields written in one goroutine and read in another. Look for map read/write without mutex. Check for `go func()` closures capturing loop variables.
- **Fix**: Use `sync.Mutex`, `sync.RWMutex`, `atomic` operations, or channels
- **Verify**: `go build -race` passes

```go
// BAD: data race on shared map
go func() { m[key] = value }()
v := m[key]

// GOOD: protected access
mu.Lock()
m[key] = value
mu.Unlock()
```

### Goroutine Leaks (P0)

- **Detect**: Goroutines blocked forever on channel operations or missing context cancellation
- **Prompt**: For every `go func()`, verify there is a termination path. Check unbuffered channels have both sender and receiver. Verify `context.Done()` or `select` with timeout.
- **Fix**: Always use `context.WithTimeout` or `context.WithCancel`, check `ctx.Done()` in loops

```go
// BAD: goroutine leaks if nobody reads ch
go func() { ch <- result }()

// GOOD: respect context
go func() {
    select {
    case ch <- result:
    case <-ctx.Done():
    }
}()
```

### Mutex Misuse (P1)

- **Detect**: Unlock not deferred, RWMutex used where Mutex suffices, lock held during I/O
- **Prompt**: Every `Lock()` should have an immediately following `defer Unlock()`. Look for long-held locks spanning network calls or DB queries.
- **Fix**: Defer unlocks, minimize critical sections, avoid I/O under locks

### Context Propagation (P1)

- **Detect**: Missing context passing in goroutine chains, hardcoded `context.Background()` in non-init code
- **Prompt**: Trace context from HTTP/gRPC handler through service → biz → data layers. Every DB call, HTTP client call, and goroutine should receive the request context.
- **Fix**: Thread `ctx context.Context` through all layers

---

## Input Validation & Injection

### SQL Injection via GORM (P0)

- **Detect**: Raw SQL with string concatenation or `fmt.Sprintf`
- **Prompt**: Scan for `db.Raw(fmt.Sprintf(...))`, `db.Where("name = '" + input + "'")`, `db.Exec` with unparameterized input
- **Fix**: Always use parameterized queries

```go
// BAD
db.Where(fmt.Sprintf("name = '%s'", input))

// GOOD
db.Where("name = ?", input)
```

### Path Traversal (P0)

- **Detect**: User input used in file paths without sanitization
- **Prompt**: Scan for `os.Open`, `filepath.Join`, `ioutil.ReadFile` with user-supplied path components. Check for `..` traversal.
- **Fix**: Use `filepath.Clean`, validate against allowed base directory

### Command Injection (P0)

- **Detect**: User input passed to `exec.Command` or `os/exec`
- **Prompt**: Scan for `exec.Command` with variable arguments derived from user input
- **Fix**: Use allowlists, avoid shell execution, use `exec.Command` with explicit arg splitting (no `sh -c`)

### Protobuf Input Validation (P1)

- **Detect**: gRPC handlers that trust incoming proto messages without validation
- **Prompt**: Check if `Validate()` is called on request messages (if using `protoc-gen-validate` or `buf validate`). Look for missing nil checks on nested message fields.
- **Fix**: Use proto validation, add nil checks for optional/nested fields

```go
// GOOD: validate request
if err := req.Validate(); err != nil {
    return nil, status.Errorf(codes.InvalidArgument, "invalid request: %v", err)
}
```

---

## Authentication & Authorization

### Missing Auth Interceptor (P0)

- **Detect**: gRPC server created without authentication middleware
- **Prompt**: Check `grpc.NewServer()` or Kratos `grpc.NewServer()` options for auth interceptor/middleware. Verify public vs private endpoints are distinguished.
- **Fix**: Add auth middleware, use Kratos `middleware.Chain` with JWT/OAuth validation

### Broken Access Control (P0)

- **Detect**: Endpoints that don't verify resource ownership
- **Prompt**: For update/delete operations, check if the handler verifies that the authenticated user owns or has permission on the target resource. Look for `userID` from request body instead of auth token.
- **Fix**: Extract user identity from auth context, verify ownership before mutation

### Excessive Permissions (P1)

- **Detect**: All-or-nothing auth checks instead of fine-grained RBAC
- **Prompt**: Look for `if !isAdmin` as the only authorization check. Check if different API operations have appropriate permission levels.

---

## Secrets & Sensitive Data

### Hardcoded Secrets (P0)

- **Detect**: API keys, passwords, tokens in source code
- **Prompt**: Scan for string literals matching patterns: `password`, `secret`, `api_key`, `token`, `-----BEGIN`, base64 blobs >20 chars. Check config structs for default secret values.
- **Fix**: Use environment variables, Kubernetes secrets, or vault

### Sensitive Data in Logs (P1)

- **Detect**: Logging passwords, tokens, PII, or full request bodies
- **Prompt**: Check `log.Info`, `log.Debug`, `log.Error` calls for sensitive field output. Look for `%+v` on request/user structs that contain secrets.
- **Fix**: Use structured logging with field selection, redact sensitive fields

### Sensitive Data in Error Messages (P1)

- **Detect**: Internal errors exposed to API clients
- **Prompt**: Check gRPC status messages and HTTP responses for stack traces, DB errors, or internal paths
- **Fix**: Return generic error messages to clients, log detailed errors server-side

---

## Cryptography

### Weak Hashing (P0)

- **Detect**: MD5 or SHA1 for security-critical purposes (password hashing, integrity)
- **Prompt**: Scan imports for `crypto/md5`, `crypto/sha1`. Check usage context — non-security use (checksums, cache keys) is acceptable.
- **Fix**: Use `bcrypt`, `argon2`, or `scrypt` for passwords. Use `SHA-256`+ for integrity.

### Insecure Random (P0)

- **Detect**: `math/rand` used for security-sensitive values (tokens, IDs, nonces)
- **Prompt**: Scan for `math/rand` in auth, token generation, or cryptographic contexts
- **Fix**: Use `crypto/rand`

```go
// BAD
token := fmt.Sprintf("%d", rand.Int())

// GOOD
b := make([]byte, 32)
crypto_rand.Read(b)
token := hex.EncodeToString(b)
```

---

## gRPC Security

### Message Size Limits (P1)

- **Detect**: No `MaxRecvMsgSize` set on gRPC server
- **Prompt**: Check gRPC server options. Default is 4MB — verify if appropriate for the service. Extremely large messages can cause OOM.
- **Fix**: Set explicit `grpc.MaxRecvMsgSize()` and `grpc.MaxSendMsgSize()`

### Missing Recovery Interceptor (P1)

- **Detect**: gRPC server without panic recovery middleware
- **Prompt**: Verify Kratos server has `recovery.Recovery()` middleware or equivalent
- **Fix**: Add recovery middleware to prevent a single panic from crashing the server

### Reflection Enabled in Production (P2)

- **Detect**: `reflection.Register(server)` in production builds
- **Prompt**: Check if gRPC reflection is conditionally enabled (dev only)
- **Fix**: Guard with build tags or config flags

---

## GORM Security

### Mass Assignment (P1)

- **Detect**: `db.Create(&userInput)` where `userInput` comes directly from API request
- **Prompt**: Check if request payloads are directly passed to GORM Create/Update without field filtering. Look for `is_admin`, `role`, `balance` fields that could be injected.
- **Fix**: Map request to domain model with explicit field assignment, or use `Select` to whitelist fields

```go
// BAD: mass assignment
db.Create(&req)

// GOOD: explicit fields
user := User{Name: req.Name, Email: req.Email}
db.Create(&user)
```

### Transaction Safety (P1)

- **Detect**: Multi-step mutations without transactions, or transactions without proper rollback
- **Prompt**: Look for sequences of `db.Create`, `db.Update`, `db.Delete` that should be atomic. Verify `tx.Rollback()` in error paths or use of `Transaction()` callback.
- **Fix**: Use `db.Transaction(func(tx *gorm.DB) error { ... })` pattern

---

## Network & TLS

### Insecure TLS Config (P0)

- **Detect**: `InsecureSkipVerify: true` in TLS config
- **Prompt**: Scan for `tls.Config{InsecureSkipVerify: true}`. Check HTTP clients and gRPC dial options.
- **Fix**: Use proper certificate verification. For internal services, use mTLS.

### Missing Timeouts (P1)

- **Detect**: HTTP clients or servers without timeout configuration
- **Prompt**: Scan for `&http.Client{}` without `Timeout`. Check `http.Server` for `ReadTimeout`, `WriteTimeout`, `IdleTimeout`. Verify gRPC dial options include `WithTimeout` or deadline.
- **Fix**: Always set timeouts. Default `http.Client` has no timeout — this is a production risk.

```go
// BAD
client := &http.Client{}

// GOOD
client := &http.Client{Timeout: 10 * time.Second}
```

---

## Dependency & Supply Chain

### Outdated Dependencies (P2)

- **Detect**: `go.mod` has dependencies with known CVEs
- **Prompt**: Check `go.mod` for pinned old versions of critical libraries. Run `go list -m -u all` mentally to identify major version gaps.
- **Fix**: Update dependencies, use `govulncheck` in CI

### Unnecessary CGo (P2)

- **Detect**: CGo imports where pure Go alternatives exist
- **Prompt**: Scan for `import "C"` or `#cgo` directives. Evaluate if a pure Go library can replace the C dependency.
- **Fix**: Prefer pure Go libraries for portability and safety
