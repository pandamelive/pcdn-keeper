FROM alpine:latest

RUN apk update && apk add --no-cache \
    python3 \
    py3-requests \
    coreutils \
    ca-certificates \
    tzdata \
    bash

ENV TZ=Asia/Shanghai
WORKDIR /app

RUN mkdir -p /opt/init
COPY pcdn-keeper.sh /opt/init/pcdn-keeper.sh
RUN sed -i 's/\r$//' /opt/init/pcdn-keeper.sh \
    && chmod +x /opt/init/pcdn-keeper.sh

RUN mkdir -p /app/data

ENTRYPOINT ["/bin/bash","-c","\
if [ ! -f /app/data/pcdn-keeper.sh ];then \
  cp /opt/init/pcdn-keeper.sh /app/data/pcdn-keeper.sh; \
  chmod +x /app/data/pcdn-keeper.sh; \
fi; \
cd /app/data; \
exec bash /app/data/pcdn-keeper.sh \
"]

