FROM alpine:latest

RUN apk add --no-cache aria2 \
    && rm -rf /var/cache/apk/*

WORKDIR /app

COPY traffic-keeper.sh ./
RUN chmod +x ./traffic-keeper.sh

ENTRYPOINT ["/app/traffic-keeper.sh"]
