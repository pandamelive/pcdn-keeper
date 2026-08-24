FROM alpine:latest

RUN apk add --no-cache curl coreutils ca-certificates

WORKDIR /app

RUN mkdir -p /app/data

ENTRYPOINT ["/app/data/pcdn-keeper.sh"]
