# pcdn-keeper

Docker PCDN 流量模拟工具，基于 [spde (Super-Download-Engine)](https://github.com/pandamelive/spde) 下载引擎，循环下载配置文件中的 URL 列表，数据全部写入 tmpfs（内存文件系统），**完全不写入磁盘**。

> 全部镜像由 GitHub Actions 自动构建，用户本地无需编译。

## 架构

```
pcdn-keeper 容器
├── /app/spde              spde 二进制（Rust 静态二进制）
├── /app/spde-node/        spde 工作目录（用户挂载）
│   ├── config/config.yaml  下载任务配置
│   └── data/
│       ├── node-id.json     节点唯一标识
│       └── run-history.jsonl  流量历史记录
├── /opt/init/entrypoint.sh  循环调度器
└── /tmp/downloads/          下载目录（tmpfs 内存）
```

- **下载引擎**：spde，多线程 HTTP 下载，支持并发任务、断点续传、重试、代理
- **调度逻辑**：入口脚本循环调用 `spde serve`，每轮执行完所有启用的任务后休眠指定间隔
- **不落盘**：下载目录 `/tmp/downloads` 挂载为 tmpfs，每轮结束后自动清理

## 特性

- 基于 spde Rust 下载引擎，单静态二进制，性能优于 aria2
- 全部网络数据写入内存，无磁盘 IO
- 多并发下载，可配置单文件连接数和最大并发任务数
- 配置文件驱动，修改任务无需重建镜像
- 流量历史记录持久化（`run-history.jsonl`）
- docker 一键部署

## 快速使用

### 1. 启动容器

```bash
docker compose up -d
```

首次启动时如果配置文件不存在，容器会自动复制默认配置到 `./data/config/config.yaml`。

### 2. 编辑下载任务

```bash
vim ./data/config/config.yaml
```

### 3. 重启生效

```bash
docker compose restart
```

### 4. 查看日志

```bash
docker logs -f pcdnkeeper
```

## 配置说明

### 环境变量

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `LOOP_INTERVAL` | `20` | 每轮下载完成后的休眠秒数 |

### config.yaml 字段

#### global

| 字段 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `max_concurrent` | int | `4` | 最大并发下载任务数 |
| `resume` | bool | `false` | 断点续传（PCDN 流量模拟建议关闭） |
| `retry_times` | int | `3` | 单任务失败重试次数 |
| `timeout` | int | `1800` | 单任务超时秒数 |
| `skip_tls_verify` | bool | `false` | 跳过 TLS 证书验证 |
| `connections_per_file` | int | `16` | 单文件并发连接数 |
| `dry_run` | bool | `false` | 试运行模式（不实际下载） |

#### output

| 字段 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `save_path` | string | `/tmp/downloads` | 下载保存目录（容器内为 tmpfs） |

#### proxy

| 字段 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `http_proxy` | string | `""` | HTTP 代理地址 |
| `https_proxy` | string | `""` | HTTPS 代理地址 |

#### direct_tasks

任务列表，每个任务包含：

| 字段 | 类型 | 说明 |
|------|------|------|
| `name` | string | 任务名称（用于日志和统计） |
| `enable` | bool | 是否启用该任务 |
| `url` | string | 下载地址（支持 http/https） |
| `filename` | string | 保存文件名 |

## 数据目录

挂载的 `./data` 目录对应容器内 `/app/spde-node`，包含：

- `config/config.yaml`：下载任务配置
- `data/node-id.json`：节点永久唯一标识
- `data/run-history.jsonl`：每次下载的历史记录（JSON Lines 格式），包含下载字节数、耗时、平均速度、状态等

## docker-compose.yml

```yaml
services:
  pcdn-keeper:
    image: ghcr.io/pandamelive/pcdn-keeper:latest
    container_name: pcdnkeeper
    restart: always
    environment:
      - LOOP_INTERVAL=20
    volumes:
      # spde-node 工作目录（config.yaml、node-id.json、run-history.jsonl 均在此）
      - ./data:/app/spde-node
    logging:
      driver: "json-file"
      options:
        max-size: "5m"
        max-file: "3"
    tmpfs:
      - /tmp/downloads
```
