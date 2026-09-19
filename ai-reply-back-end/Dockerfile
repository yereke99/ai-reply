# --- құрастыру кезеңі -------------------------------------------------------
FROM golang:1.24-alpine AS build

# SQLite драйвері cgo талап етеді.
RUN apk add --no-cache build-base ca-certificates tzdata

WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=1 GOOS=linux go build -trimpath -ldflags="-s -w" -o /out/server ./cmd/server

# --- жұмыс кезеңі -----------------------------------------------------------
FROM alpine:3.20

RUN apk add --no-cache ca-certificates tzdata && adduser -D -u 10001 aireply
WORKDIR /app

COPY --from=build /out/server /app/server
RUN mkdir -p /app/data && chown -R aireply:aireply /app

USER aireply
EXPOSE 8084
ENV APP_HOST=0.0.0.0 APP_PORT=8084 SQLITE_PATH=/app/data/aireply.db

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s \
  CMD wget -qO- http://127.0.0.1:8084/healthz || exit 1

ENTRYPOINT ["/app/server"]
