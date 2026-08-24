FROM alpine:latest
RUN apk add --no-cache curl coreutils ca-certificates tzdata
ENV TZ=Asia/Shanghai
WORKDIR /app

# 把构建上下文的脚本打包进镜像内部 /app/keeper
RUN mkdir -p /app/keeper
COPY pcdn-keeper.sh /app/keeper/pcdn-keeper.sh
RUN chmod +x /app/keeper/pcdn-keeper.sh

# data目录依然做挂载，只存放统计和日志
RUN mkdir -p /app/data

ENTRYPOINT ["/app/keeper/pcdn-keeper.sh"]
