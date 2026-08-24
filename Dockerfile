FROM alpine:latest
RUN apk add --no-cache curl coreutils ca-certificates tzdata
ENV TZ=Asia/Shanghai
WORKDIR /app

RUN mkdir -p /opt/init
COPY pcdn-keeper.sh /opt/init/pcdn-keeper.sh
RUN chmod +x /opt/init/pcdn-keeper.sh

RUN mkdir -p /app/data

ENTRYPOINT ["/bin/sh","-c","if [ ! -f /app/data/pcdn-keeper.sh ];then cp /opt/init/pcdn-keeper.sh /app/data/pcdn-keeper.sh;chmod +x /app/data/pcdn-keeper.sh;fi;exec /app/data/pcdn-keeper.sh"]
