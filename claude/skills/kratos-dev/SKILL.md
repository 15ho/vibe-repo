---
name: kratos-dev
description: Kratos 微服务框架全流程开发指南。使用场景：(1) 创建新的 Kratos 微服务项目或模块 (2) 添加 gRPC/HTTP API 端点 (3) 生成 proto、wire、config 代码 (4) 实现分层架构（biz/data/service/server）(5) 配置依赖注入。触发词：kratos、微服务、gRPC、proto、wire、新建服务、添加 API。
---

# Kratos 开发

## 架构概览

Kratos 采用 DDD 分层架构：

```
API (Proto) → Server (HTTP/gRPC) → Service → Biz → Data
```

| 层级 | 目录 | 职责 |
|------|------|------|
| API | `api/<service>/v1/` | Proto 定义，生成 pb.go、http、grpc 代码 |
| Server | `internal/server/` | HTTP/gRPC 服务器配置，中间件 |
| Service | `internal/service/` | 应用层，DTO→DO 转换，编排 biz |
| Biz | `internal/biz/` | 业务逻辑层，定义 Repository 接口 |
| Data | `internal/data/` | 数据访问层，实现 Repository 接口 |
| Conf | `internal/conf/` | 配置 Proto 定义 |

## 标准目录结构

```
├── api/                      # API Proto 定义
│   └── <service>/v1/
│       ├── <service>.proto   # 服务定义
│       └── error_reason.proto # 错误码
├── cmd/<service>/            # 服务入口
│   ├── main.go
│   ├── wire.go               # 依赖注入定义
│   └── wire_gen.go           # 生成文件（勿编辑）
├── configs/                  # 配置文件
├── internal/
│   ├── biz/                  # 业务逻辑 + ProviderSet
│   ├── conf/                 # 配置 Proto
│   ├── data/                 # 数据访问 + ProviderSet
│   ├── server/               # HTTP/gRPC 服务器 + ProviderSet
│   └── service/              # 服务实现 + ProviderSet
└── third_party/              # 第三方 proto
```

## 工作流

### 1. 创建新项目

```bash
kratos new <project-name>
cd <project-name>
go mod tidy
```

### 2. 添加 API

```bash
# 创建 proto 文件
kratos proto add api/<service>/v1/<service>.proto
```

Proto 模板：

```protobuf
syntax = "proto3";

package api.<service>.v1;

option go_package = "<module>/api/<service>/v1;<service>v1";

import "google/api/annotations.proto";

service <Service>Service {
    rpc Get<Entity> (Get<Entity>Request) returns (Get<Entity>Response) {
        option (google.api.http) = {
            get: "/v1/<entities>/{id}"
        };
    }
    rpc Create<Entity> (Create<Entity>Request) returns (Create<Entity>Response) {
        option (google.api.http) = {
            post: "/v1/<entities>"
            body: "*"
        };
    }
}

message Get<Entity>Request {
    int64 id = 1;
}

message Get<Entity>Response {
    <Entity> <entity> = 1;
}

message <Entity> {
    int64 id = 1;
    string name = 2;
}
```

### 3. 生成代码

```bash
# 生成 API 代码（pb.go, http, grpc, openapi）
make api

# 生成服务骨架代码
kratos proto server api/<service>/v1/<service>.proto -t internal/service
```

### 4. 实现分层

#### Biz 层（业务逻辑）

```go
// internal/biz/<entity>.go
package biz

import "context"

type <Entity> struct {
    ID   int64
    Name string
}

type <Entity>Repo interface {
    Get(ctx context.Context, id int64) (*<Entity>, error)
    Create(ctx context.Context, e *<Entity>) (*<Entity>, error)
}

type <Entity>Usecase struct {
    repo <Entity>Repo
    log  *log.Helper
}

func New<Entity>Usecase(repo <Entity>Repo, logger log.Logger) *<Entity>Usecase {
    return &<Entity>Usecase{repo: repo, log: log.NewHelper(logger)}
}

func (uc *<Entity>Usecase) Get(ctx context.Context, id int64) (*<Entity>, error) {
    return uc.repo.Get(ctx, id)
}
```

#### Data 层（数据访问）

```go
// internal/data/<entity>.go
package data

import "context"

type <entity>Repo struct {
    data *Data
    log  *log.Helper
}

func New<Entity>Repo(data *Data, logger log.Logger) biz.<Entity>Repo {
    return &<entity>Repo{data: data, log: log.NewHelper(logger)}
}

func (r *<entity>Repo) Get(ctx context.Context, id int64) (*biz.<Entity>, error) {
    // 实现数据访问
}
```

#### Service 层（应用层）

```go
// internal/service/<service>.go
package service

import (
    "context"
    pb "your-module/api/<service>/v1"
    "your-module/internal/biz"
)

type <Service>Service struct {
    pb.Unimplemented<Service>ServiceServer
    uc *biz.<Entity>Usecase
}

func New<Service>Service(uc *biz.<Entity>Usecase) *<Service>Service {
    return &<Service>Service{uc: uc}
}

func (s *<Service>Service) Get<Entity>(ctx context.Context, req *pb.Get<Entity>Request) (*pb.Get<Entity>Response, error) {
    entity, err := s.uc.Get(ctx, req.Id)
    if err != nil {
        return nil, err
    }
    return &pb.Get<Entity>Response{
        <Entity>: &pb.<Entity>{Id: entity.ID, Name: entity.Name},
    }, nil
}
```

### 5. 配置依赖注入

每个包提供 `ProviderSet`：

```go
// internal/biz/biz.go
var ProviderSet = wire.NewSet(New<Entity>Usecase)

// internal/data/data.go
var ProviderSet = wire.NewSet(NewData, New<Entity>Repo)

// internal/service/service.go
var ProviderSet = wire.NewSet(New<Service>Service)

// internal/server/server.go
var ProviderSet = wire.NewSet(NewGRPCServer, NewHTTPServer)
```

Wire 定义：

```go
// cmd/<service>/wire.go
//go:build wireinject

package main

func wireApp(*conf.Server, *conf.Data, log.Logger) (*kratos.App, func(), error) {
    panic(wire.Build(server.ProviderSet, data.ProviderSet, biz.ProviderSet, service.ProviderSet, newApp))
}
```

生成：

```bash
wire ./cmd/<service>/...
```

### 6. 启动服务

```bash
kratos run
# 或
go build -o ./bin/<service> ./cmd/<service> && ./bin/<service> -conf ./configs
```

## 常用命令速查

| 命令 | 用途 |
|------|------|
| `kratos new <name>` | 创建新项目 |
| `kratos proto add api/xxx/v1/xxx.proto` | 添加 proto 文件 |
| `kratos proto server <proto> -t internal/service` | 生成服务骨架 |
| `make api` | 生成 API 代码 |
| `wire ./cmd/<service>/...` | 生成依赖注入代码 |
| `kratos run` | 启动服务（热重载） |
| `make build` | 编译二进制 |

## 错误处理

定义错误码：

```protobuf
// api/<service>/v1/error_reason.proto
enum ErrorReason {
    option (errors.default_code) = 500;

    ENTITY_NOT_FOUND = 0 [(errors.code) = 404];
    ENTITY_ALREADY_EXISTS = 1 [(errors.code) = 409];
}
```

使用错误：

```go
import v1 "your-module/api/<service>/v1"

return nil, v1.ErrorEntityNotFound("entity %d not found", id)
```

## 中间件

```go
// internal/server/http.go
func NewHTTPServer(c *conf.Server, svc *service.<Service>Service, logger log.Logger) *http.Server {
    opts := []http.ServerOption{
        http.Middleware(
            recovery.Recovery(),
            tracing.Server(),
            logging.Server(logger),
        ),
    }
    if c.Http.Addr != "" {
        opts = append(opts, http.Address(c.Http.Addr))
    }
    srv := http.NewServer(opts...)
    v1.Register<Service>ServiceHTTPServer(srv, svc)
    return srv
}
```

## 参考资源

- [Kratos 官方文档](https://go-kratos.dev/docs/)
- [kratos-layout](https://github.com/go-kratos/kratos-layout) - 官方项目模板
- 详细 API 设计指南见 [references/api-design.md](references/api-design.md)
