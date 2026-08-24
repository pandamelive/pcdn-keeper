FROM alpine:latest

ARG SPDE_VERSION=v0.2.1
ARG SPDE_ARCH=x86_64-linux-musl

RUN apk update && apk add --no-cache \
    ca-certificates \
    tzdata \
    curl \
    bash

ENV TZ=Asia/Shanghai
ENV LOOP_INTERVAL=20

WORKDIR /app

# 下载 spde 静态二进制
RUN curl -fSL -o /app/spde \
    "https://github.com/pandamelive/spde/releases/download/${SPDE_VERSION}/spde-${SPDE_ARCH}" \
    && chmod +x /app/spde

# 复制入口脚本和默认配置
COPY entrypoint.sh /opt/init/entrypoint.sh
COPY config.yaml /opt/init/config.yaml

RUN chmod +x /opt/init/entrypoint.sh \
    && mkdir -p /app/spde-node/config /app/spde-node/data /tmp/downloads

ENTRYPOINT ["/bin/bash", "-c", "\
mkdir -p /app/spde-node/config /app/spde-node/data; \
if [ ! -f /app/spde-node/config/config.yaml ]; then \
  cp /opt/init/config.yaml /app/spde-node/config/config.yaml; \
fi; \
exec /opt/init/entrypoint.sh \
"]
