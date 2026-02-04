# Kratos API 设计指南

## Proto 文件规范

### 目录结构

```
api/
└── <service>/
    └── v1/
        ├── <service>.proto      # 服务定义
        ├── error_reason.proto   # 错误码定义
        └── <service>_http.pb.go # 生成的 HTTP 代码
```

### 命名规范

| 类型 | 规范 | 示例 |
|------|------|------|
| package | `api.<service>.v<version>` | `api.user.v1` |
| service | `<Service>Service` | `UserService` |
| rpc | `<Action><Entity>` | `GetUser`, `CreateOrder` |
| request | `<Rpc>Request` | `GetUserRequest` |
| response | `<Rpc>Response` | `GetUserResponse` |

### HTTP 路由设计

```protobuf
service UserService {
    // GET /v1/users/{id}
    rpc GetUser (GetUserRequest) returns (GetUserResponse) {
        option (google.api.http) = {
            get: "/v1/users/{id}"
        };
    }

    // GET /v1/users?page_size=10&page_token=xxx
    rpc ListUsers (ListUsersRequest) returns (ListUsersResponse) {
        option (google.api.http) = {
            get: "/v1/users"
        };
    }

    // POST /v1/users (body: user fields)
    rpc CreateUser (CreateUserRequest) returns (CreateUserResponse) {
        option (google.api.http) = {
            post: "/v1/users"
            body: "*"
        };
    }

    // PUT /v1/users/{id} (body: user fields)
    rpc UpdateUser (UpdateUserRequest) returns (UpdateUserResponse) {
        option (google.api.http) = {
            put: "/v1/users/{id}"
            body: "*"
        };
    }

    // DELETE /v1/users/{id}
    rpc DeleteUser (DeleteUserRequest) returns (DeleteUserResponse) {
        option (google.api.http) = {
            delete: "/v1/users/{id}"
        };
    }
}
```

### 分页设计

```protobuf
message ListUsersRequest {
    int32 page_size = 1;    // 每页数量，默认 10，最大 100
    string page_token = 2;  // 分页令牌
    string filter = 3;      // 过滤条件
    string order_by = 4;    // 排序字段
}

message ListUsersResponse {
    repeated User users = 1;
    string next_page_token = 2;  // 下一页令牌，空表示无更多数据
    int32 total_size = 3;        // 总数（可选）
}
```

### 字段验证

使用 protoc-gen-validate：

```protobuf
import "validate/validate.proto";

message CreateUserRequest {
    string name = 1 [(validate.rules).string = {
        min_len: 1,
        max_len: 100
    }];
    string email = 2 [(validate.rules).string.email = true];
    int32 age = 3 [(validate.rules).int32 = {gte: 0, lte: 150}];
}
```

## 错误处理

### 错误码定义

```protobuf
// api/<service>/v1/error_reason.proto
syntax = "proto3";

package api.<service>.v1;

import "errors/errors.proto";

option go_package = "<module>/api/<service>/v1;<service>v1";

enum ErrorReason {
    option (errors.default_code) = 500;

    // 资源未找到 - 404
    USER_NOT_FOUND = 0 [(errors.code) = 404];

    // 资源已存在 - 409
    USER_ALREADY_EXISTS = 1 [(errors.code) = 409];

    // 参数无效 - 400
    INVALID_ARGUMENT = 2 [(errors.code) = 400];

    // 权限不足 - 403
    PERMISSION_DENIED = 3 [(errors.code) = 403];

    // 内部错误 - 500
    INTERNAL_ERROR = 4 [(errors.code) = 500];
}
```

### 错误使用

```go
import (
    v1 "your-module/api/<service>/v1"
    "github.com/go-kratos/kratos/v2/errors"
)

// 返回业务错误
func (s *UserService) GetUser(ctx context.Context, req *v1.GetUserRequest) (*v1.GetUserResponse, error) {
    user, err := s.uc.Get(ctx, req.Id)
    if err != nil {
        if errors.Is(err, biz.ErrUserNotFound) {
            return nil, v1.ErrorUserNotFound("user %d not found", req.Id)
        }
        return nil, v1.ErrorInternalError("internal error: %v", err)
    }
    return &v1.GetUserResponse{User: toProto(user)}, nil
}
```

## 双向流 API

适用于实时通信、MPC 协议等场景：

```protobuf
service SigningService {
    // 双向流
    rpc SignProtocol (stream MPCMessage) returns (stream MPCMessage);
}

message MPCMessage {
    string session_id = 1;
    bytes payload = 2;
    MessageType type = 3;
}
```

实现：

```go
func (s *SigningService) SignProtocol(stream v1.SigningService_SignProtocolServer) error {
    for {
        msg, err := stream.Recv()
        if err == io.EOF {
            return nil
        }
        if err != nil {
            return err
        }

        // 处理消息
        response := processMessage(msg)

        if err := stream.Send(response); err != nil {
            return err
        }
    }
}
```

## 配置 Proto

```protobuf
// internal/conf/conf.proto
syntax = "proto3";

package conf;

option go_package = "<module>/internal/conf;conf";

import "google/protobuf/duration.proto";

message Bootstrap {
    Server server = 1;
    Data data = 2;
}

message Server {
    message HTTP {
        string network = 1;
        string addr = 2;
        google.protobuf.Duration timeout = 3;
    }
    message GRPC {
        string network = 1;
        string addr = 2;
        google.protobuf.Duration timeout = 3;
    }
    HTTP http = 1;
    GRPC grpc = 2;
}

message Data {
    message Database {
        string driver = 1;
        string source = 2;
    }
    message Redis {
        string addr = 1;
        google.protobuf.Duration read_timeout = 2;
        google.protobuf.Duration write_timeout = 3;
    }
    Database database = 1;
    Redis redis = 2;
}
```

## 常见模式

### 长轮询

```protobuf
rpc WaitForEvent (WaitRequest) returns (EventResponse) {
    option (google.api.http) = {
        get: "/v1/events/wait"
    };
}

message WaitRequest {
    google.protobuf.Duration timeout = 1;  // 最长等待时间
}
```

### 批量操作

```protobuf
rpc BatchCreateUsers (BatchCreateUsersRequest) returns (BatchCreateUsersResponse) {
    option (google.api.http) = {
        post: "/v1/users:batchCreate"
        body: "*"
    };
}

message BatchCreateUsersRequest {
    repeated CreateUserRequest requests = 1;
}
```

### 自定义动作

```protobuf
// 非 CRUD 操作使用 :action 语法
rpc ActivateUser (ActivateUserRequest) returns (ActivateUserResponse) {
    option (google.api.http) = {
        post: "/v1/users/{id}:activate"
        body: "*"
    };
}
```
