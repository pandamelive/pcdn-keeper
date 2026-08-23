FROM alpine:latest

RUN apk add --no-cache aria2 \
    && rm -rf /var/cache/apk/*

WORKDIR /app

COPY pcdn-keeper.sh ./
RUN chmod +x ./pcdn-keeper.sh

ENTRYPOINT ["/app/pcdn-keeper.sh"]
