# Kratos Development Conventions

**Load this reference when:** creating new files, adding API endpoints, defining errors, writing service/biz/data layers, configuring servers, or setting up Wire dependency injection.

## Project Layout (DDD Onion Architecture)

```
API (Proto) → Server (HTTP/gRPC) → Service → Biz → Data
```

| Layer | Directory | Responsibility | Depends On |
|-------|-----------|---------------|------------|
| API | `api/<domain>/v1/` | Proto definitions, generated code | Nothing |
| Server | `internal/server/` | HTTP/gRPC server config, middleware | Service |
| Service | `internal/service/` | gRPC implementation, DTO→DO conversion | Biz |
| Biz | `internal/biz/` | Business logic, domain interfaces | Nothing (defines interfaces) |
| Data | `internal/data/` | Repository implementation, storage | Biz (implements interfaces) |
| Conf | `internal/conf/` | Configuration proto definitions | Nothing |
| Cmd | `cmd/<service>/` | Entry point, Wire injection | All layers |

**Dependency rule:** Inner layers NEVER import outer layers. Biz defines interfaces, Data implements them.

## Proto Definitions

### File Naming

```
api/<domain>/v1/<domain>.proto         # Service + messages
api/<domain>/v1/error_reason.proto     # Error definitions
```

### Service Proto Template

```protobuf
syntax = "proto3";
package <domain>.v1;

option go_package = "git.yingzhongtong.com/x_financial/mpc-wallet/api/<domain>/v1;v1";

import "google/api/annotations.proto";

service <Domain>Service {
    // <Verb><Noun> - describe what the RPC does
    rpc Get<Resource>(Get<Resource>Request) returns (Get<Resource>Response) {
        option (google.api.http) = {
            get: "/v1/<resource>"
        };
    }

    rpc Create<Resource>(Create<Resource>Request) returns (Create<Resource>Response) {
        option (google.api.http) = {
            post: "/v1/<resource>"
            body: "*"
        };
    }
}

message Get<Resource>Request {
    string id = 1;
}

message Get<Resource>Response {
    // fields...
}
```

**Rules:**
- `package`: `<domain>.v1`
- `go_package`: full path + `;v1` alias
- RPC names: PascalCase verbs (`Get`, `Create`, `Update`, `Delete`, `List`)
- Message fields: snake_case
- Each RPC has matched `Request`/`Response` pair
- HTTP annotations: GET for queries, POST+body for mutations
- HTTP paths: `/v1/<resource>/<action>`

### Error Reason Proto Template

```protobuf
syntax = "proto3";
package <domain>.v1;

option go_package = "git.yingzhongtong.com/x_financial/mpc-wallet/api/<domain>/v1;v1";

import "errors/errors.proto";

enum ErrorReason {
    option (errors.default_code) = 500;

    ERROR_REASON_UNSPECIFIED = 0;

    // Group: input validation (400)
    INVALID_INPUT = 10 [(errors.code) = 400];

    // Group: not found (404)
    RESOURCE_NOT_FOUND = 20 [(errors.code) = 404];

    // Group: conflict (409)
    RESOURCE_ALREADY_EXISTS = 30 [(errors.code) = 409];

    // Group: server errors (500)
    INTERNAL_ERROR = 40 [(errors.code) = 500];
}
```

**HTTP code conventions:**
- 400: Client input validation errors
- 404: Resource not found
- 409: Conflict (duplicate, wrong state)
- 410: Expired/gone
- 423: Service locked
- 500: Internal server errors

**Generated code pattern:**
```go
// Create error
v1.ErrorResourceNotFound("resource %s not found", id)

// Check error
if v1.IsResourceNotFound(err) { ... }
```

### Code Generation

```bash
make api       # Generate from proto: *.pb.go, *_http.pb.go, *_grpc.pb.go, error_reason_errors.pb.go
make config    # Generate internal/conf/*.pb.go
```

Never edit generated files (`*.pb.go`, `wire_gen.go`).

## Layer Implementation Conventions

### Biz Layer

**File structure:**
```
internal/biz/
├── biz.go              # ProviderSet
├── <domain>.go         # Domain models + repository interfaces
├── <domain>_usecase.go # Business logic implementation
└── <feature>.go        # Additional features (engine, manager, etc.)
```

**ProviderSet:**
```go
var ProviderSet = wire.NewSet(
    NewSigningUsecaseProvider,
    NewMPCEngine,
    NewUnlockManager,
)
```

**Interface definition (in `<domain>.go`):**
```go
// SessionRepo manages sign session persistence.
type SessionRepo interface {
    Create(ctx context.Context, session *SignSession) error
    Get(ctx context.Context, sessionID string) (*SignSession, error)
    // ...
}
```

**Usecase implementation (in `<domain>_usecase.go`):**
```go
type SigningUsecase struct {
    sessionRepo    SessionRepo   // interface, not concrete type
    mpcEngine      MPCEngine     // interface, not concrete type
    log            *log.Helper
}

func NewSigningUsecase(repo SessionRepo, engine MPCEngine, logger log.Logger) *SigningUsecase {
    return &SigningUsecase{
        sessionRepo: repo,
        mpcEngine:   engine,
        log:         log.NewHelper(logger),
    }
}
```

**Rules:**
- Define interfaces in biz layer (dependency inversion)
- Accept interfaces, return structs
- Use `log.Helper` (not raw `log.Logger`)
- All exported types/functions have English comments starting with the name
- Business errors use generated error functions: `v1.ErrorXxx(...)`

### Data Layer

**File structure:**
```
internal/data/
├── data.go             # ProviderSet + Data struct + RedisClient interface
├── <repo>.go           # Repository implementation
├── <loader>.go         # Loader/accessor implementation
└── testsuite.go        # Test infrastructure (TestSuite)
```

**ProviderSet:**
```go
var ProviderSet = wire.NewSet(
    NewData,
    NewRedisClient,
    NewSessionRepo,
    NewKeyShareLoader,
)
```

**Data struct:**
```go
type Data struct {
    rdb RedisClient
}

// Factory returns (instance, cleanup, error)
func NewData(c *conf.Data, logger log.Logger) (*Data, func(), error) {
    // ...init resources
    cleanup := func() {
        logHelper.Info("closing the data resources")
        rdb.Close()
    }
    return &Data{rdb: rdb}, cleanup, nil
}
```

**Repository implementation:**
```go
type sessionRepo struct {     // unexported struct
    data *Data
    log  *log.Helper
}

// NewSessionRepo returns the biz interface, not the concrete type.
func NewSessionRepo(data *Data, logger log.Logger) biz.SessionRepo {
    return &sessionRepo{data: data, log: log.NewHelper(logger)}
}
```

**Redis key conventions:**
```go
const (
    sessionKeyPrefix   = "mpc:session:"
    signatureKeyPrefix = "mpc:signature:"
    requestIDKeyPrefix = "mpc:request:"
)
```

**Rules:**
- Repository struct is unexported, factory returns biz interface
- Separate storage DTO from domain model (JSON serialization)
- Use key prefixes for Redis namespace isolation
- Factory returns `(instance, cleanup, error)` for resource lifecycle
- Define `RedisClient` interface (subset of `redis.Client`) for testability

### Service Layer

**File structure:**
```
internal/service/
├── service.go          # ProviderSet
├── <domain>.go         # gRPC service implementation
└── <feature>.go        # Additional services
```

**ProviderSet:**
```go
var ProviderSet = wire.NewSet(NewHealthService, NewSigningService, NewUnlockService)
```

**Service implementation:**
```go
// Define usecase interface locally (not importing from biz)
type SigningUsecase interface {
    InitiateSign(ctx context.Context, keyID string, messageHash []byte, requestID string) (*biz.SignSession, *biz.LoadedKeyShare, error)
    // ...
}

type SigningService struct {
    v1.UnimplementedSigningServiceServer  // embed unimplemented for forward compat
    uc  SigningUsecase                     // interface, not concrete type
    log *log.Helper
}

func NewSigningService(uc SigningUsecase, logger log.Logger) *SigningService {
    return &SigningService{uc: uc, log: log.NewHelper(logger)}
}

func (s *SigningService) InitiateSign(ctx context.Context, req *v1.InitiateSignRequest) (*v1.InitiateSignResponse, error) {
    // 1. Validate input
    // 2. Call usecase
    // 3. Convert DO → DTO (response proto)
    // 4. Return response
}
```

**Rules:**
- Embed `v1.Unimplemented<Service>Server` for forward compatibility
- Define usecase interface in service package (decoupling from biz concrete types)
- Input validation belongs here (proto field checks)
- DTO ↔ DO conversion belongs here
- No business logic — delegate to usecase
- Log errors before returning proto error responses

### Server Layer

**File structure:**
```
internal/server/
├── server.go           # ProviderSet
├── grpc.go             # gRPC server factory
├── http.go             # HTTP server factory
├── interceptor.go      # Middleware/interceptors
└── tls.go              # TLS configuration
```

**gRPC server factory:**
```go
func NewGRPCServer(
    c *conf.Server,
    svc1 *service.SigningService,
    svc2 *service.UnlockService,
    logger log.Logger,
) (*grpc.Server, error) {
    var opts = []grpc.ServerOption{
        grpc.Middleware(
            recovery.Recovery(),
            // custom middleware...
        ),
    }
    // Configure network, address, timeout from conf
    // Configure TLS if enabled
    srv := grpc.NewServer(opts...)
    // Register services
    v1.RegisterSigningServiceServer(srv, svc1)
    return srv, nil
}
```

**HTTP server factory:**
```go
func NewHTTPServer(
    c *conf.Server,
    svc *service.UnlockService,
    logger log.Logger,
) *http.Server {
    var opts = []http.ServerOption{
        http.Middleware(recovery.Recovery()),
    }
    srv := http.NewServer(opts...)
    v1.RegisterUnlockServiceHTTPServer(srv, svc)
    return srv
}
```

**Middleware pattern (Kratos middleware.Middleware):**
```go
func MyMiddleware(dep SomeDep) middleware.Middleware {
    return func(handler middleware.Handler) middleware.Handler {
        return func(ctx context.Context, req interface{}) (interface{}, error) {
            if tr, ok := transport.FromServerContext(ctx); ok {
                operation := tr.Operation()
                // check operation, reject or pass through
            }
            return handler(ctx, req)
        }
    }
}
```

**gRPC interceptor pattern (for TLS/auth):**
```go
func AuthUnaryInterceptor(allowed []string) grpc.UnaryServerInterceptor {
    return func(ctx context.Context, req interface{}, info *grpc.UnaryServerInfo, handler grpc.UnaryHandler) (interface{}, error) {
        if err := validate(ctx, allowed); err != nil {
            return nil, err
        }
        return handler(ctx, req)
    }
}
```

**Middleware order:** recovery → lock check → custom → handler

## Wire Dependency Injection

**Wire file (`cmd/<service>/wire.go`):**
```go
//go:build wireinject

func wireApp(*conf.Server, *conf.Data, *conf.SigningConfig, log.Logger) (*AppBundle, func(), error) {
    panic(wire.Build(
        server.ProviderSet,
        data.ProviderSet,
        biz.ProviderSet,
        service.ProviderSet,
        wire.Bind(new(biz.KeyShareLoader), new(*data.KeyShareLoader)),
        wire.Bind(new(service.SigningUsecase), new(*biz.SigningUsecase)),
        newApp,
    ))
}
```

**Rules:**
- One `ProviderSet` per package
- `wire.Bind` maps interface to concrete implementation
- Run `wire ./cmd/<service>/...` after changing providers
- Never edit `wire_gen.go` manually

## Configuration

**Proto definition (`internal/conf/conf.proto`):**
```protobuf
syntax = "proto3";
package kratos.api;
option go_package = "git.yingzhongtong.com/x_financial/mpc-wallet/internal/conf;conf";

import "google/protobuf/duration.proto";

message Bootstrap {
    Server server = 1;
    Data data = 2;
    SigningConfig signing = 3;
}
```

**Loading priority:** CLI `-conf` flag > `CONFIG_FILE` env var > Apollo config center

**Generate:** `make config`

## Import Organization

Three groups, separated by blank lines:

```go
import (
    // 1. Standard library
    "context"
    "fmt"
    "sync"

    // 2. Third-party
    "github.com/go-kratos/kratos/v2/log"
    "github.com/google/wire"

    // 3. Local (project)
    v1 "git.yingzhongtong.com/x_financial/mpc-wallet/api/signing/v1"
    "git.yingzhongtong.com/x_financial/mpc-wallet/internal/biz"
)
```

Local prefix: `git.yingzhongtong.com/x_financial/mpc-wallet`

## Logging

```go
// In struct
type MyService struct {
    log *log.Helper
}

// In constructor
func NewMyService(logger log.Logger) *MyService {
    return &MyService{log: log.NewHelper(logger)}
}

// Usage
s.log.Debugf("debug: %v", val)
s.log.Infof("info: %v", val)
s.log.Warnf("warn: %v", val)
s.log.Errorf("error: %v", err)
```

Accept `log.Logger` in constructor, wrap with `log.NewHelper()` for formatted output.

## Error Handling

```go
// Wrap internal errors
return nil, fmt.Errorf("failed to load key: %w", err)

// Return business errors to client
return nil, v1.ErrorKeyNotFound("key %s not found", keyID)

// Log then return sanitized error
s.log.Errorf("internal failure: %v", err)
return nil, v1.ErrorProtocolError("operation failed")
```

**Rules:**
- Wrap errors with `%w` for internal propagation
- Use generated `v1.ErrorXxx()` for client-facing errors
- Never expose internal details to clients
- Log internal error details before returning sanitized response

## Concurrency Safety

```go
type Manager struct {
    mu     sync.RWMutex
    data   map[string]*Item
}

// Read operation
func (m *Manager) Get(id string) (*Item, bool) {
    m.mu.RLock()
    defer m.mu.RUnlock()
    item, ok := m.data[id]
    return item, ok
}

// Write operation
func (m *Manager) Set(id string, item *Item) {
    m.mu.Lock()
    defer m.mu.Unlock()
    m.data[id] = item
}
```

**Rules:**
- `sync.RWMutex` for shared state (RLock for reads, Lock for writes)
- Always `defer Unlock()` immediately after lock
- Use channels for goroutine coordination
- Run tests with `-race` flag

## Code Comments

All comments in English. Exported types/functions must have godoc comments:

```go
// SigningService implements the gRPC signing service.
type SigningService struct { ... }

// NewSigningService creates a new SigningService instance.
func NewSigningService(...) *SigningService { ... }

// InitiateSign creates a new signing session for the given key.
func (s *SigningService) InitiateSign(...) (...) { ... }
```

## Adding a New Feature Checklist

1. **Proto**: Define messages + RPC in `api/<domain>/v1/<domain>.proto`
2. **Errors**: Add error reasons in `api/<domain>/v1/error_reason.proto`
3. **Generate**: `make api`
4. **Biz**: Define interface in `internal/biz/<domain>.go`, implement in `<domain>_usecase.go`
5. **Data**: Implement repository in `internal/data/<repo>.go`
6. **Service**: Implement gRPC service in `internal/service/<domain>.go`
7. **Server**: Register service in `internal/server/grpc.go` and/or `http.go`
8. **Wire**: Update ProviderSets and `wire.go`, run `wire ./cmd/<service>/...`
9. **Config**: Update `internal/conf/conf.proto` if new config needed, `make config`
10. **Test at each layer** following TDD (see SKILL.md)
11. **Check**: `make check`
