FROM alpine:latest

# ========== 仓库配置 ==========
ARG PK_REPO=pandamelive/pk
ARG SPDE_REPO=pandamelive/spde
ARG TARGETARCH=amd64
# 版本号（由 CI 从上游 latest release 获取，通过 build-arg 传入）
ARG PK_VERSION=unknown
ARG SPDE_VERSION=unknown
# ================================

RUN apk update && apk add --no-cache \
    ca-certificates \
    tzdata \
    curl \
    bash \
    jq

ENV TZ=Asia/Shanghai
# 版本号环境变量（entrypoint.sh 会用二进制 --version 覆盖为真实值，这里作为 fallback）
ENV PK_VERSION=${PK_VERSION}
ENV SPDE_VERSION=${SPDE_VERSION}
ENV PCDN_KEEPER_VERSION=pk-v${PK_VERSION}_spde-v${SPDE_VERSION}

WORKDIR /pnos

RUN mkdir -p /pnos/download /pnos/controlcentre

# 根据架构选择二进制资产名，下载到对应子目录
# 用指定版本号下载，确保与 CI 获取的版本一致（不依赖 latest 语义）
RUN if [ "${TARGETARCH}" = "arm64" ]; then \
        PK_ASSET="pk-aarch64-linux-musl"; \
        SPDE_ASSET="spde-aarch64-linux-musl"; \
    else \
        PK_ASSET="pk-x86_64-linux-musl"; \
        SPDE_ASSET="spde-x86_64-linux-musl"; \
    fi; \
    curl -fSL -o /pnos/controlcentre/pk \
        "https://github.com/${PK_REPO}/releases/download/v${PK_VERSION}/${PK_ASSET}" \
        && chmod +x /pnos/controlcentre/pk; \
    curl -fSL -o /pnos/download/spde \
        "https://github.com/${SPDE_REPO}/releases/download/v${SPDE_VERSION}/${SPDE_ASSET}" \
        && chmod +x /pnos/download/spde

# 镜像元数据
LABEL org.opencontainers.image.title="pcdn-keeper" \
      org.opencontainers.image.description="PK + SPDE minimal combo for PCDN traffic simulation" \
      org.opencontainers.image.version="pk-v${PK_VERSION}_spde-v${SPDE_VERSION}" \
      org.opencontainers.image.source="https://github.com/pandamelive/pcdn-keeper"

# 入口脚本和默认 pk 配置
COPY entrypoint.sh /pnos/entrypoint.sh
COPY pk-config.yaml /pnos/pk-config.default.yaml
RUN chmod +x /pnos/entrypoint.sh

ENTRYPOINT ["/bin/bash", "/pnos/entrypoint.sh"]
