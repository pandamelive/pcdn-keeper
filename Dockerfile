FROM alpine:latest

# ========== 仓库配置 ==========
ARG PK_REPO=pandamelive/pk
ARG SPDE_REPO=pandamelive/spde
ARG TARGETARCH=amd64
# 版本号（由 CI 从上游 release assets 文件名提取，通过 build-arg 传入）
ARG PK_VERSION=unknown
ARG SPDE_VERSION=unknown
# CI 检测到的实际 asset 文件名（x86_64），用于日志和元数据
ARG PK_ASSET=pk-x86_64-linux-musl
ARG SPDE_ASSET=spde-x86_64-linux-musl
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

# 根据架构选择平台名，下载二进制
# 优先尝试带版本号的文件名（新格式 pk-v1.0-x86_64-linux-musl）
# 失败则回退到旧格式（pk-x86_64-linux-musl），兼容历史 release
RUN if [ "${TARGETARCH}" = "arm64" ]; then \
        PK_PLATFORM="aarch64-linux-musl"; \
        SPDE_PLATFORM="aarch64-linux-musl"; \
    else \
        PK_PLATFORM="x86_64-linux-musl"; \
        SPDE_PLATFORM="x86_64-linux-musl"; \
    fi; \
    echo "下载 pk (platform=${PK_PLATFORM}, version=${PK_VERSION})"; \
    if ! curl -fSL -o /pnos/controlcentre/pk \
        "https://github.com/${PK_REPO}/releases/download/v${PK_VERSION}/pk-v${PK_VERSION}-${PK_PLATFORM}"; then \
        echo "新格式文件名不存在，回退到旧格式 pk-${PK_PLATFORM}"; \
        curl -fSL -o /pnos/controlcentre/pk \
        "https://github.com/${PK_REPO}/releases/download/v${PK_VERSION}/pk-${PK_PLATFORM}"; \
    fi && chmod +x /pnos/controlcentre/pk; \
    echo "下载 spde (platform=${SPDE_PLATFORM}, version=${SPDE_VERSION})"; \
    if ! curl -fSL -o /pnos/download/spde \
        "https://github.com/${SPDE_REPO}/releases/download/v${SPDE_VERSION}/spde-v${SPDE_VERSION}-${SPDE_PLATFORM}"; then \
        echo "新格式文件名不存在，回退到旧格式 spde-${SPDE_PLATFORM}"; \
        curl -fSL -o /pnos/download/spde \
        "https://github.com/${SPDE_REPO}/releases/download/v${SPDE_VERSION}/spde-${SPDE_PLATFORM}"; \
    fi && chmod +x /pnos/download/spde

# ========== 版本校验（检查文件存在性和大小，不运行二进制——跨架构qemu模拟不可靠）==========
RUN echo "预期版本: pk=${PK_VERSION}, spde=${SPDE_VERSION}" && \
    echo "CI 检测 asset: pk=${PK_ASSET}, spde=${SPDE_ASSET}" && \
    echo "检查二进制文件..." && \
    if [ ! -f /pnos/controlcentre/pk ] || [ ! -s /pnos/controlcentre/pk ]; then \
        echo "ERROR: pk 二进制不存在或为空"; \
        exit 1; \
    fi && \
    if [ ! -f /pnos/download/spde ] || [ ! -s /pnos/download/spde ]; then \
        echo "ERROR: spde 二进制不存在或为空"; \
        exit 1; \
    fi && \
    PK_SIZE=$(stat -c%s /pnos/controlcentre/pk) && \
    SPDE_SIZE=$(stat -c%s /pnos/download/spde) && \
    echo "pk 大小: ${PK_SIZE} bytes" && \
    echo "spde 大小: ${SPDE_SIZE} bytes" && \
    if [ "${PK_SIZE}" -lt 1000000 ]; then \
        echo "ERROR: pk 二进制过小 (${PK_SIZE} bytes)，可能下载失败"; \
        exit 1; \
    fi && \
    if [ "${SPDE_SIZE}" -lt 1000000 ]; then \
        echo "ERROR: spde 二进制过小 (${SPDE_SIZE} bytes)，可能下载失败"; \
        exit 1; \
    fi && \
    echo "版本校验通过: pk-v${PK_VERSION}_spde-v${SPDE_VERSION} (文件完整性检查通过)"

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
