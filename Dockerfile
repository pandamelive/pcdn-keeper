FROM alpine:latest

# 安装curl + 证书包，--no-cache不保留apk缓存，镜像体积不会膨胀
RUN apk add --no-cache curl ca-certificates

WORKDIR /app

COPY pcdn-keeper.sh ./
RUN chmod +x ./pcdn-keeper.sh

ENTRYPOINT ["/app/pcdn-keeper.sh"]
