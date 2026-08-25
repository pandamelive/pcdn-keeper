# pcdn-keeper

[PK](https://github.com/pandamelive/pk) + [SPDE](https://github.com/pandamelive/spde) 最小结合体示例，一键 Docker 部署开箱即用。

一个容器同时运行 **PK 主控**（Web UI + API，端口 5566）和 **SPDE Agent 节点**（自动接入本地 PK），下载数据全部写入 tmpfs（内存文件系统），**完全不写磁盘**。

> 全部镜像由 GitHub Actions 自动构建，用户本地无需编译。

## 架构

```
pcdn-keeper 容器
├── /tmp                           下载目录（tmpfs 内存，完全不落盘）
└── /pnos/
    ├── entrypoint.sh              双进程启动器（pk + spde agent）
    ├── pk-config.default.yaml     默认 pk 配置模板
    ├── download/                  SPDE 二进制目录
    │   └── spde                   SPDE 下载引擎二进制
    └── controlcentre/             PK 目录
        ├── pk                     PK 主控二进制
        └── pk-controlcenter/      PK 工作目录（持久化挂载，宿主机 ./data）
            ├── config.yaml        PK 主控配置
            └── pk-data/
                ├── state.json     节点 / 任务 / 调度 / 运行记录
                └── artifacts/     各平台 SPDE 二进制（用于下发给外部节点）
```

- **PK 主控**：Axum Web 服务，内置 Web UI，负责节点管理、任务调度、流量统计
- **SPDE Agent**：以 agent 模式接入本地 PK，自动注册节点、拉取任务、回写结果
- **不落盘**：`/tmp` 挂载为 tmpfs，spde 下载数据写入内存，完全不碰磁盘
- **持久化**：宿主机 `./data` 映射到 pk 工作目录 `/pnos/controlcentre/pk-controlcenter`，配置和状态数据保留

## 特性

- PK + SPDE 双二进制打包，一个容器即开即用
- PK Web UI 可视化管理节点、创建下载任务、查看流量统计
- SPDE Agent 自动接入本地 PK，零配置节点注册
- 全部网络数据写入内存（tmpfs），无磁盘 IO
- 仅 PK 工作目录（pk-controlcenter）持久化，节点数据随容器重建
- docker compose 一键部署

## 快速使用

### 1. 启动容器

```bash
docker compose up -d
```

首次启动时如果 PK 配置不存在，容器会自动复制默认配置到 `./data/config.yaml`。

### 2. 打开 Web UI

浏览器访问 `http://<host>:5566`，即可看到 PK 主控面板。SPDE Agent 已自动注册为在线节点。

### 3. 创建下载任务

在 Web UI 中创建下载任务，调度到本地节点执行。也可通过 API：

```bash
curl -X POST http://127.0.0.1:5566/api/v1/tasks \
  -H "Content-Type: application/json" \
  -d '{"name":"测试","url":"http://example.com/file.zip","filename":"file.zip","target":"any"}'
```

### 4. 查看日志

```bash
docker logs -f pcdnkeeper
```

## 配置说明

### 环境变量

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `PK_LISTEN` | `0.0.0.0:5566` | PK 监听地址 |
| `PK_TOKEN` | `""` | PK API / Agent 鉴权 Bearer Token，留空则不鉴权 |
| `SPDE_MASTER` | `http://127.0.0.1:5566` | SPDE Agent 连接的 PK 地址（通常无需修改） |

### PK 配置文件

挂载路径：`./data/config.yaml`

```yaml
listen: "0.0.0.0:5566"
data_dir: null
heartbeat_timeout_secs: 45
token: ""
spde_defaults:
  max_concurrent: 4
  resume: false          # PCDN 流量模拟建议关闭，每次重新下载
  retry_times: 3
  timeout: 1800
  skip_tls_verify: false
  connections_per_file: 8
  # dry_run=true: 数据直接丢弃不落盘，仅统计速度和流量（PCDN 流量模拟推荐，安全）
  # dry_run=false: 实际写入 save_path（tmpfs 内存，注意大文件占满内存风险）
  dry_run: true
  save_path: "/tmp"   # 容器内 tmpfs 目录
  http_proxy: ""
  https_proxy: ""
```

修改配置后重启生效：`docker compose restart`

## 内存与落盘注意事项

`/tmp` 为 tmpfs 内存文件系统，下载数据写入内存而非磁盘，存在以下风险：

| 配置 | 行为 | 风险 |
|------|------|------|
| `dry_run: true`（默认） | 数据直接丢弃，仅统计速度和流量 | 无内存风险，推荐 PCDN 流量模拟使用 |
| `dry_run: false` | 实际写入 `/tmp` | 大文件可能占满 tmpfs，触发 ENOSPC 或容器 OOM |

如需实际落盘下载大文件，有两种方式：

1. **限制 tmpfs 上限**（防止内存爆掉）：
   ```yaml
   tmpfs:
     - /tmp:size=8G
   ```

2. **改为 bind 挂载**（数据落盘到宿主机磁盘）：
   ```yaml
   volumes:
     - ./data:/pnos/controlcentre/pk-controlcenter
     - ./downloads:/tmp
   ```
   同时移除 `tmpfs` 配置段。

> 容器启动时若检测到 `dry_run: false`，会在日志中输出内存风险警告。

## 数据目录

宿主机 `./data` 直接映射到容器内 pk 工作目录 `/pnos/controlcentre/pk-controlcenter`，包含：

- `config.yaml`：PK 主控配置
- `pk-data/state.json`：节点、任务、调度、运行记录（持久化核心）
- `pk-data/artifacts/`：各平台 SPDE 二进制，用于下发给外部节点

> SPDE 自身的 `spde-node/` 目录（node-id.json、run-history.jsonl）不持久化，容器重建后节点重新注册。流量统计以 PK 的 state.json 为准。

## docker-compose.yml

<!-- COMPOSE_START -->
```yaml
services:
  pcdn-keeper:
    image: ghcr.io/pandamelive/pcdn-keeper:latest
    container_name: pcdnkeeper
    restart: always
    ports:
      - "5566:5566"
    volumes:
      # pk 工作目录持久化（config.yaml、pk-data/state.json、artifacts/）
      - ./data:/pnos/controlcentre/pk-controlcenter
    tmpfs:
      # 下载目录用容器标准 /tmp，内存文件系统，完全不落盘
      - /tmp
    logging:
      driver: "json-file"
      options:
        max-size: "5m"
        max-file: "3"
    logging:
      driver: "json-file"
      options:
        max-size: "5m"
        max-file: "3"
```
<!-- COMPOSE_END -->

## 相关项目

- [PK](https://github.com/pandamelive/pk) — PandaNetPL 主控，生成、下发并控制 SPDE 节点
- [SPDE](https://github.com/pandamelive/spde) — Super-Download-Engine 统一下载中心
