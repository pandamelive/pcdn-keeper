FROM alpine:latest

RUN apk add --no-cache aria2 \
    && rm -rf /var/cache/apk/*

COPY traffic-keeper.sh /app/traffic-keeper.sh
RUN chmod +x /app/traffic-keeper.sh

WORKDIR /app
ENTRYPOINT ["/app/traffic-keeper.sh"]
