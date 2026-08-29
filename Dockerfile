FROM alpine:3.20

ARG TARGETARCH=amd64
ARG PK_VERSION=unknown
ARG SPDE_VERSION=unknown

RUN apk add --no-cache bash curl ca-certificates tzdata

ENV TZ=Asia/Shanghai \
    PK_VERSION=${PK_VERSION} \
    SPDE_VERSION=${SPDE_VERSION}

WORKDIR /pnos

# 下载二进制（文件名带版本号: pk-v1.1-x86_64-linux-musl）
RUN PLATFORM=$([ "${TARGETARCH}" = "arm64" ] && echo aarch64-linux-musl || echo x86_64-linux-musl); \
    mkdir -p controlcentre download && \
    curl -fSL --retry 3 --retry-delay 2 -o controlcentre/pk \
      "https://github.com/pandamelive/pk/releases/download/v${PK_VERSION}/pk-v${PK_VERSION}-${PLATFORM}" && \
    curl -fSL --retry 3 --retry-delay 2 -o download/spde \
      "https://github.com/pandamelive/spde/releases/download/v${SPDE_VERSION}/spde-v${SPDE_VERSION}-${PLATFORM}" && \
    chmod +x controlcentre/pk download/spde

COPY --chmod=+x entrypoint.sh entrypoint.sh
COPY pk-config.yaml pk-config.default.yaml

ENTRYPOINT ["/bin/bash", "/pnos/entrypoint.sh"]
