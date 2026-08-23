# pcdn‑keeper
Docker PDN流量模拟工具，curl多线程下载，流量全部输出到 `/dev/null`，**完全不写入磁盘**。

> 全部镜像由 GitHub Actions 自动构建，用户本地无需编译。

## 特性
- alpine + curl
- 全部网络数据丢弃，无磁盘IO
- 多并发下载，可限制带宽
- docker 一键部署

## 快速使用
```yaml
services:
  pcdn-keeper:
    image: ghcr.io/pandamelive/pcdn-keeper:latest
    container_name: pcdnkeeper
    restart: always
    volumes:
      - /etc/localtime:/etc/localtime:ro
      - /etc/timezone:/etc/timezone:ro
    logging:
      driver: "json-file"
      options:
        max-size: "5m"
        max-file: "3"
    tmpfs:
      - /tmp
