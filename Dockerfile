FROM alpine:latest

ARG TARGETARCH=amd64
ARG PK_VERSION=unknown
ARG SPDE_VERSION=unknown

RUN apk add --no-cache ca-certificates tzdata curl bash

ENV TZ=Asia/Shanghai
ENV PK_VERSION=${PK_VERSION}
ENV SPDE_VERSION=${SPDE_VERSION}

WORKDIR /pnos
RUN mkdir -p controlcentre download

# 下载二进制（文件名带版本号: pk-v1.1-x86_64-linux-musl）
RUN PLATFORM=$([ "${TARGETARCH}" = "arm64" ] && echo aarch64-linux-musl || echo x86_64-linux-musl); \
    curl -fSL -o controlcentre/pk "https://github.com/pandamelive/pk/releases/download/v${PK_VERSION}/pk-v${PK_VERSION}-${PLATFORM}" && \
    curl -fSL -o download/spde "https://github.com/pandamelive/spde/releases/download/v${SPDE_VERSION}/spde-v${SPDE_VERSION}-${PLATFORM}" && \
    chmod +x controlcentre/pk download/spde

COPY entrypoint.sh entrypoint.sh
COPY pk-config.yaml pk-config.default.yaml
RUN chmod +x entrypoint.sh

ENTRYPOINT ["/bin/bash", "/pnos/entrypoint.sh"]
