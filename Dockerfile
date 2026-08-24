FROM alpine:latest
RUN apk add --no-cache curl coreutils ca-certificates tzdata
ENV TZ=Asia/Shanghai
WORKDIR /app
RUN mkdir -p /app/data
ENTRYPOINT ["/app/data/pcdn-keeper.sh"]
