FROM alpine:latest

# ========== 仓库配置 ==========
ARG PK_REPO=pandamelive/pk
ARG SPDE_REPO=pandamelive/spde
ARG TARGETARCH=amd64
# ================================

RUN apk update && apk add --no-cache \
    ca-certificates \
    tzdata \
    curl \
    bash

ENV TZ=Asia/Shanghai

WORKDIR /pnos

RUN mkdir -p /pnos/download /pnos/controlcentre

# 根据架构选择二进制资产名，下载到对应子目录
RUN if [ "${TARGETARCH}" = "arm64" ]; then \
        PK_ASSET="pk-aarch64-linux-musl"; \
        SPDE_ASSET="spde-aarch64-linux-musl"; \
    else \
        PK_ASSET="pk-x86_64-linux-musl"; \
        SPDE_ASSET="spde-x86_64-linux-musl"; \
    fi; \
    curl -fSL -o /pnos/controlcentre/pk \
        "https://github.com/${PK_REPO}/releases/latest/download/${PK_ASSET}" \
        && chmod +x /pnos/controlcentre/pk; \
    curl -fSL -o /pnos/download/spde \
        "https://github.com/${SPDE_REPO}/releases/latest/download/${SPDE_ASSET}" \
        && chmod +x /pnos/download/spde

# 入口脚本和默认 pk 配置
COPY entrypoint.sh /pnos/entrypoint.sh
COPY pk-config.yaml /pnos/pk-config.default.yaml
RUN chmod +x /pnos/entrypoint.sh

ENTRYPOINT ["/bin/bash", "/pnos/entrypoint.sh"]
