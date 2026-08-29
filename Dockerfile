FROM alpine:latest

# ========== 构建参数 ==========
ARG PK_REPO=pandamelive/pk
ARG SPDE_REPO=pandamelive/spde
ARG TARGETARCH=amd64
ARG PK_VERSION=unknown
ARG SPDE_VERSION=unknown
# ================================

RUN apk update && apk add --no-cache \
    ca-certificates tzdata curl bash jq

ENV TZ=Asia/Shanghai
ENV PK_VERSION=${PK_VERSION}
ENV SPDE_VERSION=${SPDE_VERSION}
ENV PCDN_KEEPER_VERSION=pk-v${PK_VERSION}_spde-v${SPDE_VERSION}

WORKDIR /pnos
RUN mkdir -p /pnos/download /pnos/controlcentre

# 根据架构选择平台，下载二进制
# 优先新格式文件名(pk-v1.1-x86_64-linux-musl)，失败回退旧格式(pk-x86_64-linux-musl)兼容历史release
RUN if [ "${TARGETARCH}" = "arm64" ]; then PLATFORM="aarch64-linux-musl"; else PLATFORM="x86_64-linux-musl"; fi; \
    curl -fSL -o /pnos/controlcentre/pk "https://github.com/${PK_REPO}/releases/download/v${PK_VERSION}/pk-v${PK_VERSION}-${PLATFORM}" \
      || curl -fSL -o /pnos/controlcentre/pk "https://github.com/${PK_REPO}/releases/download/v${PK_VERSION}/pk-${PLATFORM}"; \
    curl -fSL -o /pnos/download/spde "https://github.com/${SPDE_REPO}/releases/download/v${SPDE_VERSION}/spde-v${SPDE_VERSION}-${PLATFORM}" \
      || curl -fSL -o /pnos/download/spde "https://github.com/${SPDE_REPO}/releases/download/v${SPDE_VERSION}/spde-${PLATFORM}"; \
    chmod +x /pnos/controlcentre/pk /pnos/download/spde

# 完整性检查：文件存在且非空
RUN test -s /pnos/controlcentre/pk && test -s /pnos/download/spde \
    && echo "镜像版本: pk-v${PK_VERSION}_spde-v${SPDE_VERSION}，二进制完整性检查通过"

# 镜像元数据
LABEL org.opencontainers.image.title="pcdn-keeper" \
      org.opencontainers.image.description="PK + SPDE minimal combo for PCDN traffic simulation" \
      org.opencontainers.image.version="pk-v${PK_VERSION}_spde-v${SPDE_VERSION}" \
      org.opencontainers.image.source="https://github.com/pandamelive/pcdn-keeper"

COPY entrypoint.sh /pnos/entrypoint.sh
COPY pk-config.yaml /pnos/pk-config.default.yaml
RUN chmod +x /pnos/entrypoint.sh

ENTRYPOINT ["/bin/bash", "/pnos/entrypoint.sh"]
